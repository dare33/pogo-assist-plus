import Foundation
import XCTest
@testable import PogoBox
import PogoReader

final class PartialReadTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private func date(_ day: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(day) * 86_400) }
    private func row(_ id: String = "staraptor", cp: Int, hp: Int? = 142, ivs: IVs? = IVs(atk: 13, def: 12, hp: 15), flags: [String] = []) -> ScanRow {
        let nf = GameMaster.nameAndForm(gm.byId[id]?.name ?? id)
        return ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: id, dex: gm.byId[id]?.dex, cp: cp, hp: hp, ivs: ivs, ivsRead: ivs, ivsGuess: nil,
                       level: 20, levelMax: 20, dust: 1000, solveStatus: "exact", flags: flags, frames: [])
    }
    private func entry(_ r: ScanRow, _ id: String) -> BoxEntry { BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0)) }
    private func plan(_ s: [ScanRow], _ v: [BoxEntry], _ k: BoxStore.Kind = .partial) -> BoxMerge.Plan { BoxMerge.plan(scanned: s, into: v, kind: k, scanDate: date(5), gameMaster: gm) }
    private let junk: (Int, Int?) -> ScanRow = { _, _ in fatalError() }

    private func partial(cp: Int = 182, hp: Int? = 142) -> ScanRow { row(cp: cp, hp: hp, ivs: nil, flags: ["no-level-fits"]) }

    /// The owner's case: a part read "182" of the saved Staraptor CP 1982, HP 142, next to the real read of it.
    func testThePartReadOfASavedPokemonIsUnsureNotNew() throws {
        let saved = entry(row(cp: 1982), "a")
        let p = plan([row(cp: 1982), partial()], [saved])
        XCTAssertEqual(p.same, [BoxMerge.Pair(scanned: 0, savedId: "a")])
        XCTAssertEqual(p.unsure, [BoxMerge.Unsure(scanned: 1, candidates: ["a"], kind: .partialRead)])
        XCTAssertTrue(p.new.isEmpty)
        // answers: new adds it, leave it out drops it, "this one" only marks seen and keeps the real values
        XCTAssertThrowsError(try BoxMerge.apply(p, to: [saved]))
        XCTAssertEqual(try BoxMerge.apply(p, resolutions: [1: .new], to: [saved], makeID: { "n" }).map { $0.id }, ["a", "n"])
        XCTAssertEqual(try BoxMerge.apply(p, resolutions: [1: .leaveOut], to: [saved]).map { $0.id }, ["a"])
        let same = try BoxMerge.apply(p, resolutions: [1: .existing("a")], to: [saved])
        XCTAssertEqual(same.count, 1); XCTAssertEqual(same[0].row.cp, 1982, "the part-read CP must not overwrite the real one"); XCTAssertEqual(same[0].lastSeen, date(5))
    }

    func testDifferentHPIsNew() {
        let p = plan([partial(hp: 140)], [entry(row(cp: 1982), "a")])
        XCTAssertEqual(p.new, [0]); XCTAssertTrue(p.unsure.isEmpty)
    }

    func testUnreadHPStillAsksAndNonSubsequenceIsNew() {
        let a = entry(row(cp: 1982), "a")
        XCTAssertEqual(plan([partial(hp: nil)], [a]).unsure.count, 1)
        XCTAssertEqual(plan([partial(cp: 281)], [a]).new, [0], "2 8 1 is not in 1 9 8 2 in that order")
        XCTAssertEqual(plan([row("pidgey", cp: 182, hp: 142, ivs: nil, flags: ["no-level-fits"])], [a]).new, [0], "other species")
    }

    func testTwoCandidatesAreBothListed() {
        let a = entry(row(cp: 1982), "a"), b = entry(row(cp: 1802, ivs: IVs(atk: 1, def: 2, hp: 3)), "b")
        let p = plan([partial()], [a, b])
        XCTAssertEqual(p.unsure, [BoxMerge.Unsure(scanned: 0, candidates: ["a", "b"], kind: .partialRead)])
    }

    func testOnlyAFlaggedOrIVlessRowIsAsked() {
        // a clean row with IVs that happens to look like a part read is just a new Pokémon
        let p = plan([row(cp: 182, ivs: IVs(atk: 1, def: 1, hp: 1))], [entry(row(cp: 1982), "a")])
        XCTAssertEqual(p.new, [0])
        // a row with IVs but the no-level-fits flag, with its HP read as the saved entry's, is resolved by the merge (W1); with the HP unread it is asked about
        let flagged = row(cp: 182, ivs: IVs(atk: 1, def: 1, hp: 1), flags: ["no-level-fits"])
        XCTAssertEqual(plan([flagged], [entry(row(cp: 1982), "a")]).partMatches.count, 1)
        var noHP = flagged; noHP.hp = nil
        XCTAssertEqual(plan([noHP], [entry(row(cp: 1982), "a")]).unsure.count, 1)
    }

    func testAFullScanDoesNotProposeTheCandidateAsGone() {
        let a = entry(row(cp: 1982), "a")
        let p = plan([partial()], [a], .full)
        XCTAssertTrue(p.gone.isEmpty)
        XCTAssertEqual(try! BoxMerge.apply(p, resolutions: [0: .leaveOut], keepGone: BoxMerge.keepSet(plan: p, resolutions: [0: .leaveOut], markedForRemoval: []), to: [a]).count, 1, "an untouched save removes nothing")
    }

    func testTwoAmbiguousOnesStillCannotPickTheSameSaved() {
        let a = entry(row(cp: 300, ivs: IVs(atk: 1, def: 1, hp: 1)), "a")
        let p = plan([row(cp: 500, ivs: IVs(atk: 1, def: 1, hp: 1)), row(cp: 600, ivs: IVs(atk: 1, def: 1, hp: 1))], [a])
        XCTAssertThrowsError(try BoxMerge.apply(p, resolutions: [0: .existing("a"), 1: .existing("a")], to: [a]))
        XCTAssertNoThrow(try BoxMerge.apply(p, resolutions: [0: .leaveOut, 1: .existing("a")], to: [a]))
    }

    // MARK: solving again after a correction

    func testCorrectedIVsGetTheirLevelAndDust() throws {
        let engine = CoreEngine()
        // a real Staraptor read: CP 1982, HP 142, IVs 13/12/15 (from the device log), so a level fits
        var r = row(cp: 1982, ivs: IVs(atk: 13, def: 12, hp: 15), flags: ["ambiguous-ivs:3-fit"])
        r.level = nil; r.levelMax = nil; r.dust = nil
        let e = BoxEntry(id: "a", row: r, firstSeen: date(0), lastSeen: date(0))
        let fixed = try BoxMerge.correct(e, with: BoxMerge.Edit(ivs: IVs(atk: 13, def: 12, hp: 14)), gameMaster: gm)
        // 13/12/14 may or may not fit this CP and HP: the answer must be one of the two defined outcomes, never a silent stale level
        let (out, notice) = LevelSolve.apply(to: fixed, engine: engine)
        if let level = out.row.level {
            XCTAssertNil(notice); XCTAssertNotNil(out.row.dust); XCTAssertGreaterThan(level, 0)
            XCTAssertFalse(out.row.flags.contains("no-level-fits"))
        } else {
            XCTAssertTrue(out.row.flags.contains("no-level-fits")); XCTAssertNotNil(notice); XCTAssertTrue(notice!.contains("No level fits"))
        }
        XCTAssertEqual(out.row.ivs, IVs(atk: 13, def: 12, hp: 14), "the person's values are kept either way")
    }

    func testAValuesThatFitGivesALevelAndOnesThatDoNotGiveTheFlag() throws {
        let engine = CoreEngine()
        let out = try ScanPipeline.process(replay: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PogoAssist/PogoAssist/Resources/sample-scan.replay.jsonl"), engine: engine)
        let real = try XCTUnwrap(out.scan.rows.first { $0.ivs != nil && $0.level != nil && $0.flags.isEmpty })
        var e = BoxEntry(id: "x", row: real, firstSeen: date(0), lastSeen: date(0))
        e.row.level = nil; e.row.levelMax = nil; e.row.dust = nil
        let (fit, note) = LevelSolve.apply(to: e, engine: engine)
        XCTAssertNil(note); XCTAssertEqual(fit.row.level, real.level); XCTAssertEqual(fit.row.dust, real.dust)
        // a CP that no level of this species can have
        var bad = e; bad.row.cp = 10
        let (none, why) = LevelSolve.apply(to: bad, engine: engine)
        XCTAssertNil(none.row.level); XCTAssertTrue(none.row.flags.contains("no-level-fits")); XCTAssertNotNil(why)
        XCTAssertEqual(none.row.cp, 10)
    }
}

