import Foundation
import XCTest
@testable import PogoBox
import PogoReader

final class BoxLibraryTests: XCTestCase {
    private var dir: URL!
    private var lib: BoxLibrary!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-lib-\(UUID().uuidString)")
        lib = BoxLibrary(root: dir)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func date(_ n: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(n) * 3600) }
    private func entries(_ cps: [Int]) -> [BoxEntry] {
        cps.enumerated().map { i, cp in
            BoxEntry(id: "e\(i)", row: ScanRow(index: i, name: "Pidgey", display: "Pidgey", form: "", speciesId: "pidgey", dex: 16, cp: cp, hp: 40, ivs: IVs(atk: 1, def: 2, hp: 3), ivsRead: nil,
                                              ivsGuess: nil, level: 5, levelMax: 5, dust: 200, solveStatus: "exact", flags: [], frames: []), firstSeen: date(0), lastSeen: date(0))
        }
    }

    func testAccountsAreMadeAndVersionsAccumulate() throws {
        XCTAssertEqual(try lib.accounts(), [])
        try lib.createAccount("Greg main")
        XCTAssertEqual(try lib.accounts(), ["Greg main"])
        XCTAssertNil(try lib.current(account: "Greg main"))
        let v1 = try lib.commit(account: "Greg main", entries: entries([100]), reason: .scan, note: "one", now: date(1))
        let v2 = try lib.commit(account: "Greg main", entries: entries([100, 200]), reason: .scan, note: "two", now: date(2))
        XCTAssertEqual([v1.seq, v2.seq], [1, 2])
        XCTAssertEqual(try lib.current(account: "Greg main")?.entries.count, 2)
        XCTAssertEqual(try lib.history(account: "Greg main").map { $0.seq }, [2, 1])
        XCTAssertEqual(try lib.load(account: "Greg main", seq: 1).entries.count, 1, "an earlier version is untouched")
    }

    private func scanFiles(_ account: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent(account).path).filter { $0.hasPrefix("scan-") }
    }

    func testAScanWhoseVersionCannotBeWrittenLeavesNoScanRecordAndARetryMakesOne() throws {
        let es = entries([100, 200])
        let result = ScanResult(rows: es.map { $0.row }, review: [], unmatched: [])
        let log = Data("{\"k\":\"t\",\"t\":1}\n".utf8)
        _ = try lib.commit(account: "a", entries: entries([100]), reason: .scan, note: "one", now: date(1))
        struct Boom: Error {}
        // the version write fails after the scan record is down (the hook), then for real (a box folder that takes no new file)
        XCTAssertThrowsError(try lib.commitScan(result, entries: es, account: "a", scanDate: date(2), source: "broadcast", kind: .full, note: "two", expectedCurrentSeq: .some(1), replayLog: log, commitFailure: { throw Boom() }))
        XCTAssertEqual(try scanFiles("a"), [], "the record and its log were taken back out")
        let box = dir.appendingPathComponent("a/box")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: box.path)
        XCTAssertThrowsError(try lib.commitScan(result, entries: es, account: "a", scanDate: date(2), source: "broadcast", kind: .full, note: "two", expectedCurrentSeq: .some(1), replayLog: log))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: box.path)
        XCTAssertEqual(try scanFiles("a"), [])
        XCTAssertEqual(try lib.current(account: "a")?.seq, 1, "the box did not move")
        // the retry makes one scan and one version
        let done = try lib.commitScan(result, entries: es, account: "a", scanDate: date(2), source: "broadcast", kind: .full, note: "two", expectedCurrentSeq: .some(1), replayLog: log)
        XCTAssertEqual(done.snapshot.seq, 2); XCTAssertEqual(done.snapshot.scanId, done.scan.id)
        XCTAssertEqual(try scanFiles("a").sorted(), ["\(done.scan.id).json", "\(done.scan.id).replay.jsonl"])
    }

    func testAScanSavedOverAChangedBoxIsRefusedBeforeAnythingIsWritten() throws {
        _ = try lib.commit(account: "a", entries: entries([100]), reason: .scan, note: "one", now: date(1))
        let result = ScanResult(rows: entries([100]).map { $0.row }, review: [], unmatched: [])
        XCTAssertThrowsError(try lib.commitScan(result, entries: [], account: "a", scanDate: date(2), source: "broadcast", kind: .full, note: "x", expectedCurrentSeq: .some(0), replayLog: Data("x".utf8))) {
            XCTAssertEqual($0 as? BoxLibrary.Failure, .boxChanged)
        }
        XCTAssertEqual(try scanFiles("a"), [])
    }

    func testAScanIsNeverSavedIntoAnAccountFolderThatDoesNotExist() throws {
        let result = ScanResult(rows: entries([100]).map { $0.row }, review: [], unmatched: [])
        XCTAssertThrowsError(try lib.commitScan(result, entries: [], account: "Ghost", scanDate: date(1), source: "broadcast", kind: .full, note: "x", expectedCurrentSeq: .some(nil))) {
            XCTAssertEqual($0 as? BoxStore.Failure, .noSuchAccount("Ghost"))
        }
        XCTAssertEqual(try lib.accounts(), [], "no folder was made")
        // an account that was made, and has no version yet, takes its first scan
        try lib.createAccount("New")
        XCTAssertEqual(try lib.commitScan(result, entries: [], account: "New", scanDate: date(1), source: "broadcast", kind: .full, note: "x", expectedCurrentSeq: .some(nil), sourceSignature: "12-345").snapshot.seq, 1)
        XCTAssertEqual(try lib.store.list(account: "New").scans.first?.sourceSignature, "12-345")
    }

    func testAScanIsNotSavedOnTopOfANewestVersionThatCannotBeRead() throws {
        _ = try lib.commit(account: "a", entries: entries([100]), reason: .scan, note: "one", now: date(1))
        _ = try lib.commit(account: "a", entries: entries([100, 200]), reason: .scan, note: "two", now: date(2))
        try Data("{ broken".utf8).write(to: dir.appendingPathComponent("a/box/000002.json"))
        let result = ScanResult(rows: entries([100]).map { $0.row }, review: [], unmatched: [])
        XCTAssertThrowsError(try lib.commitScan(result, entries: [], account: "a", scanDate: date(3), source: "broadcast", kind: .full, note: "x", expectedCurrentSeq: .some(2), replayLog: Data("x".utf8)))
        XCTAssertEqual(try scanFiles("a"), [], "nothing was written")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("a/box").path).sorted(), ["000001.json", "000002.json"])
    }

    func testThePreviousVersionCanBeTakenFromAHistoryAlreadyRead() throws {
        for i in 1...3 { _ = try lib.commit(account: "a", entries: entries([i]), reason: .scan, note: "v\(i)", now: date(i)) }
        let h = try lib.history(account: "a")
        XCTAssertEqual(BoxLibrary.previous(in: h)?.seq, 2)
        XCTAssertEqual(BoxLibrary.previous(in: h), try lib.previousVersion(account: "a"))
        XCTAssertNil(BoxLibrary.previous(in: []))
    }

    func testRestorePreviousBringsBackTheEarlierBoxAsANewVersion() throws {
        _ = try lib.commit(account: "a", entries: entries([100]), reason: .scan, note: "one", now: date(1))
        _ = try lib.commit(account: "a", entries: entries([100, 200, 300]), reason: .scan, note: "two", now: date(2))
        XCTAssertEqual(try lib.previousVersion(account: "a")?.seq, 1)
        let r = try lib.restorePrevious(account: "a", now: date(3))
        XCTAssertEqual(r.seq, 3); XCTAssertEqual(r.reason, .restore); XCTAssertEqual(r.restoredFrom, 1)
        XCTAssertEqual(try lib.current(account: "a")?.entries.count, 1)
        XCTAssertEqual(try lib.load(account: "a", seq: 2).entries.count, 3, "the box that was undone is still there")
        // pressing it again goes back to what the restore replaced (the content of version 2)
        XCTAssertEqual(try lib.previousVersion(account: "a")?.seq, 2)
        XCTAssertEqual(try lib.restorePrevious(account: "a", now: date(3)).entries.count, 3)
        try lib.commit(account: "solo", entries: entries([1]), reason: .scan, note: "only", now: date(1))
        XCTAssertThrowsError(try lib.restorePrevious(account: "solo")) { XCTAssertEqual($0 as? BoxLibrary.Failure, .nothingToRestore) }
        // any version can be restored by number, which is how the undone one comes back
        XCTAssertEqual(try lib.restore(account: "a", seq: 2, now: date(4)).entries.count, 3)
        XCTAssertThrowsError(try lib.restore(account: "a", seq: 99)) { XCTAssertEqual($0 as? BoxLibrary.Failure, .noSuchVersion(99)) }
    }

    func testRestoreAfterAScanThatRemovedPokemon() throws {
        let gm = try GameMaster.bundled()
        let first = BoxMerge.plan(scanned: entries([100, 200]).map { $0.row }, into: [], kind: .full, scanDate: date(1), gameMaster: gm)
        let box1 = try BoxMerge.apply(first, to: [])
        try lib.commit(account: "a", entries: box1, reason: .scan, note: "first", now: date(1))
        // a full scan that sees only one of them proposes the other as gone; saving removes it ...
        let second = BoxMerge.plan(scanned: [box1[0].row], into: box1, kind: .full, scanDate: date(2), gameMaster: gm)
        XCTAssertEqual(second.gone, [box1[1].id])
        try lib.commit(account: "a", entries: try BoxMerge.apply(second, to: box1), reason: .scan, note: "second", now: date(2))
        XCTAssertEqual(try lib.current(account: "a")?.entries.count, 1)
        // ... and restoring brings it back with its id and dates
        let back = try lib.restorePrevious(account: "a", now: date(3))
        XCTAssertEqual(back.entries.map { $0.id }, box1.map { $0.id })
        XCTAssertEqual(back.entries[1].firstSeen, date(1))
    }

    func testAdviceIsCachedPerVersion() throws {
        try lib.commit(account: "a", entries: entries([100]), reason: .scan, note: "one", now: date(1))
        XCTAssertNil(lib.loadAdvice(account: "a", seq: 1))
        let advice = BoxAdvice(builds: [], gaps: [BoxAdvice.Gap(area: "Raids", section: nil, tier: "S", name: "X", obtain: nil, haveBase: false)], duplicates: [], unresolved: [])
        try lib.saveAdvice(advice, account: "a", seq: 1)
        XCTAssertEqual(lib.loadAdvice(account: "a", seq: 1), advice)
        XCTAssertNil(lib.loadAdvice(account: "a", seq: 2))
        XCTAssertEqual(try lib.history(account: "a").count, 1, "the advice file is not a version")
    }

    func testAdviceFromBeforeLeaguesIsDroppedAndLeaguesDecode() throws {
        try lib.commit(account: "a", entries: entries([100]), reason: .scan, note: "one", now: date(1))
        let box = try XCTUnwrap(lib.current(account: "a")).entries
        let json = """
        {"pokemon":[{"p":{"index":1},"hits":[],"leagues":{
          "gl":{"pick":{"speciesId":"toxapex","name":"Toxapex","self":false},"strength":{"score":91.8,"rank":23,"of":1152},
                "moves":{"fast":"Poison Jab","charged":["Brine","Sludge Wave"]},"needs":null,
                "iv":{"rank":5,"pct":99.1,"rankPct":97.2,"level":24.5,"cp":1497},"overCap":false,
                "cost":{"dust":175000,"candy":120,"xl":0,"evolveCandy":50,"toLevel":24.5}},
          "ul":{"pick":{"speciesId":"mareanie","name":"Mareanie","self":true},"strength":null,"moves":null,"needs":["Brine","Poison Jab"],
                "iv":null,"overCap":true,"cost":null}}}]}
        """
        let advice = BoxAdvice.make(from: try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)), entries: box)
        let l = advice.leagues(for: box[0].id)
        XCTAssertEqual(l["gl"]?.pick.name, "Toxapex")
        XCTAssertEqual(l["gl"]?.pick.isSelf, false)
        XCTAssertEqual(l["gl"]?.strength, .init(score: 91.8, rank: 23, of: 1152))
        XCTAssertEqual(l["gl"]?.moves, .init(fast: "Poison Jab", charged: ["Brine", "Sludge Wave"]))
        XCTAssertNil(l["gl"]?.needs)
        XCTAssertEqual(l["gl"]?.cost, .init(dust: 175000, candy: 120, xl: 0, evolveCandy: 50, toLevel: 24.5))
        XCTAssertEqual(l["ul"]?.needs, ["Brine", "Poison Jab"])
        XCTAssertEqual(l["ul"]?.overCap, true)
        XCTAssertNil(l["ul"]?.strength); XCTAssertNil(l["ul"]?.iv); XCTAssertNil(l["ul"]?.cost)
        XCTAssertNil(l["ml"])
        XCTAssertEqual(advice.leagues(for: "nobody"), [:])
        XCTAssertEqual(advice.version, 2)

        // The cache round-trips it; a file with no version (build 2) or a lower one is read as missing.
        try lib.saveAdvice(advice, account: "a", seq: 1)
        XCTAssertEqual(lib.loadAdvice(account: "a", seq: 1), advice)
        var old = advice; old.version = 1
        try lib.saveAdvice(old, account: "a", seq: 1)
        XCTAssertNil(lib.loadAdvice(account: "a", seq: 1))
        let legacy = #"{"builds":[],"gaps":[],"duplicates":[],"unresolved":[],"spareBuilds":{}}"#
        let file = try XCTUnwrap(FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }.first { $0.lastPathComponent.hasSuffix(".advice.json") })
        try Data(legacy.utf8).write(to: file)
        XCTAssertNil(lib.loadAdvice(account: "a", seq: 1))
    }

    func testLeagueSentences() {
        typealias R = BoxAdvice.LeagueRating
        let full = R(pick: .init(speciesId: "toxapex", name: "Toxapex", isSelf: false), strength: .init(score: 91.84, rank: 23, of: 1152),
                     moves: .init(fast: "Poison Jab", charged: ["Brine", "Sludge Wave"]), needs: ["Brine", "Poison Jab"],
                     iv: .init(rank: 1234, pct: 97.26, rankPct: 70, level: 24.5, cp: 1497), overCap: false,
                     cost: .init(dust: 175000, candy: 1200, xl: 8, evolveCandy: 50, toLevel: 24.5))
        XCTAssertEqual(LeagueText.pick(full), "As Toxapex")
        var locked = full; locked.pick = .init(speciesId: "gallade", name: "Gallade", isSelf: false, genderLocked: "male")
        XCTAssertEqual(LeagueText.pick(locked), "As Gallade, if it is male")
        XCTAssertEqual(LeagueText.strength(full, key: "gl"), "PvPoke ranks Toxapex 23rd of 1,152 in Great League, score 91.8")
        XCTAssertEqual(LeagueText.ivs(full, key: "gl"), "IVs rank #1,234 of 4,096 · 97.3% of best")
        XCTAssertEqual(LeagueText.moves(full), "Moves: Poison Jab, Brine, Sludge Wave")
        XCTAssertEqual(LeagueText.needs(full), "Needs Brine and Poison Jab")
        var one = full; one.needs = ["Brine"]
        XCTAssertEqual(LeagueText.needs(one), "Needs Brine")
        one.needs = []; XCTAssertNil(LeagueText.needs(one))
        one.needs = nil; XCTAssertNil(LeagueText.needs(one))
        XCTAssertEqual(LeagueText.cost(full, levelKnown: true), "To level 24.5: 175,000 dust, 1,200 candy, 8 XL candy (50 to evolve)")
        var plain = full; plain.cost = .init(dust: 9000, candy: 40, xl: 0, evolveCandy: 0, toLevel: 40)
        XCTAssertEqual(LeagueText.cost(plain, levelKnown: true), "To level 40: 9,000 dust, 40 candy")
        plain.cost = .init(dust: 0, candy: 0, xl: 0, evolveCandy: 0, toLevel: 24.5)
        XCTAssertEqual(LeagueText.cost(plain, levelKnown: true), "Already at level 24.5")
        plain.cost = nil
        XCTAssertEqual(LeagueText.cost(plain, levelKnown: false), "Level not known, so no cost")
        XCTAssertNil(LeagueText.cost(plain, levelKnown: true))
        var self1 = full; self1.pick.isSelf = true; self1.strength = nil; self1.moves = nil; self1.iv = nil
        XCTAssertNil(LeagueText.pick(self1)); XCTAssertNil(LeagueText.moves(self1))
        XCTAssertEqual(LeagueText.strength(self1, key: "ul"), "Not ranked in Ultra League by PvPoke")
        XCTAssertEqual(LeagueText.ivs(self1, key: "ul"), "IVs not read, so no rank")
        var over = full; over.overCap = true
        XCTAssertEqual(LeagueText.ivs(over, key: "ul"), "Already above 2,500 CP, so it cannot be used in Ultra League")
        XCTAssertEqual(LeagueText.ivs(over, key: "gl"), "Already above 1,500 CP, so it cannot be used in Great League")
        XCTAssertEqual([1, 2, 3, 4, 11, 12, 13, 21, 22, 101, 111, 1002].map(LeagueText.ordinal), ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "101st", "111th", "1,002nd"])
    }

    func testReplayLogIsKeptBesideTheScanAndAScanFileWithoutOneStillLoads() throws {
        let store = lib.store
        let result = ScanResult(rows: [], review: [], unmatched: [])
        let log = Data("{\"k\":\"t\",\"t\":1}\n".utf8)
        let s = try store.save(result, account: "a", source: "broadcast", kind: .partial, storageCount: 120, replayLog: log)
        XCTAssertEqual(try store.replayLog(account: "a", id: s.id), log)
        XCTAssertEqual(try store.load(account: "a", id: s.id).storageCount, 120)
        XCTAssertEqual(try store.list(account: "a").scans.count, 1, "the log is not listed as a scan")
        let bare = try store.save(result, account: "a", source: "x")
        XCTAssertNil(try store.replayLog(account: "a", id: bare.id))
        try store.delete(account: "a", id: s.id)
        XCTAssertNil(try store.replayLog(account: "a", id: s.id))
    }
}
