import Foundation
import XCTest
@testable import PogoBox
import PogoReader

final class TroubleStretchTests: XCTestCase {
    /// Row `i` of a constructed scan: frames come 3 apart, so an unread card can sit between two rows.
    private func row(_ i: Int, flags: [String] = [], ivs: IVs? = IVs(atk: 1, def: 2, hp: 3)) -> ScanRow {
        ScanRow(index: i + 1, name: "Pokemon\(i)", display: "Pokemon\(i)", form: "", speciesId: "pidgey", dex: 16, cp: 100 + i, hp: 40, ivs: ivs, ivsRead: ivs, ivsGuess: nil, level: 5, levelMax: 5, dust: 200,
                solveStatus: "exact", flags: flags, frames: [FrameLabel(frame: "r\(i * 3)", time: Double(i), cp: nil, cpText: nil, name: nil, hp: nil, ivs: nil, ivConfidence: nil, sharpness: nil, clip: nil)])
    }
    private func hidden(_ i: Int) -> ScanRow { row(i, flags: ["cp-computed:\(100 + i)"]) }
    private func unread(after i: Int) -> Unmatched {
        Unmatched(frame: "r\(i * 3 + 1)", cp: nil, name: "Pidgey", nameText: nil, hp: 40, ivs: nil, cpOptions: [], frames: 1, reason: "cp-not-read", into: nil, clip: nil, count: nil, cpBefore: nil, cpAfter: nil, speciesIds: nil, stretch: nil)
    }
    private func scan(_ rows: [ScanRow], _ unmatched: [Unmatched] = []) -> ScanResult { ScanResult(rows: rows, review: [], unmatched: unmatched) }
    private func rows(_ n: Int, hiddenAt: Set<Int>) -> [ScanRow] { (0..<n).map { hiddenAt.contains($0) ? hidden($0) : row($0) } }

    // MARK: run 25

    /// The real scan of 5 Oct 2026: an alarm banner hid the CP of 139 cards in a row (positions 243 to 381 of 391) and 19 more could not be read.
    func testRun25IsOneCPHiddenStretchFrom243To381() throws {
        let s = try JSONDecoder().decode(ScanResult.self, from: Data(contentsOf: Fixture.url("run25-alarm-result.json")))
        XCTAssertEqual(s.rows.count, 391); XCTAssertEqual(s.unmatched.count, 19)
        let found = TroubleStretches.find(s)
        XCTAssertEqual(found.count, 1, "\(found)")
        let t = try XCTUnwrap(found.first)
        XCTAssertEqual(t.kind, .cpHidden); XCTAssertEqual(t.firstRow, 243); XCTAssertEqual(t.lastRow, 381)
        XCTAssertEqual(t.unreadCards, 19); XCTAssertEqual(t.count, 139 + 19); XCTAssertEqual(t.cleanRowsInside, 0)
        XCTAssertEqual(t.rowBefore, 242); XCTAssertEqual(t.cardBefore, TroubleStretch.Card(position: 242, name: "Snorlax", cp: 133))
        XCTAssertEqual(t.firstCard.name, "Smoliv"); XCTAssertEqual(t.firstCard.cp, 131)
        XCTAssertEqual(t.lastCard.name, "Rattata"); XCTAssertEqual(t.lastCard.cp, 67)
        // from the first affected row to the end: 391 - 243 rows, plus the 19 unread cards, all of which lie inside the stretch
        XCTAssertEqual(t.cardsToEnd, (391 - 243) + 19)
        // no bars stretch: only four rows have no IVs
        XCTAssertTrue(found.allSatisfy { $0.kind == .cpHidden })
    }

    // MARK: constructed

    func testFewerThanTheMinimumIsNeverReported() {
        XCTAssertTrue(TroubleStretches.find(scan(rows(30, hiddenAt: Set(10..<14)))).isEmpty, "four in a row")
        XCTAssertEqual(TroubleStretches.find(scan(rows(30, hiddenAt: Set(10..<15)))).count, 1, "five in a row")
        XCTAssertEqual(TroubleStretches.find(scan(rows(30, hiddenAt: Set(10..<14))), minimum: 4).count, 1)
        XCTAssertTrue(TroubleStretches.find(scan(rows(30, hiddenAt: [3, 9, 15, 21, 27]))).isEmpty, "isolated failures")
    }

    func testTwoCleanRowsInsideDoNotSplitButThreeDo() throws {
        // failures 10..12, two clean (13, 14), failures 15..17: one stretch of six
        let one = TroubleStretches.find(scan(rows(30, hiddenAt: [10, 11, 12, 15, 16, 17])))
        XCTAssertEqual(one.count, 1); XCTAssertEqual(one[0].count, 6); XCTAssertEqual(one[0].cleanRowsInside, 2); XCTAssertEqual(one[0].firstRow, 10); XCTAssertEqual(one[0].lastRow, 17)
        // three clean rows split it into 3 + 3, each under the minimum
        XCTAssertTrue(TroubleStretches.find(scan(rows(30, hiddenAt: [10, 11, 12, 16, 17, 18]))).isEmpty)
        // three clean rows between two real stretches: two stretches
        let two = TroubleStretches.find(scan(rows(40, hiddenAt: Set(5..<10).union(Set(13..<19)))))
        XCTAssertEqual(two.map { [$0.firstRow, $0.lastRow, $0.count] }, [[5, 9, 5], [13, 18, 6]])
        XCTAssertEqual(two[1].rowBefore, 12); XCTAssertEqual(two[0].rowBefore, 4)
    }