final class RenameTests: XCTestCase {
    private var dir: URL!
    private var lib: BoxLibrary!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-rename-\(UUID().uuidString)")
        lib = BoxLibrary(root: dir)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func seed(_ name: String) throws -> (scan: String, seq: Int) {
        let entry = BoxEntry(id: "e1", row: ScanRow(index: 1, name: "Pidgey", display: "Pidgey", form: "", speciesId: "pidgey", dex: 16, cp: 100, hp: 30, ivs: nil, ivsRead: nil, ivsGuess: nil,
                                                    level: 5, levelMax: 5, dust: 200, solveStatus: "exact", flags: [], frames: []), firstSeen: Date(timeIntervalSince1970: 1_790_000_000), lastSeen: Date(timeIntervalSince1970: 1_790_000_000))
        let log = Data("{\"k\":\"t\",\"t\":1}\n".utf8)
        let scan = try lib.store.save(ScanResult(rows: [entry.row], review: [], unmatched: []), account: name, source: "broadcast", replayLog: log)
        let snap = try lib.commit(account: name, entries: [entry], reason: .scan, note: "x", scanId: scan.id)
        _ = try lib.commit(account: name, entries: [entry], reason: .edit, note: "y")
        try lib.saveAdvice(BoxAdvice(), account: name, seq: snap.seq)
        return (scan.id, snap.seq)
    }

