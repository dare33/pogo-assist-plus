import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// One IV triple has to explain both readings, or a saved entry is not offered as the same Pokémon powered up (run12: 24 of 25 "is it this one?" questions were answered "new").
final class ShareIVTripleTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private func date(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(d) * 86_400) }
    private func row(_ id: String, cp: Int, hp: Int?, ivs: IVs?) -> ScanRow {
        let nf = GameMaster.nameAndForm(gm.byId[id]?.name ?? id)
        return ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: id, dex: gm.byId[id]?.dex, cp: cp, hp: hp, ivs: ivs, ivsRead: ivs, ivsGuess: nil,
                       level: 20, levelMax: 20, dust: 1000, solveStatus: ivs == nil ? "unknown-ivs" : "exact", flags: [], frames: [])
    }
    private func entry(_ r: ScanRow, _ id: String) -> BoxEntry { BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0)) }
    private func plan(_ s: [ScanRow], _ v: [BoxEntry]) -> BoxMerge.Plan { BoxMerge.plan(scanned: s, into: v, kind: .full, scanDate: date(5), gameMaster: gm) }
    private let max = IVs(atk: 15, def: 15, hp: 15)

    // Real numbers from the first long scan (run12).
    func testMeowth534WithBarsAgainstASavedMeowth65WithUnreadIVsIsNotACandidate() {
        let p = plan([row("meowth", cp: 534, hp: 90, ivs: max)], [entry(row("meowth", cp: 65, hp: 29, ivs: nil), "m")])
        XCTAssertTrue(p.unsure.isEmpty, "no IV triple makes a CP 65 / HP 29 Meowth into a CP 534 / HP 90 one with 15/15/15")
        XCTAssertEqual(p.new, [0])
    }

    func testCombee367AgainstASavedCombee51WithTheSameIVsIsStillAsked() {
        // as in the scan: several Combee with 15/15/15 against the one saved Combee (a straight power-up when there is one, a question when there are more)
        let p = plan([row("combee", cp: 367, hp: 79, ivs: max), row("combee", cp: 296, hp: 71, ivs: max)], [entry(row("combee", cp: 51, hp: 29, ivs: max), "c")])
        XCTAssertEqual(p.unsure.map { $0.candidates }, [["c"], ["c"]], "the same 15/15/15 fits both: legitimate")
        // the leftover rule on its own (a different IV read on the saved side cannot make it impossible): unread IVs on the scanned side
        XCTAssertEqual(plan([row("combee", cp: 367, hp: 79, ivs: nil)], [entry(row("combee", cp: 51, hp: 29, ivs: max), "c")]).unsure.map { $0.candidates }, [["c"]])
    }

    func testAGenuinePowerUpWithUnreadIVsOnTheSavedSideIsStillAsked() {
        let base = gm.byId["pikachu"]!.baseStats!, ivs = IVs(atk: 10, def: 11, hp: 12)
        let saved = row("pikachu", cp: cpAt(base, ivs, 10), hp: hpAt(base, ivs, 10), ivs: nil)
        let up = row("pikachu", cp: cpAt(base, ivs, 20), hp: hpAt(base, ivs, 20), ivs: ivs)
        XCTAssertEqual(plan([up], [entry(saved, "s")]).unsure.map { $0.candidates }, [["s"]])
        // and with IVs unread on the scanned side instead
        XCTAssertEqual(plan([row("pikachu", cp: up.cp, hp: up.hp, ivs: nil)], [entry(row("pikachu", cp: saved.cp, hp: saved.hp, ivs: ivs), "s")]).unsure.map { $0.candidates }, [["s"]])
        // a "power-up" to a LOWER level than the saved one is not one
        let down = row("pikachu", cp: cpAt(base, ivs, 5), hp: hpAt(base, ivs, 5), ivs: ivs)
        XCTAssertTrue(plan([down], [entry(row("pikachu", cp: cpAt(base, ivs, 20), hp: hpAt(base, ivs, 20), ivs: nil), "s")]).unsure.isEmpty)
    }

    func testAZubatThatCannotBeTheSavedOneIsNew() {
        // saved Zubat CP 61 / HP 29 (IVs unread); a CP 362 / HP 80 Zubat with 13/10/15 cannot share its IVs: level 20 and HP 80 need base 120 + 15 at 0.597
        let zubat = gm.byId["zubat"]!.baseStats!
        let scanned = row("zubat", cp: 362, hp: 80, ivs: IVs(atk: 13, def: 10, hp: 15))
        let saved = entry(row("zubat", cp: 61, hp: 29, ivs: nil), "z")
        // computed from the formulas, not asserted by hand: the saved entry is a candidate exactly when an IV triple explains both
        let fits = IVFit()
        let a = fits.ranges(zubat, cp: 61, hp: 29)[IVFit.index(IVs(atk: 13, def: 10, hp: 15))]
        let b = fits.ranges(zubat, cp: 362, hp: 80)[IVFit.index(IVs(atk: 13, def: 10, hp: 15))]
        let shared = (a != nil && b != nil && b!.upperBound >= a!.lowerBound)
        XCTAssertEqual(plan([scanned], [saved]).unsure.isEmpty, !shared)
        XCTAssertFalse(shared, "with 13/10/15 a Zubat of CP 61 has HP 29 nowhere")
    }

    func testAnEvolutionWithUnreadIVsMustShareAnIVTripleToo() {
        let machop = gm.byId["machop"]!.baseStats!, machoke = gm.byId["machoke"]!.baseStats!
        let ivs = IVs(atk: 12, def: 13, hp: 14)
        let saved = row("machop", cp: cpAt(machop, ivs, 12), hp: hpAt(machop, ivs, 12), ivs: ivs)
        let evolved = row("machoke", cp: cpAt(machoke, ivs, 12), hp: hpAt(machoke, ivs, 12), ivs: nil)
        XCTAssertEqual(plan([evolved], [entry(saved, "m")]).unsure.map { $0.candidates }, [["m"]], "the real evolution is asked about")
        // a Machoke whose CP and HP no shared IV triple could give from that Machop: not offered
        let other = row("machoke", cp: cpAt(machoke, IVs(atk: 0, def: 0, hp: 0), 40), hp: hpAt(machoke, IVs(atk: 0, def: 0, hp: 0), 40), ivs: nil)
        let strong = row("machop", cp: cpAt(machop, IVs(atk: 15, def: 15, hp: 15), 5), hp: hpAt(machop, IVs(atk: 15, def: 15, hp: 15), 5), ivs: IVs(atk: 15, def: 15, hp: 15))
        XCTAssertTrue(plan([other], [entry(strong, "m")]).unsure.isEmpty, "a 15/15/15 Machop cannot become a Machoke that needs 0/0/0 to give that CP")
    }

    func testAReadingTheAppAlreadyFlaggedAsMisreadNeverVetoesAnythingButAnImpossibleOneDoes() {
        var misread = row("pikachu", cp: 400, hp: 1, ivs: nil); misread.flags = ["no-level-fits"]
        XCTAssertEqual(plan([row("pikachu", cp: 500, hp: 60, ivs: nil)], [entry(misread, "s")]).unsure.map { $0.candidates }, [["s"]], "flagged: not judged")
        // the same numbers without the flag fit no level: nothing fits, so not a candidate
        XCTAssertTrue(plan([row("pikachu", cp: 500, hp: 60, ivs: nil)], [entry(row("pikachu", cp: 400, hp: 1, ivs: nil), "s")]).unsure.isEmpty)
    }

    /// The real scan, merged into the low-CP saved entries of the four species it asked about. Skipped when the log is not on this machine.
    func testRun12QuestionsAgainstTheLowCPSavedEntries() throws {
        let dir = NSString(string: "~/Developer/personal/pogo-frames/device-runs/run12-tap-1500").expandingTildeInPath
        let url = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: dir).first { $0.hasSuffix(".result.json") }.map { URL(fileURLWithPath: dir + "/" + $0) }, "run12 not on this machine")
        let saved: [BoxEntry] = [
            entry(row("zubat", cp: 61, hp: nil, ivs: nil), "zubat61"),
            entry(row("meowth", cp: 65, hp: 29, ivs: nil), "meowth65"),
            entry(row("combee", cp: 51, hp: 29, ivs: max), "combee51"),
            entry(row("psyduck", cp: 40, hp: 24, ivs: IVs(atk: 2, def: 0, hp: 11)), "psyduck40"),
        ]
        let scan = try JSONDecoder().decode(ScanResult.self, from: Data(contentsOf: url)).rows.filter { ["Zubat", "Meowth", "Combee", "Psyduck"].contains($0.name) }
        let before = BoxMerge.plan(scanned: scan, into: saved, kind: .partial, scanDate: date(5), gameMaster: gm, shareIVs: false)
        let after = BoxMerge.plan(scanned: scan, into: saved, kind: .partial, scanDate: date(5), gameMaster: gm)
        let names = after.unsure.map { "\(scan[$0.scanned].name) \(scan[$0.scanned].cp)" }
        print("RUN12 questions on the four species: \(before.unsure.count) before, \(after.unsure.count) after: \(names)")
        XCTAssertLessThan(after.unsure.count, before.unsure.count)
    }

    /// The second 300-Pokémon run merged into the box the first one made (the same phone's list a few minutes apart): 306 the same, 4 unsure before this rule.
    func testRun9IntoTheRun8BoxStillHasTheSameCountsAndNoMoreQuestions() throws {
        let hint = PagingHint(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds)
        let r8 = try ScanPipeline.process(replay: Fixture.url("device-run8-tap-300.replay.jsonl"), engine: sharedEngine, paging: hint)
        let r9 = try ScanPipeline.process(replay: Fixture.url("device-run9-tap-300b.replay.jsonl"), engine: sharedEngine, paging: hint)
        let box = r8.scan.rows.enumerated().map { BoxEntry(id: "e\($0.offset)", row: $0.element, firstSeen: date(0), lastSeen: date(0)) }
        let before = BoxMerge.plan(scanned: r9.scan.rows, into: box, kind: .full, scanDate: date(5), gameMaster: gm, shareIVs: false)
        let after = BoxMerge.plan(scanned: r9.scan.rows, into: box, kind: .full, scanDate: date(5), gameMaster: gm)
        print("RUN9INTO8 before: same \(before.same.count) updated \(before.updated.count) unsure \(before.unsure.count) new \(before.new.count) gone \(before.gone.count); after: same \(after.same.count) updated \(after.updated.count) unsure \(after.unsure.count) new \(after.new.count) gone \(after.gone.count)")
        XCTAssertGreaterThanOrEqual(after.same.count, before.same.count)
        XCTAssertLessThanOrEqual(after.unsure.count, before.unsure.count)
    }
}
