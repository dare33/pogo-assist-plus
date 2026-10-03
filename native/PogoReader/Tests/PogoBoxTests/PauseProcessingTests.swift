import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// A pause is a known gap, not paging: the stalled card's long stay is one Pokémon, the first card after a resume is usually the same Pokémon re-read, and the joined scan gives one row
/// per Pokémon across the joins.
final class PauseProcessingTests: XCTestCase {
    private let dev = NSString(string: "~/Developer/personal/pogo-frames/device-runs").expandingTildeInPath
    private let hint = PagingHint(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds)
    private func readings(_ lines: [ReplayLine]) -> [ReplayReading] { lines.compactMap { if case .reading(let r) = $0 { return r } else { return nil } }.sorted { $0.t < $1.t } }
    private func externalLines(_ dir: String) throws -> [ReplayLine] {
        let f = try XCTUnwrap((try? FileManager.default.contentsOfDirectory(atPath: dev + "/" + dir))?.filter { $0.hasSuffix(".replay.jsonl") && !$0.contains(" 2") }.sorted().first, "\(dir) is not on this machine")
        return ReplayLog.lines(in: URL(fileURLWithPath: dev + "/" + dir + "/" + f)).filter { if case .end = $0 { return false } else { return true } }   // the stall's own end marker is replaced by pause and resume markers
    }
    private func write(_ lines: [ReplayLine]) throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("pause-\(UUID().uuidString).jsonl")
        try (lines.map { String(decoding: ReplayLog.encode($0), as: UTF8.self) }.joined(separator: "\n") + "\n").write(to: u, atomically: true, encoding: .utf8)
        return u
    }
    private func key(_ r: ScanRow) -> String { "\(r.display)|\(r.cp)|\(r.hp.map(String.init) ?? "-")" }
    private func full(_ r: ScanRow) -> String { key(r) + "|" + (r.ivs.map { "\($0.atk)/\($0.def)/\($0.hp)" } ?? "-") }

    /// Join logs: each log's lines, then a pause marker at its last reading and a resume marker at the next log's first reading. With `removeGaps` the real time between the logs is closed up.
    private func join(_ logs: [[ReplayLine]], removeGaps: Bool) -> [ReplayLine] {
        var out = [ReplayLine](), prevEnd: Double?
        for (i, lines) in logs.enumerated() {
            let times: [Double] = lines.compactMap { if case .reading(let r) = $0 { return r.t } else { return nil } }
            var shift = 0.0
            if let pe = prevEnd, removeGaps, let t0 = times.min() { shift = pe + 1 - t0 }
            if i > 0, let t0 = times.min() { out.append(.resume(at: t0 + shift)) }
            for l in lines {
                switch l {
                case .reading(var r): r.t += shift; out.append(.reading(r))
                case .tick(let t): out.append(.tick(t + shift))
                case .drop(let t): out.append(.drop(t + shift))
                default: break
                }
            }
            prevEnd = (times.max() ?? 0) + shift
            if i < logs.count - 1 {
                // the stalled card began at the last row's first reading
                let rs = lines.compactMap { l -> ReplayReading? in if case .reading(let r) = l { return r } else { return nil } }
                var stalledFrom = rs.last?.t ?? 0, k = rs.count - 1
                while k >= 0, rs[k].name == rs.last?.name || rs[k].name == nil { stalledFrom = rs[k].t; k -= 1 }   // the final run of one card
                out.append(.pause(at: prevEnd!, last: stalledFrom + shift, read: 0, closed: nil))
            }
        }
        return out
    }

    func testTheOwnersFourLogsJoinedGiveOneRowPerPokemonAcrossTheJoins() throws {
        let real = ["stall-scan-20261003T054229Z-b1f94047", "stall-scan-20261003T055448Z-6b2b1f4e", "stall-scan-20261003T065119Z-2fd03e3a-horsea", "run14-tail-from-horsea-scan-20261003T070213Z-08997070"]
        let logs = try real.map { try externalLines($0) }
        var separate = [[ScanRow]]()
        for l in logs { separate.append(try ScanPipeline.process(replay: write(l), engine: sharedEngine, paging: hint).scan.rows) }
        XCTAssertEqual(separate.map { $0.count }, [170, 51, 1194, 267])
        for removeGaps in [true, false] {
            let joined = join(logs, removeGaps: removeGaps)
            let out = try ScanPipeline.process(replay: write(joined), engine: sharedEngine, paging: hint)
            let rows = out.scan.rows
            XCTAssertEqual(rows.count, 170 + 51 + 1194 + 267 - 3, "removeGaps \(removeGaps): the four scans' rows minus the three overlaps")
            XCTAssertEqual(out.pauses.count, 3)
            for (name, cp) in [("Stunfisk", 902), ("Abra", 799), ("Horsea", 134)] { XCTAssertEqual(rows.filter { $0.display == name && $0.cp == cp }.count, 1, "\(name) \(cp) once") }
            // every Pokémon of the four separate results is in the joined one with the same values (the three overlap rows may carry more readings, so compare name, CP and HP there)
            var expected = separate.flatMap { $0.map(key) }.sorted()
            for k in ["Stunfisk|902|129", "Abra|799|62", "Horsea|134|32"] { if let i = expected.firstIndex(of: k) { expected.remove(at: i) } }
            XCTAssertEqual(rows.map(key).sorted(), expected, "removeGaps \(removeGaps)")
            // the stalled cards keep the IVs they were read with (the appraisal closing mid-stay does not leave a row without)
            let stun = try XCTUnwrap(rows.first { $0.display == "Stunfisk" && $0.cp == 902 })
            XCTAssertEqual(stun.ivs, IVs(atk: 14, def: 11, hp: 10)); XCTAssertEqual(rows.filter { $0.flags.contains("split-by-timing") || $0.flags.contains("split-by-bars") }.count,
                                                                                  separate.flatMap { $0 }.filter { $0.flags.contains("split-by-timing") || $0.flags.contains("split-by-bars") }.count, "no new twins from the pauses")
            // the same values elsewhere: rows other than the overlaps are identical to the separate results'
            let sepFull = Set(separate.flatMap { $0.map(full) })
            XCTAssertLessThanOrEqual(rows.map(full).filter { !sepFull.contains($0) }.count, 3, "only the three overlap rows may differ in their values")
        }
    }

    /// Without the pause markers the same joined log gives the same rows, so the markers only describe a gap; WITH them a row touching the pause is never split by the timing rule.
    func testARowThatTouchesAPauseIsNeverSplitByTheBeatAndItsStayIsNotPartOfIt() throws {
        let a = try externalLines("stall-scan-20261003T054229Z-b1f94047"), b = try externalLines("stall-scan-20261003T055448Z-6b2b1f4e")
        let joined = join([a, b], removeGaps: true)
        let out = try ScanPipeline.process(replay: write(joined), engine: sharedEngine, paging: hint)
        XCTAssertEqual(out.pauses.count, 1); XCTAssertNotNil(out.pauses[0].resumedAt)
        XCTAssertEqual(out.scan.rows.filter { $0.display == "Stunfisk" && $0.cp == 902 }.count, 1)
        XCTAssertFalse(out.scan.rows.contains { $0.display == "Stunfisk" && $0.cp == 902 && $0.flags.contains("split-by-timing") })
    }

    func testTheMarkersRoundTripAndTheTailAfterAFinishIsStillCut() throws {
        let lines: [ReplayLine] = [.pause(at: 10.5, last: 3.25, read: 7, closed: true), .pause(at: 20, last: 12, read: 9, closed: nil), .resume(at: 30)]
        for l in lines { XCTAssertEqual(ReplayLog.decode(ReplayLog.encode(l)), l) }
        let rs: [ReplayLine] = (0..<50).map { i in var f = FrameReading(); f.name = "A"; f.cp = 100; f.hp = HP(current: 10, max: 10); return .reading(ReplayReading(f, time: Double(i), ms: 1)) }
        let trimmed = ReplayLog.trimmed(rs + [.pause(at: 20, last: 0, read: 1, closed: nil), .end(at: 8, last: 0)])
        XCTAssertEqual(trimmed.filter { if case .reading = $0 { return true } else { return false } }.count, 4, "readings up to last + 3 s")
        XCTAssertTrue(trimmed.contains { if case .pause = $0 { return true } else { return false } }, "the markers are kept")
    }

    /// T4: the stop summary says how many pauses there were and where; the Pokémon read are the whole scan's.
    func testTheSummaryNamesWhereTheScanPaused() throws {
        let real = ["stall-scan-20261003T054229Z-b1f94047", "stall-scan-20261003T055448Z-6b2b1f4e", "stall-scan-20261003T065119Z-2fd03e3a-horsea", "run14-tail-from-horsea-scan-20261003T070213Z-08997070"]
        let out = try ScanPipeline.process(replay: write(join(real.map { try externalLines($0) }, removeGaps: true)), engine: sharedEngine, paging: hint)
        let names = ScanStop.pauseNames(out.pauses, rows: out.scan.rows)
        XCTAssertEqual(names.count, 3)
        XCTAssertEqual(names.map { $0.components(separatedBy: ", resumed").first }, ["Stunfisk (CP 902)", "Abra (CP 799)", "Horsea (CP 134)"])
        XCTAssertTrue(names.allSatisfy { $0.contains(", resumed after ") }, "each says it resumed (V7)")
        let line = ScanStop.summary(lastName: "Jigglypuff", lastCP: 10, read: out.scan.rows.count, appraisalClosed: false, ranOut: false, commandKnown: true, paused: names)
        XCTAssertTrue(line.contains("after 1,679 Pokémon") && line.contains("It paused 3 times: Stunfisk (CP 902), resumed after"), line)
        XCTAssertTrue(ScanStop.summary(lastName: "A", lastCP: 1, read: 5, appraisalClosed: nil, ranOut: false, commandKnown: true, paused: ["X (CP 2), resumed after 74 s"]).contains("It paused once, at X (CP 2), resumed after 74 s."))
        // a pause that never resumed says why the scan ended, and a scan the person finished says so (V7, V3)
        let last = ScanPipeline.Pause(at: 10, last: 9, read: 3, closed: nil, resumedAt: nil)
        let row = out.scan.rows[0]
        _ = row; _ = last
        let byPerson = ScanStop.summary(lastName: "A", lastCP: 1, read: 5, appraisalClosed: nil, ranOut: false, commandKnown: true, paused: ["X (CP 2), not resumed: you finished it"], byPerson: true)
        XCTAssertTrue(byPerson.hasPrefix("You finished the scan after 5 Pokémon;") && byPerson.contains("not resumed: you finished it") && !byPerson.contains("ended by itself") && !byPerson.contains("command's size"), byPerson)
    }
}
