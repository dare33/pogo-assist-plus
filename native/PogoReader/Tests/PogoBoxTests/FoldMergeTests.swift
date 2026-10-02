import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// Review findings folded in (M1 to M11, L1): written before the fixes, to fail first.
final class FoldMergeTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private func date(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(d) * 86_400) }
    private let x = IVs(atk: 15, def: 15, hp: 15), y = IVs(atk: 10, def: 14, hp: 13)

    private func row(_ id: String = "pikachu", cp: Int, hp: Int? = 60, ivs: IVs?, level: Double? = 20, dust: Int? = 1000, flags: [String] = []) -> ScanRow {
        let nf = GameMaster.nameAndForm(gm.byId[id]?.name ?? id)
        return ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: id, dex: gm.byId[id]?.dex, cp: cp, hp: hp, ivs: ivs, ivsRead: ivs, ivsGuess: nil,
                       level: level, levelMax: level, dust: dust, solveStatus: ivs == nil ? "unknown-ivs" : "exact", flags: flags, frames: [])
    }
    private func entry(_ r: ScanRow, _ id: String, corrections: Corrections = Corrections()) -> BoxEntry { BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0), corrections: corrections) }
    private func plan(_ s: [ScanRow], _ v: [BoxEntry], _ k: BoxStore.Kind = .full) -> BoxMerge.Plan { BoxMerge.plan(scanned: s, into: v, kind: k, scanDate: date(5), gameMaster: gm) }

    // M1: a field the scan did not read never replaces a saved one
    func testM1ChoosingASavedPokemonForAnIVlessReadKeepsItsIVsAndOtherValues() throws {
        let a = entry(row(cp: 500, ivs: x), "A"), b = entry(row(cp: 500, ivs: y), "B")
        var scanned = row(cp: 500, ivs: nil, level: nil, dust: nil); scanned.ivsRead = nil
        let p = plan([scanned], [a, b])
        XCTAssertEqual(p.unsure.first?.candidates.sorted(), ["A", "B"])
        let out = try BoxMerge.apply(p, resolutions: [0: .existing("A")], to: [a, b])
        XCTAssertEqual(out[0].row.ivs, x); XCTAssertEqual(out[0].row.ivsRead, x); XCTAssertEqual(out[0].row.hp, 60)
        XCTAssertEqual(out[0].row.level, 20); XCTAssertEqual(out[0].row.dust, 1000)
    }

    // M11 (and M1 for the update path)
    func testM11APowerUpWithHPUnreadKeepsTheSavedHP() throws {
        let saved = entry(row("machamp", cp: 2500, hp: 150, ivs: x), "m")
        var s = row("machamp", cp: 2600, hp: nil, ivs: x); s.level = nil; s.dust = nil
        let p = plan([s], [saved])
        XCTAssertEqual(p.updated.first?.reason, .poweredUp)
        let out = try BoxMerge.apply(p, to: [saved])
        XCTAssertEqual(out[0].row.cp, 2600); XCTAssertEqual(out[0].row.hp, 150); XCTAssertEqual(out[0].row.level, 20); XCTAssertEqual(out[0].row.dust, 1000)
    }

    // M3
    func testM3AMegaRowWithoutIVsAsksAgainstTheBaseEntries() {
        let a = entry(row("staraptor", cp: 2819, hp: 167, ivs: x), "a"), b = entry(row("staraptor", cp: 2500, hp: 160, ivs: y), "b")
        let p = plan([row("staraptor_mega", cp: 3970, hp: 190, ivs: nil)], [a, b])
        XCTAssertEqual(p.unsure.first?.candidates.sorted(), ["a", "b"]); XCTAssertTrue(p.new.isEmpty); XCTAssertTrue(p.gone.isEmpty)
        // no saved base entry: New under the base species, as before
        XCTAssertEqual(plan([row("staraptor_mega", cp: 3970, hp: 190, ivs: nil)], []).new, [0])
    }

    // M4
    func testM4ThePlausibleCandidatesAreAskedAboutNotAddedAndRemoved() {
        // powered up, IVs unread this time
        let machamp = entry(row("machamp", cp: 2500, hp: 150, ivs: x), "m")
        let p1 = plan([row("machamp", cp: 2600, hp: 155, ivs: nil)], [machamp])
        XCTAssertEqual(p1.unsure.first?.candidates, ["m"]); XCTAssertTrue(p1.new.isEmpty && p1.gone.isEmpty)
        // the reverse: the saved one has no IVs, the scan has them and the CP differs
        let noIVs = entry(row("machamp", cp: 2500, hp: 150, ivs: nil), "n")
        let p2 = plan([row("machamp", cp: 2600, hp: 155, ivs: x)], [noIVs])
        XCTAssertEqual(p2.unsure.first?.candidates, ["n"]); XCTAssertTrue(p2.new.isEmpty && p2.gone.isEmpty)
        // a LOWER CP with the same IVs
        let p3 = plan([row("machamp", cp: 2400, hp: 150, ivs: x)], [machamp])
        XCTAssertEqual(p3.unsure.first?.candidates, ["m"]); XCTAssertTrue(p3.new.isEmpty && p3.gone.isEmpty)
    }

    // M5
    func testM5APowerUpNeverLowersHPOrLevel() {
        let saved = entry(row("machamp", cp: 1532, hp: 120, ivs: x), "m")
        let lowerHP = plan([row("machamp", cp: 1582, hp: 110, ivs: x)], [saved])
        XCTAssertTrue(lowerHP.updated.isEmpty); XCTAssertEqual(lowerHP.unsure.first?.candidates, ["m"]); XCTAssertTrue(lowerHP.new.isEmpty)
        let lowerLevel = plan([row("machamp", cp: 1582, hp: 125, ivs: x, level: 18)], [saved])
        XCTAssertTrue(lowerLevel.updated.isEmpty); XCTAssertEqual(lowerLevel.unsure.count, 1)
        // a consistent power-up is still a power-up
        XCTAssertEqual(plan([row("machamp", cp: 1582, hp: 125, ivs: x, level: 21)], [saved]).updated.first?.reason, .poweredUp)
    }

    // M6
    func testM6TwoSavedWithTheSameIVsBothPoweredUpIsAskedNotPairedGreedily() {
        let a = entry(row(cp: 300, hp: 50, ivs: x), "a"), b = entry(row(cp: 400, hp: 60, ivs: x), "b")
        // scanned 400 and 500: b may be unchanged and a powered up to 500, or a to 400 and b to 500: two consistent answers
        let p = plan([row(cp: 400, hp: 60, ivs: x), row(cp: 500, hp: 70, ivs: x)], [a, b])
        XCTAssertTrue(p.same.isEmpty && p.updated.isEmpty, "no greedy pairing")
        XCTAssertEqual(p.unsure.count, 2); XCTAssertTrue(p.unsure.allSatisfy { $0.candidates.sorted() == ["a", "b"] })
        XCTAssertTrue(p.new.isEmpty && p.gone.isEmpty)
        // 1000/1200 saved, 1200/1500 scanned: the same trap
        let c = entry(row(cp: 1000, hp: 80, ivs: x), "c"), d = entry(row(cp: 1200, hp: 90, ivs: x), "d")
        XCTAssertEqual(plan([row(cp: 1200, hp: 90, ivs: x), row(cp: 1500, hp: 100, ivs: x)], [c, d]).unsure.count, 2)
        // all exact: pairs by count as before
        let ex = plan([row(cp: 300, hp: 50, ivs: x), row(cp: 400, hp: 60, ivs: x)], [a, b])
        XCTAssertEqual(ex.same.count, 2)
        // one consistent assignment only (300 -> 350, 400 -> 500): paired
        let u = plan([row(cp: 350, hp: 55, ivs: x), row(cp: 500, hp: 70, ivs: x)], [a, b])
        XCTAssertEqual(u.updated.count, 2); XCTAssertTrue(u.unsure.isEmpty)
        XCTAssertEqual(u.updated.first { $0.savedId == "a" }.map { u.scanned[$0.scanned].cp }, 350)
    }

    // M7
    func testM7IdenticalSavedOneHandCorrectedKeepsTheCorrectedOne() throws {
        let plain = entry(row(cp: 1000, ivs: x), "plain")
        let fixed = entry(row(cp: 1000, ivs: x), "fixed", corrections: Corrections(ivs: Fix(was: IVs(atk: 1, def: 1, hp: 1))))
        for order in [[plain, fixed], [fixed, plain]] {
            let p = plan([row(cp: 1000, ivs: x)], order)
            XCTAssertEqual(p.same, [BoxMerge.Pair(scanned: 0, savedId: "fixed")], "the corrected one survives whatever the saved order")
            XCTAssertEqual(p.gone, ["plain"])
            XCTAssertEqual(try BoxMerge.apply(p, to: order).map { $0.id }, ["fixed"])
        }
        XCTAssertTrue(plan([row(cp: 1000, ivs: x)], [plain, fixed], .partial).gone.isEmpty)
    }
}

final class FoldLibraryTests: XCTestCase {
    private var dir: URL!
    private var lib: BoxLibrary!
    override func setUpWithError() throws { dir = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-fold-\(UUID().uuidString)"); lib = BoxLibrary(root: dir) }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }
    private func date(_ n: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(n) * 3600) }

    // L1
    func testL1PreviousIsTheContentCurrentBeforeTheLatestChange() throws {
        try lib.commit(account: "a", entries: [], reason: .scan, note: "scan", now: date(1))           // 1
        try lib.commit(account: "a", entries: [], reason: .edit, note: "edit", now: date(2))           // 2
        try lib.commit(account: "a", entries: [], reason: .restore, note: "Restored version 1", restoredFrom: 1, now: date(3))   // 3
        try lib.commit(account: "a", entries: [], reason: .scan, note: "scan 2", now: date(4))         // 4
        XCTAssertEqual(try lib.previousVersion(account: "a")?.seq, 3, "version 3 holds the content that was current before version 4")
    }
}
