import Foundation
import CoreGraphics
import ImageIO

/// Gray PNG encoding of a crop: a third of the size of colour, and Vision reads the text the same.
enum GrayPNG {
    static func encode(_ img: RGBAImage) -> Data? {
        guard img.width > 0, img.height > 0 else { return nil }
        return autoreleasepool {
            var gray = [UInt8](repeating: 0, count: img.width * img.height)
            for y in 0..<img.height { for x in 0..<img.width { gray[y * img.width + x] = UInt8(max(0, min(255, img.luma(x, y).rounded()))) } }
            guard let provider = CGDataProvider(data: Data(gray) as CFData),
                  let cg = CGImage(width: img.width, height: img.height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: img.width,
                                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(dest, cg, nil)
            return CGImageDestinationFinalize(dest) ? data as Data : nil
        }
    }

    static func decode(_ data: Data) -> RGBAImage? {
        autoreleasepool {
            guard let src = CGImageSourceCreateWithData(data as CFData, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
            let w = cg.width, h = cg.height
            var gray = [UInt8](repeating: 0, count: w * h)
            let ok = gray.withUnsafeMutableBytes { raw -> Bool in
                guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard ok else { return nil }
            var out = RGBAImage(width: w, height: h)
            for i in 0..<(w * h) { out.bytes[i * 4] = gray[i]; out.bytes[i * 4 + 1] = gray[i]; out.bytes[i * 4 + 2] = gray[i]; out.bytes[i * 4 + 3] = 255 }
            return out
        }
    }
}

/// Which frames "save crops" mode keeps: at most `maxCropFramesPerSegment` per on-screen segment, the
/// second frame of it and then one every 0.4 s, and only once the bars have settled (so the frame is a
/// settled card). A card with no HP bar never settles its bars (they are not looked for), so it is kept
/// on timing alone, as is a segment whose bars never settle (its fifth frame). A segment ends at a swipe:
/// the grouper's rule (`swipeSeparatorSeconds` of frames with no anchors), on the pixel evidence alone.
/// All of it is by the frames' times, so a dropped frame does not change which are kept.
public struct CropSaver {
    private var sepStart: Double?
    private var sepLast = 0.0
    private var segStart = 0.0
    private var saved = 0
    private var lastSavedT = -Double.infinity
    private var segment = 0
    private var started = false
    private var clock = 0.0
    private var lastCardT = -Double.infinity
    private var lastTick = -Double.infinity

    public init() {}

    /// A swipe seen by the luma signature at `time` (see `SwipeDetector`): the next settled card starts a new segment.
    public mutating func noteSwipe(at time: Double) { if time.isFinite { lastTick = max(lastTick, time) } }

    /// Decides, and when it says yes stamps the frame's segment number into `a`.
    public mutating func shouldSave(_ a: inout FrameAnalysis) -> Bool {
        let t = max(a.time ?? (clock + Tuning.framePeriod), clock)
        clock = t
        let eps = 1e-9
        if !a.needsText {
            if sepStart == nil { sepStart = t }
            sepLast = t
            return false
        }
        let tick = lastTick > lastCardT + eps && lastTick < t - eps
        let swipe = !started || tick || (sepStart != nil && sepLast - sepStart! + Tuning.framePeriod >= Tuning.swipeSeparatorSeconds - eps)
        sepStart = nil
        lastCardT = t
        if swipe { segStart = t; saved = 0; lastSavedT = -Double.infinity; segment += 1; started = true }
        guard saved < Tuning.maxCropFramesPerSegment, t - segStart >= Tuning.framePeriod - eps, t - lastSavedT >= 2 * Tuning.framePeriod - eps else { return false }
        guard a.barsSettled || a.cpOnly || (saved == 0 && t - segStart >= 4 * Tuning.framePeriod - eps) else { return false }
        saved += 1
        lastSavedT = t
        a.segment = segment
        return true
    }
}

/// A folder of saved frames: per frame the analysis as one line of JSON (`NNNNNN.json`) and the
/// crops as gray PNGs (`NNNNNN-cp.png`, `-name.png`, `-nameup.png`, `-hp.png`). Capped in files and
/// bytes. Written by the extension in "save crops" mode, read and then emptied by the app.
public final class CropArchive {
    public let directory: URL
    public private(set) var fileCount = 0
    public private(set) var byteCount = 0
    public private(set) var frameCount = 0
    private var next = 1
    private let maxFiles: Int, maxBytes: Int

    public init(directory: URL, maxFiles: Int = Tuning.maxSavedFiles, maxBytes: Int = Tuning.maxSavedBytes) {
        self.directory = directory
        self.maxFiles = maxFiles
        self.maxBytes = maxBytes
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = frameURLs()
        frameCount = existing.count
        next = (existing.last.flatMap { Int($0.deletingPathExtension().lastPathComponent) } ?? 0) + 1
        for u in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? [] {
            fileCount += 1
            byteCount += (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
    }

    /// Frame JSON files in order.
    public func frameURLs() -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Write one frame. Returns false (and writes nothing) when a cap would be passed.
    @discardableResult
    public func save(_ a: FrameAnalysis, _ crops: FrameCrops) -> Bool {
        let id = String(format: "%06d", next)
        var parts: [(String, Data)] = []
        for (suffix, img) in [("cp", crops.cp), ("name", crops.name), ("nameup", crops.nameUp), ("hp", crops.hp)] {
            if let img = img, let d = GrayPNG.encode(img) { parts.append((suffix, d)) }
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let json = try? enc.encode(a) else { return false }
        let bytes = parts.reduce(json.count) { $0 + $1.1.count }
        guard fileCount + parts.count + 1 <= maxFiles, byteCount + bytes <= maxBytes else { return false }
        for (suffix, d) in parts { try? d.write(to: directory.appendingPathComponent("\(id)-\(suffix).png"), options: .atomic) }
        // The JSON goes last: a frame exists once its line does, so a kill mid-save leaves no half frame.
        do { try (json + Data("\n".utf8)).write(to: directory.appendingPathComponent("\(id).json"), options: .atomic) } catch { return false }
        next += 1; frameCount += 1; fileCount += parts.count + 1; byteCount += bytes
        return true
    }

    /// Load a saved frame; absent crops come back empty.
    public func load(_ jsonURL: URL) -> (FrameAnalysis, FrameCrops)? {
        guard let data = try? Data(contentsOf: jsonURL), let a = try? JSONDecoder().decode(FrameAnalysis.self, from: data) else { return nil }
        let id = jsonURL.deletingPathExtension().lastPathComponent
        func crop(_ suffix: String) -> RGBAImage? {
            (try? Data(contentsOf: directory.appendingPathComponent("\(id)-\(suffix).png"))).flatMap(GrayPNG.decode)
        }
        let empty = RGBAImage(width: 0, height: 0)
        return (a, FrameCrops(cp: crop("cp"), name: crop("name") ?? empty, nameUp: crop("nameup") ?? empty, hp: crop("hp") ?? empty))
    }

    /// Delete the given saved frames (their JSON line and crops) and nothing else: frames written after a read began,
    /// or ones that could not be read, stay.
    public func remove(frames jsonURLs: [URL]) {
        for u in jsonURLs {
            let id = u.deletingPathExtension().lastPathComponent
            for suffix in ["cp", "name", "nameup", "hp"] {
                let f = directory.appendingPathComponent("\(id)-\(suffix).png")
                if let size = (try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize { byteCount -= size; fileCount -= 1 }
                try? FileManager.default.removeItem(at: f)
            }
            if let size = (try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize { byteCount -= size; fileCount -= 1 }
            try? FileManager.default.removeItem(at: u)
            frameCount = max(0, frameCount - 1)
        }
    }

    /// Delete everything in the folder.
    public func removeAll() {
        for u in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] { try? FileManager.default.removeItem(at: u) }
        fileCount = 0; byteCount = 0; frameCount = 0
    }
}

/// The app's half of "save crops" mode: Vision on the saved crops through the same `FrameReader.complete`.
public enum DeferredRun {
    /// Read the saved frames in order; each reading comes with its segment number. `removeWhenDone` deletes the
    /// frames that were read (and only those) afterwards; `consumed` lists them for a caller that deletes later.
    public static func read(archive: CropArchive, reader: FrameReader, removeWhenDone: Bool = true) -> (frames: [(segment: Int?, reading: FrameReading)], consumed: [URL]) {
        var out = [(segment: Int?, reading: FrameReading)]()
        var consumed = [URL]()
        for url in archive.frameURLs() {
            autoreleasepool {
                if let (a, crops) = archive.load(url) { out.append((a.segment, reader.complete(a, crops))); consumed.append(url) }
            }
        }
        if removeWhenDone { archive.remove(frames: consumed) }
        return (out, consumed)
    }

    /// Read, group, return both (and the frames read). The saved frames of different segments had a swipe between
    /// them that was not saved, so the grouper is given a swipe tick between them (and a few empty frames).
    public static func readAndGroup(archive: CropArchive, reader: FrameReader, species: SpeciesTable?, removeWhenDone: Bool = true) -> (readings: [FrameReading], rows: [LiveRow], consumed: [URL]) {
        let result = read(archive: archive, reader: reader, removeWhenDone: removeWhenDone)
        var g = LiveGrouper(species: species)
        var previous: Int?? = .none
        var lastTime = 0.0
        for (segment, reading) in result.frames {
            if let p = previous, p != segment {
                // The real gap was at least a swipe long: tell the grouper so, midway between the two readings.
                g.swipe(at: lastTime + Tuning.framePeriod)
                var gap = FrameReading(frame: nil, time: lastTime + 2 * Tuning.framePeriod); gap.flags = ["mid-swipe"]; g.add(gap)
            }
            previous = .some(segment)
            g.add(reading)
            lastTime = reading.time ?? lastTime + Tuning.framePeriod
        }
        g.finish()
        return (result.frames.map(\.reading), g.rows, result.consumed)
    }
}
