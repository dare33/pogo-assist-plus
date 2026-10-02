import Compression
import Foundation
import XCTest
@testable import PogoBox

/// A reader for binary property lists that keeps the UID type (Foundation turns UIDs into opaque objects), so the keyed archives
/// inside a commands file can be compared as plain structures, UIDs included.
indirect enum Tree: Equatable {
    case null, bool(Bool), int(Int), real(Double), string(String), uid(Int), data(Data), date(Double)
    case array([Tree]), dict([String: Tree])
}

enum BPlistReader {
    static func parse(_ d: Data) throws -> Tree {
        let b = [UInt8](d)
        guard b.count > 40, Array(b[0..<8]) == Array("bplist00".utf8) else { throw NSError(domain: "bplist", code: 1) }
        let t = b.count - 32
        let offSize = Int(b[t + 6]), refSize = Int(b[t + 7])
        func num(_ at: Int, _ n: Int) -> Int { (0..<n).reduce(0) { ($0 << 8) | Int(b[at + $1]) } }
        let count = num(t + 8, 8), top = num(t + 16, 8), tableStart = num(t + 24, 8)
        func offset(_ i: Int) -> Int { num(tableStart + i * offSize, offSize) }
        func length(_ at: inout Int, _ low: Int) -> Int {
            if low != 0xF { return low }
            let m = b[at]; at += 1
            let n = 1 << Int(m & 0x0F)
            defer { at += n }
            return num(at, n)
        }
        func read(_ i: Int) throws -> Tree {
            precondition(i < count)
            var at = offset(i)
            let m = b[at]; at += 1
            let hi = m >> 4, lo = Int(m & 0x0F)
            switch hi {
            case 0x0: return m == 0x08 ? .bool(false) : m == 0x09 ? .bool(true) : .null
            case 0x1: let n = 1 << lo; return .int(n == 8 ? Int(Int64(bitPattern: UInt64(num(at, 8)))) : num(at, n))
            case 0x2:
                let n = 1 << lo
                if n == 8 { return .real(Double(bitPattern: UInt64(num(at, 8)))) }
                return .real(Double(Float(bitPattern: UInt32(num(at, 4)))))
            case 0x3: return .date(Double(bitPattern: UInt64(num(at, 8))))
            case 0x4: let n = length(&at, lo); return .data(Data(b[at..<at + n]))
            case 0x5: let n = length(&at, lo); return .string(String(decoding: b[at..<at + n], as: UTF8.self))
            case 0x6: let n = length(&at, lo); return .string(String(utf16CodeUnits: (0..<n).map { UInt16(num(at + 2 * $0, 2)) }, count: n))
            case 0x8: return .uid(num(at, lo + 1))
            case 0xA:
                let n = length(&at, lo)
                return .array(try (0..<n).map { try read(num(at + $0 * refSize, refSize)) })
            case 0xD:
                let n = length(&at, lo)
                var out = [String: Tree]()
                for k in 0..<n {
                    guard case .string(let key) = try read(num(at + k * refSize, refSize)) else { throw NSError(domain: "bplist", code: 2) }
                    out[key] = try read(num(at + (n + k) * refSize, refSize))
                }
                return .dict(out)
            default: throw NSError(domain: "bplist", code: 3)
            }
        }
        return try read(top)
    }
}

