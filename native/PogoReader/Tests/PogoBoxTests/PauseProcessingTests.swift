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
                out.append(.pause(at: prevEnd!, last: stalledFrom + shift, read: (i + 1) * 1000, closed: nil))   // distinct counts, as in real logs: Pokémon were read between the pauses
            }
        }
        return out
    }

    func testTheOwnersFourLogsJoinedGiveOneRowPerPokemonAcrossTheJoins() throws {
        let real = ["stall-scan-20261003T054229Z-b1f94047", "stall-scan-20261003T055448Z-6b2b1f4e", "stall-scan-20261003T065119Z-2fd03e3a-horsea", "run14-tail-from-horsea-scan-20261003T070213Z-08997070"]
        let logs = try real.map { try externalLines($0) }
        var separate = [[ScanRow]]()
        for l in logs { separate.append(try ScanPipeline.process(replay: write(l), engine: sharedEngine, paging: hint).scan.rows) }
        // run14's tail holds the Charmander CP 12 triplet (three bar states), owner-confirmed 4 Oct 2026: 267 became 269 when it was cut
        XCTAssertEqual(separate.map { $0.count }, [170, 51, 1194, 269])
        for removeGaps in [true, false] {
            let joined = join(logs, removeGaps: removeGaps)
            let out = try ScanPipeline.process(replay: write(joined), engine: sharedEngine, paging: hint)
            let rows = out.scan.rows
            XCTAssertEqual(rows.count, 170 + 51 + 1194 + 269 - 3, "removeGaps \(removeGaps): the four scans' rows minus the three overlaps")
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

    /// A synthetic command scan on a steady 1.2 s beat: twelve different Pokémon, the seventh held for two beats (the timing rule splits that into twins). `pause` adds a pause marker
    /// at the long stay (and a resume marker after it when `resume`).
    private func beatLog(pause: Bool, resume: Bool) -> [ReplayLine] {
        let names = ["Pidgey", "Rattata", "Zubat", "Weedle", "Caterpie", "Magikarp", "Geodude", "Oddish", "Bellsprout", "Poliwag", "Abra", "Machop"]
        var lines = [ReplayLine](), t = 0.0, longStart = 0.0, longEnd = 0.0
        for (k, n) in names.enumerated() {
            let beats = k == 6 ? 2.0 : 1.0
            if k == 6 { longStart = t }
            var u = 0.0
            while u < beats * 1.2 - 0.01 {
                var f = FrameReading(); f.name = n; f.baseName = n; f.form = ""; f.speciesIds = [n.lowercased()]; f.cp = 200 + k * 13; f.hp = HP(current: 40 + k, max: 40 + k); f.ivs = IVs(atk: k % 16, def: (k * 3) % 16, hp: (k * 5) % 16); f.ivConfidence = 1
                lines.append(.reading(ReplayReading(f, time: t + u, ms: 1))); u += 0.3
            }
            t += beats * 1.2
            if k == 6 { longEnd = t }
        }
        if pause { lines.append(.pause(at: longEnd + 0.5, last: longStart, read: 7, closed: nil)); if resume { lines.append(.resume(at: longEnd + 1.2)) } }
        return lines
    }

    /// The pause markers reach the refine step: the long stay that the timing rule would split into twins is one Pokémon held for a gap when a pause touches it. Checked the way a
    /// mutation would show it: with the markers removed (or `hint.pauses` not set in `ScanPipeline`) the same log gives the extra twin.
    func testARowThatTouchesAPauseIsNotSplitIntoTwinsByTheBeat() throws {
        func rows(_ lines: [ReplayLine]) throws -> ScanPipeline.Outcome { try ScanPipeline.process(replay: write(lines), engine: sharedEngine, paging: hint) }
        let plain = try rows(beatLog(pause: false, resume: false))
        XCTAssertEqual(plain.scan.rows.count, 13, "no pause: the two-beat stay is two twins by the timing rule")
        XCTAssertTrue(plain.scan.rows.contains { $0.flags.contains("split-by-timing") })
        let paused = try rows(beatLog(pause: true, resume: true))
        XCTAssertEqual(paused.scan.rows.count, 12, "a pause touches it: one Pokémon held for a gap")
        XCTAssertFalse(paused.scan.rows.contains { $0.flags.contains("split-by-timing") })
        XCTAssertEqual(paused.pauses.count, 1); XCTAssertNotNil(paused.pauses[0].resumedAt)
        // a pause that was never answered (no resume marker) protects the same row, and every later one
        let open = try rows(beatLog(pause: true, resume: false))
        XCTAssertEqual(open.scan.rows.count, 12); XCTAssertNil(open.pauses[0].resumedAt)
    }

    /// N1b: a pause with no Pokémon read since the one before (the same read count) is the same stall, so the earlier pause is not reported as resumed.
    func testASecondPauseWithNothingReadSinceIsTheSameStall() throws {
        let base = beatLog(pause: true, resume: true)
        let again = base + [.pause(at: 40, last: 8.4, read: 7, closed: nil)]
        let same = try ScanPipeline.process(replay: write(again), engine: sharedEngine, paging: hint)
        XCTAssertEqual(same.pauses.count, 1); XCTAssertNil(same.pauses[0].resumedAt, "it did not resume: the resume read nothing")
        let more = base + [.pause(at: 40, last: 8.4, read: 9, closed: nil)]
        let other = try ScanPipeline.process(replay: write(more), engine: sharedEngine, paging: hint)
        XCTAssertEqual(other.pauses.count, 2); XCTAssertNotNil(other.pauses[0].resumedAt, "Pokémon were read since: a real resume")
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
        // 1,681 (was 1,679): the Charmander CP 12 triplet, owner-confirmed 4 Oct 2026
        XCTAssertTrue(line.contains("after 1,681 Pokémon") && line.contains("It paused 3 times: Stunfisk (CP 902), resumed after"), line)
        XCTAssertTrue(ScanStop.summary(lastName: "A", lastCP: 1, read: 5, appraisalClosed: nil, ranOut: false, commandKnown: true, paused: ["X (CP 2), resumed after 74 s"]).contains("It paused once, at X (CP 2), resumed after 74 s."))
        // a pause that never resumed says why the scan ended (the timeout, or the person), taken from a real pipeline outcome whose pause has no resume marker (V7, V3)
        let unresumed = try ScanPipeline.process(replay: write(beatLog(pause: true, resume: false)), engine: sharedEngine, paging: hint)
        XCTAssertNil(unresumed.pauses[0].resumedAt)
        let timeoutNames = ScanStop.pauseNames(unresumed.pauses, rows: unresumed.scan.rows)
        XCTAssertEqual(timeoutNames.count, 1); XCTAssertTrue(timeoutNames[0].hasSuffix(", not resumed: the scan finished at the timeout"), timeoutNames[0])
        XCTAssertTrue(ScanStop.pauseNames(unresumed.pauses, rows: unresumed.scan.rows, finishedByPerson: true)[0].hasSuffix(", not resumed: you finished it"))
        XCTAssertFalse(timeoutNames[0].contains("resumed after"))
        let byPerson = ScanStop.summary(lastName: "A", lastCP: 1, read: 5, appraisalClosed: nil, ranOut: false, commandKnown: true, paused: ["X (CP 2), not resumed: you finished it"], byPerson: true)
        XCTAssertTrue(byPerson.hasPrefix("You finished the scan after 5 Pokémon;") && byPerson.contains("not resumed: you finished it") && !byPerson.contains("ended by itself") && !byPerson.contains("command's size"), byPerson)
    }
}
