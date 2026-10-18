import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// In Tap mode the taps past the end of the list close the appraisal, so the last Pokémon is followed by frames that show its
/// name, CP and HP but no bars. Those frames must not make an extra row or change the last row.
final class TrailingNoBarsTests: XCTestCase {
    private var sample: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PogoAssist/PogoAssist/Resources/sample-scan.replay.jsonl")
    }

    private func key(_ r: ScanRow) -> String {
        let hp: String = r.hp.map { String($0) } ?? "-"
        let ivs: String = r.ivs.map { String($0.atk) + "/" + String($0.def) + "/" + String($0.hp) } ?? "-"
        let level: String = r.level.map { String($0) } ?? "-"
        return [r.speciesId, String(r.cp), hp, ivs, level, r.flags.joined(separator: ",")].joined(separator: " ")
    }

    func testTenBarlessFramesAfterTheLastPokemonChangeNothing() throws {
        let engine = CoreEngine()
        let base = try ScanPipeline.process(replay: sample, engine: engine)
        let lines = ReplayLog.lines(in: sample)
        // the last reading that has a name and a CP, copied ten times without bars, in time order after everything else
        var named = [ReplayReading](), end = 0.0
        for line in lines { if case .reading(let r) = line { end = max(end, r.t); if r.name != nil && r.cp != nil { named.append(r) } } }
        let lastReading = try XCTUnwrap(named.last)
        var data = try Data(contentsOf: sample)
        if data.last != UInt8(ascii: "\n") { data.append(UInt8(ascii: "\n")) }
        for i in 1...10 {
            var r = lastReading
            r.t = end + Double(i) * 0.25
            r.ivs = nil; r.ivConfidence = 0
            data.append(ReplayLog.encode(.reading(r))); data.append(UInt8(ascii: "\n"))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("trailing-\(UUID().uuidString).jsonl")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let with = try ScanPipeline.process(replay: url, engine: engine)
        XCTAssertEqual(with.scan.rows.count, base.scan.rows.count, "an extra row appeared")
        XCTAssertEqual(with.scan.rows.map(key), base.scan.rows.map(key), "a row changed")
        XCTAssertEqual(with.scan.unmatched.count, base.scan.unmatched.count)
    }
}