    func testUnreadCardsInsideCountAndNeverBreakAStretch() throws {
        let rs = rows(30, hiddenAt: Set(10..<14))
        let s = scan(rs, [unread(after: 11), unread(after: 12), unread(after: 3)])   // two inside, one far away
        let t = try XCTUnwrap(TroubleStretches.find(s).first)
        XCTAssertEqual(t.firstRow, 10); XCTAssertEqual(t.lastRow, 13); XCTAssertEqual(t.unreadCards, 2); XCTAssertEqual(t.count, 6)
        XCTAssertEqual(t.cardsToEnd, (30 - 10) + 2, "the unread card at row 3 is before the stretch")
        // an unread card of another reason is neither counted nor does it break the stretch
        var other = unread(after: 11); other.reason = "absorbed"
        let t2 = try XCTUnwrap(TroubleStretches.find(scan(rows(30, hiddenAt: Set(10..<15)), [other])).first)
        XCTAssertEqual(t2.unreadCards, 0); XCTAssertEqual(t2.count, 5)
    }

    func testUnreadCardsThatCannotBePlacedAreNotCounted() {
        var floating = unread(after: 11); floating.frame = nil
        let s = scan(rows(30, hiddenAt: Set(10..<15)), [floating])
        XCTAssertEqual(TroubleStretches.find(s).first?.unreadCards, 0)
        // a stretch of five failures is not made by unread cards that cannot be placed
        XCTAssertTrue(TroubleStretches.find(scan(rows(30, hiddenAt: Set(10..<12)), [floating, floating, floating])).isEmpty)
    }

    func testABarsUnreadStretchIsFoundFromRowsWithoutIVsOrTheFlag() throws {
        var rs = rows(40, hiddenAt: [])
        for i in 20..<24 { rs[i] = row(i, ivs: nil) }
        rs[24] = row(24, flags: ["ivs-unread"])
        let found = TroubleStretches.find(scan(rs))
        XCTAssertEqual(found.count, 1)
        let t = try XCTUnwrap(found.first)
        XCTAssertEqual(t.kind, .barsUnread); XCTAssertEqual(t.firstRow, 20); XCTAssertEqual(t.lastRow, 24); XCTAssertEqual(t.count, 5); XCTAssertEqual(t.rowBefore, 19)
        XCTAssertEqual(t.cardsToEnd, 20)
    }

    func testAStretchAtTheStartHasNoRowBeforeAndKindsAreSeparate() throws {
        let rs = rows(20, hiddenAt: Set(0..<6))
        let t = try XCTUnwrap(TroubleStretches.find(scan(rs)).first)
        XCTAssertNil(t.rowBefore); XCTAssertNil(t.cardBefore); XCTAssertEqual(t.cardsToEnd, 20)
        // the same rows also without IVs: both kinds are reported, in order of first row then kind
        var both = rs; for i in 0..<6 { both[i].ivs = nil }
        XCTAssertEqual(TroubleStretches.find(scan(both)).map { $0.kind }, [.barsUnread, .cpHidden])
    }

    // MARK: the older device logs

    /// Evidence for the thresholds, not an assertion about them: walks every device log through the pipeline and writes every stretch it finds. Needs PROBE_RUNS (the device-runs folder) and STRETCH_OUT.
    func testReportStretchesInTheDeviceLogs() throws {
        let env = ProcessInfo.processInfo.environment
        guard let runs = env["PROBE_RUNS"], let outPath = env["STRETCH_OUT"] else { throw XCTSkip("no probe env") }
        var logs = [URL]()
        for case let u as URL in FileManager.default.enumerator(at: URL(fileURLWithPath: runs), includingPropertiesForKeys: nil)! where u.lastPathComponent.hasSuffix("replay.jsonl") { logs.append(u) }
        logs.sort { $0.path < $1.path }
        var text = ""
        for u in logs {
            let tag = u.deletingLastPathComponent().lastPathComponent + "/" + u.lastPathComponent
            for (mode, hint) in [("nohint", nil as PagingHint?), ("hint", PagingHint(pagedByCommand: true, expectedPeriod: 1.2))] {
                do {
                    let o = try ScanPipeline.process(replay: u, engine: CoreEngine(), paging: hint)
                    let found = TroubleStretches.find(o.scan)
                    text += "\(tag) \(mode) rows=\(o.scan.rows.count) stretches=\(found.count)\n"
                    for t in found { text += "    \(t.kind) rows \(t.firstRow)-\(t.lastRow) count \(t.count) unread \(t.unreadCards) clean-inside \(t.cleanRowsInside) before \(t.rowBefore.map(String.init) ?? "-") first \(t.firstCard.name) \(t.firstCard.cp) toEnd \(t.cardsToEnd)\n" }
                } catch { text += "\(tag) \(mode) ERROR \(error)\n" }
            }
        }
        try text.write(toFile: outPath, atomically: true, encoding: .utf8)
    }
}