    func testRenameMovesDataVersionsScansLogsAndAdvice() throws {
        let (scanId, seq) = try seed("Parents")
        try lib.renameAccount(from: "Parents", to: "  darentas ")
        XCTAssertEqual(try lib.accounts(), ["darentas"])
        XCTAssertEqual(try lib.current(account: "darentas")?.entries.count, 1)
        XCTAssertEqual(try lib.current(account: "darentas")?.account, "darentas")
        XCTAssertEqual(try lib.history(account: "darentas").count, 2)
        XCTAssertEqual(try lib.load(account: "darentas", seq: seq).account, "darentas")
        XCTAssertEqual(try lib.store.load(account: "darentas", id: scanId).account, "darentas")
        XCTAssertEqual(try lib.store.replayLog(account: "darentas", id: scanId), Data("{\"k\":\"t\",\"t\":1}\n".utf8))
        XCTAssertNotNil(lib.loadAdvice(account: "darentas", seq: seq))
        XCTAssertThrowsError(try lib.store.load(account: "Parents", id: scanId))
        // the box still takes a new version under the new name
        XCTAssertEqual(try lib.commit(account: "darentas", entries: [], reason: .edit, note: "z").seq, 3)
    }

    func testRenameRefusesEmptyAndExistingNamesInPlainWords() throws {
        _ = try seed("One"); _ = try seed("Two")
        XCTAssertThrowsError(try lib.renameAccount(from: "One", to: "   ")) { XCTAssertEqual($0 as? BoxStore.Failure, .badAccountName); XCTAssertEqual(($0 as? LocalizedError)?.errorDescription, "The account name is empty. Type a name.") }
        XCTAssertThrowsError(try lib.renameAccount(from: "One", to: "two")) { XCTAssertEqual($0 as? BoxStore.Failure, .accountExists("Two")) }
        XCTAssertThrowsError(try lib.renameAccount(from: "Nobody", to: "X")) { XCTAssertEqual($0 as? BoxStore.Failure, .noSuchAccount("Nobody")) }
        XCTAssertEqual(try lib.accounts(), ["One", "Two"], "a refused rename changes nothing")
        XCTAssertEqual(try lib.current(account: "One")?.entries.count, 1)
    }

    func testRenameByCapitalsAloneAndToTheSameName() throws {
        _ = try seed("darentas")
        try lib.renameAccount(from: "darentas", to: "Darentas")
        XCTAssertEqual(try lib.accounts(), ["Darentas"])
        XCTAssertEqual(try lib.current(account: "Darentas")?.entries.count, 1)
        XCTAssertNoThrow(try lib.renameAccount(from: "Darentas", to: "Darentas"))
    }