final class VoiceCommandFileTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: Date(timeIntervalSince1970: 0).timeIntervalSinceReferenceDate * 0 + ISO8601DateFormatter().date(from: "2026-10-02T00:00:00Z")!.timeIntervalSinceReferenceDate)
    private let tap = CGPoint(x: 424, y: 775)

    private func reference(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name + ".vc", withExtension: "deflate", subdirectory: "Fixtures/voice"), "fixture \(name) missing")
        return try (Data(contentsOf: url) as NSData).decompressed(using: .zlib) as Data
    }

    /// The outer property list with every embedded archive decoded to a plain structure.
    private func normalised(_ data: Data) throws -> Tree {
        func walk(_ v: Any) throws -> Tree {
            switch v {
            case let d as Data: return d.starts(with: Array("bplist00".utf8)) ? try BPlistReader.parse(d) : .data(d)
            case let s as String: return .string(s)
            case let n as NSNumber:
                if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
                return CFNumberIsFloatType(n) ? .real(n.doubleValue) : .int(n.intValue)
            case let d as Date: return .date(d.timeIntervalSinceReferenceDate)
            case let a as [Any]: return .array(try a.map(walk))
            case let d as [String: Any]: return .dict(try d.mapValues(walk))
            default: throw NSError(domain: "walk", code: 1)
            }
        }
        return try walk(PropertyListSerialization.propertyList(from: data, options: [], format: nil))
    }

    private func assertSame(_ name: String, _ made: Data, file: StaticString = #filePath, line: UInt = #line) throws {
        let expected = try normalised(try reference(name)), actual = try normalised(made)
        if expected != actual {
            // find the first difference for a readable failure
            func diff(_ a: Tree, _ b: Tree, _ path: String) -> String? {
                switch (a, b) {
                case (.dict(let x), .dict(let y)):
                    for k in Set(x.keys).union(y.keys).sorted() { if let d = diff(x[k] ?? .null, y[k] ?? .null, path + "/" + k) { return d } }
                    return nil
                case (.array(let x), .array(let y)):
                    if x.count != y.count { return "\(path): \(x.count) items against \(y.count)" }
                    for (i, p) in zip(x, y).enumerated() { if let d = diff(p.0, p.1, path + "[\(i)]") { return d } }
                    return nil
                default: return a == b ? nil : "\(path): \(a) against \(b)"
                }
            }
            XCTFail("\(name) differs from the Python output at \(diff(expected, actual, "") ?? "?")", file: file, line: line)
        }
    }

    func testMatchesThePythonOutput() throws {
        try assertSame("swipe-normal-50", try VoiceCommandFile.make(count: 50, pace: .swipeNormal, batch: 50, now: now))
        try assertSame("swipe-normal-1427", try VoiceCommandFile.make(count: 1427, pace: .swipeNormal, batch: 50, now: now))
        try assertSame("swipe-fast-1427", try VoiceCommandFile.make(count: 1427, pace: .swipeFast, batch: 50, now: now))
        try assertSame("swipe-normal-51", try VoiceCommandFile.make(count: 51, pace: .swipeNormal, batch: 26, now: now))   // 2 x 26, not 2 x 50
        try assertSame("swipe-normal-3", try VoiceCommandFile.make(count: 3, pace: .swipeNormal, batch: 3, now: now))
        try assertSame("tap-normal-1427", try VoiceCommandFile.make(count: 1427, pace: .tapNormal, batch: 50, tap: tap, now: now))
        try assertSame("tap-fast-51", try VoiceCommandFile.make(count: 51, pace: .tapFast, batch: 26, tap: tap, now: now))
        try assertSame("tap-normal-3-fr_FR", try VoiceCommandFile.make(count: 3, pace: .tapNormal, batch: 3, locale: "fr_FR", tap: tap, now: now))
    }

    // MARK: names, identifiers, file names

    private func commands(_ data: Data) throws -> [(id: String, name: String, type: String)] {
        guard case .dict(let root) = try normalised(data), case .dict(let table)? = root["CommandsTable"] else { return [] }
        var out = [(String, String, String)]()
        for (id, v) in table {
            guard case .dict(let e) = v, case .dict(let names)? = e["CustomCommands"], case .array(let list)? = names.values.first, case .string(let n)? = list.first, case .string(let type)? = e["CustomType"] else { continue }
            out.append((id, n, type))
        }
        return out
    }

    func testEachModeHasItsOwnNamesAndStableIdentifiers() throws {
        typealias P = VoiceCommandFile.Pace
        XCTAssertEqual(P.tapNormal.title, "Scan"); XCTAssertEqual(P.tapNormal.commandName, "Pogo scan")
        XCTAssertEqual(P.tapFast.title, "Fast scan"); XCTAssertEqual(P.tapFast.commandName, "Pogo fast scan")
        XCTAssertEqual(P.swipeFast.title, "Swipe"); XCTAssertEqual(P.swipeFast.commandName, "Pogo swipe")
        XCTAssertEqual(P.tapNormal.secondsText, "1.2 s per Pokémon"); XCTAssertEqual(P.tapFast.secondsText, "1.0 s per Pokémon"); XCTAssertEqual(P.swipeFast.secondsText, "1.6 s per Pokémon")
        // distinct everywhere
        XCTAssertEqual(Set(P.allCases.map { $0.commandName }).count, 4)
        XCTAssertEqual(Set(P.allCases.map { $0.gestureName }).count, 4)
        XCTAssertEqual(Set(P.allCases.map { $0.idBase }).count, 4)
        // the gesture names share no word with any spoken command or with each other
        let spokenWords = Set(P.allCases.flatMap { $0.commandName.lowercased().split(separator: " ").map(String.init) })
        var seen = Set<String>()
        for p in P.allCases {
            for w in p.gestureName.lowercased().split(separator: " ").map(String.init) {
                XCTAssertFalse(spokenWords.contains(w), "\(w) is also in a spoken command")
                XCTAssertTrue(seen.insert(w).inserted, "\(w) is in two gesture names")
            }
        }
        // two files of one mode have the same names and identifiers; files of different modes share none
        var idsByMode = [P: Set<String>]()
        for p in P.allCases {
            let a = try commands(try VoiceCommandFile.make(count: 10, pace: p, batch: 10, tap: tap, now: now))
            let b = try commands(try VoiceCommandFile.make(count: 400, pace: p, batch: 50, tap: tap, now: now.addingTimeInterval(86_400)))
            XCTAssertEqual(Set(a.map { $0.id }), Set(b.map { $0.id }), "\(p) identifiers must not change between files")
            XCTAssertEqual(Set(a.map { $0.name }), [p.commandName, p.gestureName])
            XCTAssertEqual(a.count, 2)
            idsByMode[p] = Set(a.map { $0.id })
        }
        let all = idsByMode.values.reduce(into: [String]()) { $0 += $1 }
        XCTAssertEqual(Set(all).count, 8, "no two modes share an identifier")
        XCTAssertEqual(idsByMode[.tapNormal], ["Custom.780000000.000000", "Custom.780000060.000000"])
    }

    func testFileNames() {
        XCTAssertEqual(VoiceCommandFile.Pace.tapNormal.fileName(count: 300), "Pogo scan 300.voicecontrolcommands")
        XCTAssertEqual(VoiceCommandFile.Pace.tapFast.fileName(count: 300), "Pogo fast scan 300.voicecontrolcommands")
        XCTAssertEqual(VoiceCommandFile.Pace.swipeFast.fileName(count: 300), "Pogo swipe 300.voicecontrolcommands")
    }

    func testOnlyTapAndFastTapAreOfferedWhereTapIsCheckedElsewhereOnlySwipe() {
        XCTAssertEqual(VoiceCommandFile.Pace.offered(tapAvailable: true), [.tapNormal, .tapFast])
        XCTAssertEqual(VoiceCommandFile.Pace.offered(tapAvailable: false), [.swipeFast])
        XCTAssertEqual(VoiceCommandFile.Pace.defaultMode(tapAvailable: true), .tapNormal)
        XCTAssertEqual(VoiceCommandFile.Pace.defaultMode(tapAvailable: false), .swipeFast)
        XCTAssertEqual(VoiceCommandFile.Pace.tapFast.note, "misreads seen at this pace"); XCTAssertNil(VoiceCommandFile.Pace.tapNormal.note)
        // the 2.1 s swipe is still made by the generator, just not offered
        XCTAssertNoThrow(try VoiceCommandFile.make(count: 3, pace: .swipeNormal, batch: 3, now: now))
    }

    func testThePaceCheckNamesTheModeThatRan() {
        typealias P = VoiceCommandFile.Pace
        XCTAssertEqual(ScanPace.check(measured: 2.2, chosen: .tapNormal), "This scan ran at about 2.2 s per Pokémon, which is the Slow swipe pace; you had chosen Scan. Voice Control may have heard a different command.")
        XCTAssertNil(ScanPace.check(measured: 1.25, chosen: .tapNormal), "the chosen mode's own pace")
        XCTAssertNil(ScanPace.check(measured: 1.1, chosen: .tapNormal), "within 0.15 s of the chosen mode")
        XCTAssertEqual(ScanPace.check(measured: 1.0, chosen: .tapNormal), "This scan ran at about 1.0 s per Pokémon, which is the Fast scan pace; you had chosen Scan. Voice Control may have heard a different command.")
        XCTAssertEqual(ScanPace.check(measured: 1.6, chosen: .tapFast)?.contains("which is the Swipe pace; you had chosen Fast scan"), true)
        XCTAssertNil(ScanPace.check(measured: 3.5, chosen: .tapNormal), "near no mode: paced by hand")
        XCTAssertNil(ScanPace.check(measured: 1.6, chosen: .swipeFast))
        XCTAssertEqual(ScanPace.nearestMode(to: 2.2), .swipeNormal)
        XCTAssertEqual(ScanPace.nearestMode(to: 1.6), .swipeFast)
    }

    func testTheComparisonCanFail() throws {
        // a fast-swipe file is not the normal-swipe reference
        XCTAssertNotEqual(try normalised(try reference("swipe-normal-1427")), try normalised(try VoiceCommandFile.make(count: 1427, pace: .swipeFast, batch: 50, now: now)))
        XCTAssertNotEqual(try normalised(try reference("swipe-normal-1427")), try normalised(try VoiceCommandFile.make(count: 1427, pace: .swipeNormal, batch: 50, name: "Other", now: now)))
    }

    func testTheBinaryReaderAndWriterAgreeOnAHandBuiltValue() throws {
        let v = PV.dict([("a", .array([.int(1), .int(300), .int(70000), .real(1.5), .bool(true), .uid(5), .uid(300), .string("é"), .string(String(repeating: "x", count: 20))])), ("b", .null)])
        guard case .dict(let d) = try BPlistReader.parse(BinaryPlist.encode(v)), case .array(let a)? = d["a"] else { return XCTFail() }
        XCTAssertEqual(a, [.int(1), .int(300), .int(70000), .real(1.5), .bool(true), .uid(5), .uid(300), .string("é"), .string(String(repeating: "x", count: 20))])
    }

    func testSizing() {
        XCTAssertEqual(VoiceCommandFile.steps(storageCount: 1), 3, "minimum 3")
        XCTAssertEqual(VoiceCommandFile.steps(storageCount: 51), 51, "50 + 2% = 51")
        XCTAssertEqual(VoiceCommandFile.steps(storageCount: 1400), 1427, "1399 * 1.02 = 1426.98, rounded up")
        XCTAssertEqual(VoiceCommandFile.steps(storageCount: 101), 102, "100 + 2% = 102")
        let s = VoiceCommandFile.sizing(storageCount: 1400, pace: .swipeNormal)
        XCTAssertEqual([s.steps, s.batch, s.repeats, s.covers], [1427, 50, 29, 1450])
        XCTAssertEqual(s.estimatedSeconds, 29 * (50 * 2.1 + 0.8), accuracy: 0.001)
        // the batch is cut so the last repeat does not overshoot by almost a batch
        let b = VoiceCommandFile.sizing(storageCount: 51, pace: .swipeNormal)      // 51 steps
        XCTAssertEqual([b.steps, b.batch, b.repeats, b.covers], [51, 26, 2, 52])
        let c = VoiceCommandFile.sizing(storageCount: 101, pace: .swipeNormal)     // 102 steps -> 3 x 34
        XCTAssertEqual([c.steps, c.batch, c.repeats], [102, 34, 3])
        let d = VoiceCommandFile.sizing(storageCount: 99, pace: .swipeNormal)      // 100 steps
        XCTAssertEqual([d.steps, d.batch, d.repeats], [100, 50, 2])
        for n in [1, 2, 4, 20, 51, 52, 100, 101, 400, 1400, 3000] {
            let z = VoiceCommandFile.sizing(storageCount: n, pace: .swipeNormal)
            XCTAssertGreaterThanOrEqual(z.covers, z.steps); XCTAssertLessThan(z.covers - z.steps, z.repeats); XCTAssertLessThanOrEqual(z.batch, 50)
        }
        let small = VoiceCommandFile.sizing(storageCount: 10, pace: .tapFast)
        XCTAssertEqual([small.steps, small.batch, small.repeats], [10, 10, 1], "a small scan is one short batch, not 50 steps")
    }

    func testTapIsRefusedLeftOfTheRightEdgeAndOnUncheckedScreens() throws {
        // 0.95 * 440 = 418: 417.9 is refused, 418 is allowed
        XCTAssertThrowsError(try VoiceCommandFile.make(count: 3, pace: .tapNormal, batch: 3, tap: CGPoint(x: 417.9, y: 775), now: now)) {
            XCTAssertEqual($0 as? VoiceCommandFile.Failure, .tapTooFarLeft(x: 417.9, limit: 418))
        }
        XCTAssertThrowsError(try VoiceCommandFile.make(count: 3, pace: .tapNormal, batch: 3, tap: CGPoint(x: 300, y: 775), now: now))
        XCTAssertNoThrow(try VoiceCommandFile.make(count: 3, pace: .tapNormal, batch: 3, tap: CGPoint(x: 418, y: 775), now: now))
        XCTAssertThrowsError(try VoiceCommandFile.make(count: 3, pace: .tapFast, batch: 3, now: now)) { XCTAssertEqual($0 as? VoiceCommandFile.Failure, .needsTapPoint) }
        // the limit follows the screen width given
        XCTAssertThrowsError(try VoiceCommandFile.make(count: 3, pace: .tapNormal, batch: 3, tap: tap, screenWidth: 600, now: now))
        XCTAssertEqual(VoiceCommandFile.tapPoint(width: 440, height: 956), CGPoint(x: 424, y: 775))
        XCTAssertNil(VoiceCommandFile.tapPoint(width: 402, height: 874))
        // the checked point itself is right of the limit, and agrees with the measured fractions
        for s in VoiceCommandFile.checkedScreens {
            XCTAssertGreaterThanOrEqual(s.tapX, VoiceCommandFile.minTapXFraction * s.width)
        }
        XCTAssertEqual(424.0 / 440, VoiceCommandFile.measuredTapXFraction, accuracy: 0.002)
        XCTAssertEqual(775.0 / 956, VoiceCommandFile.measuredTapYFraction, accuracy: 0.002)
    }

    func testEveryTapIsAtExactlyTheSamePoint() throws {
        let data = try VoiceCommandFile.make(count: 50, pace: .tapNormal, batch: 50, tap: tap, now: now)
        guard case .dict(let root) = try normalised(data), case .dict(let table)? = root["CommandsTable"] else { return XCTFail() }
        var points = Set<String>()
        for case .dict(let entry) in table.values {
            guard case .dict(let archive)? = entry["CustomGesture"], case .array(let objects)? = archive["$objects"] else { continue }
            for case .dict(let o) in objects { if case .string(let s)? = o["NS.pointval"] { points.insert(s) } }
            for case .string(let s) in objects where s.hasPrefix("{") { points.insert(s) }
        }
        XCTAssertEqual(points, ["{424.0, 775.0}"])
    }

    func testTheFileSizeForABigBoxAndNoTapInASwipeFile() throws {
        let data = try VoiceCommandFile.make(count: VoiceCommandFile.steps(storageCount: 1400), pace: .swipeNormal, now: now)
        print("VOICE file for 1400 Pokémon, normal swipe: \(data.count) bytes")
        XCTAssertLessThan(data.count, 1_000_000)
    }
}
