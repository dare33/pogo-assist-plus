import Foundation

/// One line of the extension's replay log (`replay.jsonl`): what the grouper was given, in the order it was given, so a
/// device run can be replayed through any grouper offline. Readings carry the fields the grouper uses; a swipe tick is the
/// time the luma signature confirmed a swipe; a drop is the time of a frame that was kept at 5 fps but dropped because the
/// reader was busy (or skipped for low memory).
public enum ReplayLine: Equatable {
    case reading(ReplayReading)
    case tick(Double)
    case drop(Double)
}

public struct ReplayReading: Codable, Equatable {
    public var k = "r"
    public var t: Double
    public var cp: Int?
    public var cpText: String
    public var name: String?
    public var nameText: String
    public var nameWeak: Bool?
    public var nameAttached: Bool?
    public var speciesIds: [String]?
    public var hp: HP?
    public var hpText: String
    public var ivs: IVs?
    public var ivConfidence: Double
    public var flags: [String]
    /// Milliseconds the read took.
    public var ms: Double

    public init(_ r: FrameReading, time: Double, ms: Double) {
        t = time; cp = r.cp; cpText = r.cpText; name = r.name; nameText = r.nameText; nameWeak = r.nameWeak
        nameAttached = r.nameAttached; speciesIds = r.speciesIds; hp = r.hp; hpText = r.hpText; ivs = r.ivs
        ivConfidence = r.ivConfidence; flags = r.flags; self.ms = ms
    }

    /// The reading as the grouper was given it.
    public var frameReading: FrameReading {
        var r = FrameReading(frame: nil, time: t)
        r.cp = cp; r.cpText = cpText; r.cpReads = cp.map { [$0] } ?? []; r.name = name; r.nameText = nameText; r.nameWeak = nameWeak
        r.nameAttached = nameAttached; r.speciesIds = speciesIds; r.hp = hp; r.hpText = hpText; r.ivs = ivs
        r.ivConfidence = ivConfidence; r.flags = flags
        return r
    }
}

private struct ReplayEvent: Codable { var k: String; var t: Double }

public enum ReplayLog {
    /// One compact JSON object, no newline.
    public static func encode(_ line: ReplayLine) -> Data {
        let enc = JSONEncoder()
        switch line {
        case .reading(let r): return (try? enc.encode(r)) ?? Data()
        case .tick(let t): return (try? enc.encode(ReplayEvent(k: "t", t: t))) ?? Data()
        case .drop(let t): return (try? enc.encode(ReplayEvent(k: "d", t: t))) ?? Data()
        }
    }

    public static func decode(_ data: Data) -> ReplayLine? {
        let dec = JSONDecoder()
        guard let head = try? dec.decode(ReplayEvent.self, from: data) else { return nil }
        switch head.k {
        case "r": return (try? dec.decode(ReplayReading.self, from: data)).map { .reading($0) }
        case "t": return .tick(head.t)
        case "d": return .drop(head.t)
        default: return nil
        }
    }

    /// Every decodable line of a file, in file order (a damaged or half-written last line is skipped).
    public static func lines(in url: URL) -> [ReplayLine] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return data.split(separator: UInt8(ascii: "\n")).compactMap { decode(Data($0)) }
    }

    public struct Result {
        public var rows: [LiveRow]
        public var readings: Int, ticks: Int, drops: Int
    }

    /// Feed the lines through a `LiveGrouper` in file order, which is the order the extension gave them to its own
    /// grouper (ticks drained right before the reading that followed them), and return the rows.
    public static func replay(_ lines: [ReplayLine], species: SpeciesTable?) -> Result {
        var g = LiveGrouper(species: species)
        var res = Result(rows: [], readings: 0, ticks: 0, drops: 0)
        for line in lines {
            switch line {
            case .reading(let r): g.add(r.frameReading); res.readings += 1
            case .tick(let t): g.swipe(at: t); res.ticks += 1
            case .drop: res.drops += 1       // a dropped frame carries no reading; it is in the log for the record
            }
        }
        g.finish()
        res.rows = g.rows
        return res
    }
}

/// Appends replay lines to a file, one line at a time (nothing is buffered beyond the line being written). Capped in
/// bytes: past the cap it stops and says so. Any write error disables it for good and is reported once; it never throws.
public final class ReplayWriter {
    public enum Outcome { case written, truncatedNow, failedNow, disabled }

    public private(set) var truncated = false
    public private(set) var failed = false
    public private(set) var bytes = 0
    public private(set) var lineCount = 0
    private var handle: FileHandle?
    private var sink: ((Data) throws -> Void)?
    private let maxBytes: Int

    /// Creates (truncates) the file; nil if it cannot be opened.
    public init?(url: URL, maxBytes: Int = Tuning.maxReplayLogBytes) {
        self.maxBytes = maxBytes
        guard FileManager.default.createFile(atPath: url.path, contents: nil), let h = try? FileHandle(forWritingTo: url) else { return nil }
        handle = h
        sink = { try h.write(contentsOf: $0) }
    }

    /// Tests: a writer over any sink (to make a write fail).
    init(sink: @escaping (Data) throws -> Void, maxBytes: Int = Tuning.maxReplayLogBytes) { self.sink = sink; self.maxBytes = maxBytes }

    @discardableResult
    public func append(_ line: ReplayLine) -> Outcome {
        guard let write = sink, !failed, !truncated else { return .disabled }
        var data = ReplayLog.encode(line)
        data.append(UInt8(ascii: "\n"))
        if bytes + data.count > maxBytes { truncated = true; close(); return .truncatedNow }
        do { try write(data) } catch { failed = true; close(); return .failedNow }
        bytes += data.count; lineCount += 1
        return .written
    }

    public func close() { try? handle?.close(); handle = nil; sink = nil }
}