    func testAScansFilesCanBeFoundForSharing() throws {
        let (scanId, _) = try seed("A")
        let f = try lib.store.files(account: "A", id: scanId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.result.path)); XCTAssertNotNil(f.replay)
        XCTAssertThrowsError(try lib.store.files(account: "A", id: "nope"))
    }
}

final class PartialReadByBarsTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private func date(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(d) * 86_400) }
    private func fixture() throws -> (scanned: ScanRow, saved: ScanRow) {
        struct F: Decodable { var scanned: ScanRow; var saved: ScanRow }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "xerneas-part-read", withExtension: "json", subdirectory: "Fixtures"))
        let f = try JSONDecoder().decode(F.self, from: Data(contentsOf: url))
        return (f.scanned, f.saved)
    }
    private func plan(_ s: ScanRow, _ saved: [BoxEntry]) -> BoxMerge.Plan { BoxMerge.plan(scanned: [s], into: saved, kind: .partial, scanDate: date(5), gameMaster: gm) }

    /// The owner's second scan: "Xerneas CP 281, HP 170, no IVs, no-level-fits", ivsRead 12/10/10, for the saved CP 2611.
    func testTheRealPartReadIsUnsureNotNew() throws {
        let (scanned, savedRow) = try fixture()
        XCTAssertNil(scanned.ivs); XCTAssertEqual(scanned.ivsRead, IVs(atk: 12, def: 10, hp: 10)); XCTAssertEqual(scanned.cp, 281)
        let saved = BoxEntry(id: "x", row: savedRow, firstSeen: date(0), lastSeen: date(0))
        let p = plan(scanned, [saved])
        XCTAssertEqual(p.unsure, [BoxMerge.Unsure(scanned: 0, candidates: ["x"], kind: .partialRead)])
        XCTAssertTrue(p.new.isEmpty)
        // 2-8-1 is not a subsequence of 2-6-1-1: it is the bars that tie them
        XCTAssertFalse(String(2611).contains("281"))
    }

    func testDifferentBarsOrNoBarsAndNoSubsequenceIsNew() throws {
        let (scanned, savedRow) = try fixture()
        let saved = BoxEntry(id: "x", row: savedRow, firstSeen: date(0), lastSeen: date(0))
        var other = scanned; other.ivsRead = IVs(atk: 1, def: 2, hp: 3)
        XCTAssertEqual(plan(other, [saved]).new, [0], "different ivsRead")
        var none = scanned; none.ivsRead = nil
        XCTAssertEqual(plan(none, [saved]).new, [0], "ivsRead nil")
        var hp = scanned; hp.hp = scanned.hp! + 2
        XCTAssertEqual(plan(hp, [saved]).new, [0], "HP two off")
        // one point off is a misread, so it is asked, never New (U3 d)
        var near = scanned; near.hp = scanned.hp! + 1
        XCTAssertTrue(plan(near, [saved]).new.isEmpty); XCTAssertEqual(plan(near, [saved]).unsure.count, 1, "HP one off")
        var species = scanned; species.speciesId = "yveltal"; species.name = "Yveltal"
        XCTAssertEqual(plan(species, [saved]).new, [0], "different species")
        var fits = scanned; fits.flags = []; fits.ivs = scanned.ivsRead
        XCTAssertEqual(plan(fits, [saved]).new, [0], "the same IVs but no level gives this CP and HP for them: not the saved Pokémon (it is a new row, never silently dropped)")
        var fresh = fits; fresh.ivs = IVs(atk: 1, def: 2, hp: 3); fresh.ivsRead = fresh.ivs
        XCTAssertEqual(plan(fresh, [saved]).new, [0], "a clean row with other IVs is just a new Pokémon")
    }

    func testTheBarsCandidateAnswersLikeAnyPartRead() throws {
        let (scanned, savedRow) = try fixture()
        let saved = BoxEntry(id: "x", row: savedRow, firstSeen: date(0), lastSeen: date(0))
        let p = plan(scanned, [saved])
        let seen = try BoxMerge.apply(p, resolutions: [0: .existing("x")], to: [saved])
        XCTAssertEqual(seen[0].row.cp, 2611, "the part-read CP is not copied over the saved one"); XCTAssertEqual(seen[0].lastSeen, date(5))
        XCTAssertEqual(try BoxMerge.apply(p, resolutions: [0: .leaveOut], to: [saved]).count, 1)
    }
}
