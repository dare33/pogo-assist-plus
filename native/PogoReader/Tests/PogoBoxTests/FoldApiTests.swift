import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// Review findings folded in that need new interfaces (M2, M8, M9, M10, L2, L3, V1, V2, V4): written first, they did not compile.
final class FoldApiTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private func date(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(d) * 86_400) }
    private let x = IVs(atk: 15, def: 15, hp: 15)

    private func row(_ id: String = "staraptor", cp: Int, hp: Int? = 142, ivs: IVs? = IVs(atk: 13, def: 12, hp: 15), flags: [String] = []) -> ScanRow {
        let nf = GameMaster.nameAndForm(gm.byId[id]?.name ?? id)
        return ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: id, dex: gm.byId[id]?.dex, cp: cp, hp: hp, ivs: ivs, ivsRead: ivs, ivsGuess: nil,
                       level: 20, levelMax: 20, dust: 1000, solveStatus: ivs == nil ? "unknown-ivs" : "exact", flags: flags, frames: [])
    }
    private func entry(_ r: ScanRow, _ id: String) -> BoxEntry { BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0)) }
    private func plan(_ s: [ScanRow], unmatched: [Unmatched] = [], _ v: [BoxEntry], _ k: BoxStore.Kind = .full) -> BoxMerge.Plan {
        BoxMerge.plan(scanned: s, unmatched: unmatched, into: v, kind: k, scanDate: date(5), gameMaster: gm)
    }
    private func item(name: String?, reason: String = "cp-not-read") -> Unmatched {
        Unmatched(frame: "f1", cp: nil, name: name, nameText: name, hp: nil, ivs: nil, cpOptions: nil, frames: 3, reason: reason, into: nil, clip: nil)
    }

    // M2
    func testM2AnUnreadPokemonProtectsSameSpeciesEntriesFromGone() throws {
        let staraptor = entry(row(cp: 1982), "s"), pidgey = entry(row("pidgey", cp: 100, hp: 40), "p")
        let p = plan([], unmatched: [item(name: "Staraptor")], [staraptor, pidgey])
        XCTAssertEqual(p.gone, ["p"], "only the other species is proposed as gone")
        XCTAssertEqual(p.kept.map { $0.savedId }, ["s"]); XCTAssertTrue(p.kept[0].reason.contains("Staraptor"))
        // an unread item with no name protects every entry
        let anon = plan([], unmatched: [item(name: nil, reason: "name-not-read")], [staraptor, pidgey])
        XCTAssertTrue(anon.gone.isEmpty); XCTAssertEqual(Set(anon.kept.map { $0.savedId }), ["s", "p"])
        // a fragment folded into its neighbour was seen, so it protects nothing
        XCTAssertEqual(plan([], unmatched: [item(name: nil, reason: "absorbed")], [staraptor, pidgey]).gone.sorted(), ["p", "s"])
        // add-and-update never proposes gone at all
        XCTAssertTrue(plan([], unmatched: [item(name: "Staraptor")], [staraptor], .partial).gone.isEmpty)
        // kept entries survive Save
        XCTAssertEqual(try BoxMerge.apply(p, to: [staraptor, pidgey]).map { $0.id }, ["s"])
    }

    func testM2GoneIsPerEntryWithKeepAll() throws {
        let a = entry(row("pidgey", cp: 100, hp: 40), "a"), b = entry(row("rattata", cp: 90, hp: 30), "b"), c = entry(row("zubat", cp: 80, hp: 30), "c")
        let p = plan([row("pidgey", cp: 100, hp: 40)], [a, b, c])
        XCTAssertEqual(Set(p.gone), ["b", "c"])
        XCTAssertEqual(try BoxMerge.apply(p, keepGone: ["b"], to: [a, b, c]).map { $0.id }, ["a", "b"])
        XCTAssertEqual(try BoxMerge.apply(p, keepGone: Set(p.gone), to: [a, b, c]).map { $0.id }, ["a", "b", "c"], "keep all")
        XCTAssertEqual(try BoxMerge.apply(p, to: [a, b, c]).map { $0.id }, ["a"], "default is remove")
    }

    // M9
    func testM9AnsweringNewMakesTheCandidatesEligibleForGoneAgain() throws {
        let saved = entry(row(cp: 1982), "s")
        var partial = row(cp: 182, ivs: nil, flags: ["no-level-fits"]); partial.ivsRead = nil
        let p = plan([partial], [saved])
        XCTAssertEqual(p.unsure.first?.kind, .partialRead)
        XCTAssertTrue(p.gone.isEmpty)
        func report(_ r: BoxMerge.Resolution?) -> BoxMerge.GoneReport { BoxMerge.goneReport(p, resolutions: r.map { [0: $0] } ?? [:]) }
        XCTAssertTrue(report(nil).gone.isEmpty && report(nil).kept.isEmpty, "pending: neither")
        XCTAssertEqual(report(.new).gone, ["s"], "the row is new, so the saved one was not seen")
        XCTAssertTrue(report(.existing("s")).gone.isEmpty)
        let left = report(.leaveOut)
        XCTAssertTrue(left.gone.isEmpty); XCTAssertEqual(left.kept.map { $0.savedId }, ["s"], "a left-out row was on screen: the entry is kept, with the reason")
        // Save follows the report
        XCTAssertEqual(try BoxMerge.apply(p, resolutions: [0: .new], to: [saved], makeID: { "n" }).map { $0.id }, ["n"])
        XCTAssertEqual(try BoxMerge.apply(p, resolutions: [0: .new], keepGone: ["s"], to: [saved], makeID: { "n" }).map { $0.id }, ["s", "n"])
    }

    // M8
    func testM8AnExtraIdenticalTwinFlaggedByTheBeatIsAskedAbout() throws {
        let saved = entry(row(cp: 1982), "s")
        let first = row(cp: 1982), second = row(cp: 1982, flags: ["same-as-previous", "split-by-timing"])
        let p = plan([first, second], [saved])
        XCTAssertEqual(p.same.count, 1)
        XCTAssertEqual(p.unsure, [BoxMerge.Unsure(scanned: 1, candidates: ["s"], kind: .extraTwin)])
        XCTAssertTrue(p.new.isEmpty)
        XCTAssertEqual(try BoxMerge.apply(p, resolutions: [1: .new], to: [saved], makeID: { "t" }).map { $0.id }, ["s", "t"], "add a second")
        XCTAssertEqual(try BoxMerge.apply(p, resolutions: [1: .leaveOut], to: [saved]).map { $0.id }, ["s"])
        // without the beat flags the surplus identical row is New as before
        XCTAssertEqual(plan([first, row(cp: 1982)], [saved]).new.count, 1)
        // split-by-bars is two DIFFERENT Pokémon: it is not a twin
        XCTAssertTrue(plan([first, row(cp: 1982, flags: ["split-by-bars"])], [saved]).unsure.isEmpty)
    }

    // M10
    func testM10AKeptCorrectedIVsGetTheirLevelAndDustAgainAfterAPowerUp() throws {
        let engine = CoreEngine()
        let out = try ScanPipeline.process(replay: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PogoAssist/PogoAssist/Resources/sample-scan.replay.jsonl"), engine: engine)
        let real = try XCTUnwrap(out.scan.rows.first { $0.ivs != nil && $0.level != nil && $0.flags.isEmpty && $0.cp > 100 })
        let wrong = IVs(atk: (real.ivs!.atk + 1) % 16, def: real.ivs!.def, hp: real.ivs!.hp)
        // saved: the right IVs by hand (the scan had read `wrong`), an older lower CP and a stale level and dust
        var savedRow = real; savedRow.cp = real.cp - 20; savedRow.level = 1; savedRow.levelMax = 1; savedRow.dust = 1
        let saved = BoxEntry(id: "s", row: savedRow, firstSeen: date(0), lastSeen: date(0), corrections: Corrections(ivs: Fix(was: wrong)))
        var scanned = real; scanned.ivs = wrong; scanned.ivsRead = wrong
        let p = BoxMerge.plan(scanned: [scanned], into: [saved], kind: .partial, scanDate: date(5), gameMaster: gm)
        XCTAssertEqual(p.updated.first?.reason, .poweredUp)
        let box = try BoxMerge.apply(p, to: [saved], engine: engine)
        XCTAssertEqual(box[0].row.ivs, real.ivs, "the correction is kept"); XCTAssertEqual(box[0].row.cp, real.cp)
        XCTAssertEqual(box[0].row.level, real.level, "level follows the corrected IVs and the new CP"); XCTAssertEqual(box[0].row.dust, real.dust)
        // nothing fits: the old values stay and the row is flagged
        var bad = scanned; bad.cp = 10
        let pb = BoxMerge.plan(scanned: [bad], into: [BoxEntry(id: "s", row: { var r = savedRow; r.cp = 5; return r }(), firstSeen: date(0), lastSeen: date(0), corrections: Corrections(ivs: Fix(was: wrong)))], kind: .partial, scanDate: date(5), gameMaster: gm)
        let boxBad = try BoxMerge.apply(pb, to: [BoxEntry(id: "s", row: { var r = savedRow; r.cp = 5; return r }(), firstSeen: date(0), lastSeen: date(0), corrections: Corrections(ivs: Fix(was: wrong)))], engine: engine)
        XCTAssertTrue(boxBad[0].row.flags.contains("no-level-fits"))
    }

    // L2
    func testL2TwoMutationsEachReadTheCurrentBoxSoNeitherIsLost() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-l2-\(UUID().uuidString)"); defer { try? FileManager.default.removeItem(at: dir) }
        let lib = BoxLibrary(root: dir)
        try lib.commit(account: "a", entries: [entry(row(cp: 100), "one")], reason: .scan, note: "scan", now: date(1))
        let stale = try XCTUnwrap(lib.current(account: "a"))
        // two actions that were both started from the same snapshot of the box
        try lib.mutate(account: "a", reason: .edit, note: "A") { $0 + [self.entry(self.row("pidgey", cp: 50), "two")] }
        try lib.mutate(account: "a", reason: .edit, note: "B") { $0.filter { $0.id != "one" } }
        XCTAssertEqual(try lib.current(account: "a")?.entries.map { $0.id }, ["two"], "B saw A's result")
        XCTAssertEqual(try lib.history(account: "a").count, 3)
        // a save prepared against the old box is refused
        XCTAssertThrowsError(try lib.commit(account: "a", entries: stale.entries, reason: .scan, note: "late", expectedCurrentSeq: stale.seq)) { XCTAssertEqual($0 as? BoxLibrary.Failure, .boxChanged) }
        XCTAssertNoThrow(try lib.commit(account: "a", entries: [], reason: .scan, note: "fresh", expectedCurrentSeq: 3))
        // a mutation whose transform throws writes nothing
        struct Boom: Error {}
        XCTAssertThrowsError(try lib.mutate(account: "a", reason: .edit, note: "x") { _ in throw Boom() })
        XCTAssertEqual(try lib.history(account: "a").count, 4)
    }

    // L3
    func testL3AnUnreadableNewestVersionIsNotAnEmptyBox() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-l3-\(UUID().uuidString)"); defer { try? FileManager.default.removeItem(at: dir) }
        let lib = BoxLibrary(root: dir)
        try lib.commit(account: "a", entries: [entry(row(cp: 100), "one")], reason: .scan, note: "good", now: date(1))
        let v2 = try lib.commit(account: "a", entries: [], reason: .scan, note: "will be damaged", now: date(2))
        let file = dir.appendingPathComponent("a").appendingPathComponent("box").appendingPathComponent(String(format: "%06d.json", v2.seq))
        try Data("not json".utf8).write(to: file)
        XCTAssertThrowsError(try lib.current(account: "a"))
        XCTAssertEqual(try lib.latestReadable(account: "a")?.seq, 1)
        let restored = try lib.restoreLatestReadable(account: "a")
        XCTAssertEqual(restored.seq, 3); XCTAssertEqual(restored.entries.map { $0.id }, ["one"]); XCTAssertEqual(restored.restoredFrom, 1)
        XCTAssertEqual(try lib.current(account: "a")?.entries.count, 1)
        XCTAssertThrowsError(try BoxLibrary(root: dir.appendingPathComponent("none")).restoreLatestReadable(account: "z"))
    }

    // V1, V2
    func testV2TapNeedsAnExactCheckedPointForTheGivenWidthAndHeight() throws {
        func make(_ p: CGPoint?, _ w: Double?, _ h: Double?) throws -> Data { try VoiceCommandFile.make(count: 3, pace: .tapNormal, batch: 3, tap: p, screenWidth: w, screenHeight: h, now: date(1)) }
        XCTAssertNoThrow(try make(CGPoint(x: 424, y: 775), 440, 956))
        for (p, w, h) in [(CGPoint(x: 418, y: 775), 440.0, 956.0), (CGPoint(x: 424, y: 775), 440, 957), (CGPoint(x: 424, y: 775), 744, 1133), (CGPoint(x: 424, y: 774.9), 440, 956),
                          (CGPoint(x: Double.nan, y: 775), 440, 956), (CGPoint(x: 0, y: 0), 0, 0), (CGPoint(x: -1, y: 775), 440, 956), (CGPoint(x: 424, y: 775), 440, 0)] {
            XCTAssertThrowsError(try make(p, w, h), "\(p) on \(w)x\(h)") { XCTAssertEqual($0 as? VoiceCommandFile.Failure, .tapNotChecked) }
        }
        XCTAssertThrowsError(try make(nil, 440, 956)) { XCTAssertEqual($0 as? VoiceCommandFile.Failure, .needsTapPoint) }
        XCTAssertThrowsError(try make(CGPoint(x: 424, y: 775), nil, nil)) { XCTAssertEqual($0 as? VoiceCommandFile.Failure, .tapNotChecked) }
        // swipe files need no screen
        XCTAssertNoThrow(try VoiceCommandFile.make(count: 3, pace: .swipeFast, batch: 3, now: date(1)))
    }

    func testV1TheFileNameCarriesTheScreenItWasMadeFor() {
        XCTAssertEqual(VoiceCommandFile.Pace.tapNormal.fileName(count: 300, screen: "440x956 iPhone"), "Pogo scan 300 (440x956 iPhone).voicecontrolcommands")
        XCTAssertEqual(VoiceCommandFile.Pace.tapFast.fileName(count: 300, screen: "440x956 iPhone"), "Pogo fast scan 300 (440x956 iPhone).voicecontrolcommands")
        XCTAssertEqual(VoiceCommandFile.Pace.swipeFast.fileName(count: 300, screen: "402x874 iPhone"), "Pogo swipe 300.voicecontrolcommands")
        XCTAssertEqual(VoiceCommandFile.screenLabel(width: 440, height: 956, isPad: false), "440x956 iPhone")
        XCTAssertEqual(VoiceCommandFile.screenLabel(width: 744, height: 1133, isPad: true), "744x1133 iPad")
    }

    // V4
    func testV4StorageCountBoundsAndNoTrap() {
        XCTAssertEqual(StorageCount.parse("300"), .valid(300)); XCTAssertEqual(StorageCount.parse(" 10000 "), .valid(10_000)); XCTAssertEqual(StorageCount.parse("1"), .valid(1))
        XCTAssertEqual(StorageCount.parse(""), .empty)
        for bad in ["0", "10001", "99999999999999999", "99999999999999999999999999", "-5", "12a", "1,400"] { XCTAssertEqual(StorageCount.parse(bad), .invalid, bad) }
        XCTAssertFalse(StorageCount.problem(for: "99999999999999999")!.isEmpty)
        XCTAssertNil(StorageCount.problem(for: "300")); XCTAssertNil(StorageCount.problem(for: ""))
        // the sizing never traps, whatever it is given
        XCTAssertEqual(VoiceCommandFile.steps(storageCount: Int.max), VoiceCommandFile.steps(storageCount: 10_000))
        XCTAssertEqual(VoiceCommandFile.steps(storageCount: Int.min), 3)
        XCTAssertGreaterThan(VoiceCommandFile.sizing(storageCount: Int.max, pace: .tapNormal).repeats, 0)
        XCTAssertTrue(StorageCount.needsConfirmation(3_001)); XCTAssertFalse(StorageCount.needsConfirmation(3_000))
    }
}
