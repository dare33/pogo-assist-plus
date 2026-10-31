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

    func testAScanSavedTwiceIsRecognisedAndAnOrphanOnlyRemovedWhenEverythingWasReadable() throws {
        let es = entries([100])
        let result = ScanResult(rows: es.map { $0.row }, review: [], unmatched: [])
        _ = try lib.commit(account: "a", entries: [], reason: .scan, note: "one", now: date(1))
        let done = try lib.commitScan(result, entries: es, account: "a", scanDate: date(2), source: "broadcast", kind: .full, note: "two", expectedCurrentSeq: .some(1), sourceSignature: "9-1")
        XCTAssertEqual(lib.scanAlreadySaved(account: "a", signature: "9-1"), .saved)
        XCTAssertEqual(lib.scanAlreadySaved(account: "a", signature: "other"), .notSaved)
        // a record with no version pointing at it (cut off between the writes), everything readable: taken back
        let orphan = try lib.store.save(result, account: "a", scanDate: date(3), source: "broadcast", sourceSignature: "7-2")
        XCTAssertEqual(lib.scanAlreadySaved(account: "a", signature: "7-2"), .notSaved)
        XCTAssertThrowsError(try lib.store.load(account: "a", id: orphan.id))
        // the same, but a version file cannot be read: it may be the one that points at the record, so nothing is deleted
        let orphan2 = try lib.store.save(result, account: "a", scanDate: date(4), source: "broadcast", sourceSignature: "6-3")
        try Data("{ broken".utf8).write(to: dir.appendingPathComponent("a/box/000001.json"))
        XCTAssertEqual(lib.scanAlreadySaved(account: "a", signature: "6-3"), .unknown)
        XCTAssertNoThrow(try lib.store.load(account: "a", id: orphan2.id), "not deleted")
        // a version that points at the record is found even though another version is damaged
        XCTAssertEqual(lib.scanAlreadySaved(account: "a", signature: "9-1"), .saved)
        XCTAssertEqual(done.snapshot.scanId, done.scan.id)
        // a listing that cannot be made, or a scan file that cannot be read, is not an answer either
        try Data("not json".utf8).write(to: dir.appendingPathComponent("a/scan-junk.json"))
        XCTAssertEqual(lib.scanAlreadySaved(account: "a", signature: "nothing-here"), .unknown, "a damaged scan file with no log to tell by could be it")
        // one whose log is not the length the signature says is another scan's
        try Data("12345".utf8).write(to: dir.appendingPathComponent("a/scan-junk.replay.jsonl"))
        XCTAssertEqual(lib.scanAlreadySaved(account: "a", signature: "99-1"), .notSaved)
        XCTAssertEqual(lib.scanAlreadySaved(account: "a", signature: "5-1"), .unknown, "its log is the length of this scan's")
        XCTAssertEqual(lib.scanAlreadySaved(account: "missing", signature: "1-1"), .notSaved)
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
        // The shape leaguesFor returns: options (ranked first), then pick / experimental indexes and a source. Unranked members carry no
        // strength and no moves (so no needs either, whatever the entry knows).
        let json = """
        {"pokemon":[{"p":{"index":1},"hits":[],"leagues":{
          "gl":{"options":[
                  {"speciesId":"toxapex","name":"Toxapex","self":false,"strength":{"score":91.8,"rank":23,"of":1152},
                   "moves":{"fast":"Poison Jab","charged":["Brine","Sludge Wave"]},"needs":null,
                   "iv":{"rank":5,"pct":99.1,"rankPct":97.2,"level":24.5,"cp":1497},"overCap":false,
                   "cost":{"dust":175000,"candy":120,"xl":0,"evolveCandy":50,"toLevel":24.5}},
                  {"speciesId":"mareanie","name":"Mareanie","self":true,"strength":{"score":60.5,"rank":300,"of":1152},
                   "moves":{"fast":"Poison Jab","charged":["Brine"]},"needs":["Brine"],"iv":null,"overCap":false,"cost":null},
                  {"speciesId":"gallade","name":"Gallade","self":false,"genderLocked":"male","strength":null,"moves":null,"needs":null,
                   "iv":null,"overCap":true,"cost":null}],
                "pick":0,"experimental":1,"source":"emulated"},
          "ul":{"options":[{"speciesId":"mareanie","name":"Mareanie","self":true,"strength":null,"moves":null,"needs":null,"iv":null,"overCap":true,"cost":null}],
                "pick":0,"experimental":0,"source":"ranked"}}}]}
        """
        let advice = BoxAdvice.make(from: try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)), entries: box)
        let l = advice.leagues(for: box[0].id)
        // The accessors read the shown member.
        XCTAssertEqual(l["gl"]?.pick.name, "Toxapex")
        XCTAssertEqual(l["gl"]?.pick.isSelf, false)
        XCTAssertEqual(l["gl"]?.strength, .init(score: 91.8, rank: 23, of: 1152))
        XCTAssertEqual(l["gl"]?.moves, .init(fast: "Poison Jab", charged: ["Brine", "Sludge Wave"]))
        XCTAssertNil(l["gl"]?.needs)
        XCTAssertEqual(l["gl"]?.cost, .init(dust: 175000, candy: 120, xl: 0, evolveCandy: 50, toLevel: 24.5))
        XCTAssertEqual(l["gl"]?.source, "emulated")
        XCTAssertNil(l["ul"]?.needs); XCTAssertEqual(l["ul"]?.overCap, true)
        XCTAssertNil(l["ul"]?.strength); XCTAssertNil(l["ul"]?.iv); XCTAssertNil(l["ul"]?.cost)
        XCTAssertNil(l["ml"])
        XCTAssertEqual(advice.leagues(for: "nobody"), [:])
        XCTAssertEqual(advice.version, BoxAdvice.currentVersion)
        XCTAssertEqual(BoxAdvice.currentVersion, 14)

        // The options list decodes in order; the experimental member is a different index.
        let gl = try XCTUnwrap(l["gl"])
        XCTAssertEqual(gl.options.map(\.speciesId), ["toxapex", "mareanie", "gallade"])
        XCTAssertEqual(gl.pickIndex, 0); XCTAssertEqual(gl.experimentalIndex, 1)
        XCTAssertEqual(gl.experimental.speciesId, "mareanie")
        XCTAssertEqual(gl.options[1].needs, ["Brine"])
        XCTAssertEqual(gl.options[2].genderLocked, "male")
        XCTAssertNil(gl.options[2].strength); XCTAssertNil(gl.options[2].moves)
        XCTAssertEqual(l["ul"]?.options.count, 1)

        // The cache round-trips it; a file with no version (build 2) or a lower one is read as missing.
        try lib.saveAdvice(advice, account: "a", seq: 1)
        XCTAssertEqual(lib.loadAdvice(account: "a", seq: 1), advice)
        // Versions 2 (leagues only) and 3 (the first options shape, the old pick rule) are recomputed too.
        for v in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13] {
            var old = advice; old.version = v
            try lib.saveAdvice(old, account: "a", seq: 1)
            XCTAssertNil(lib.loadAdvice(account: "a", seq: 1), "version \(v)")
        }
        let legacy = #"{"builds":[],"gaps":[],"duplicates":[],"unresolved":[],"spareBuilds":{}}"#
        let file = try XCTUnwrap(FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }.first { $0.lastPathComponent.hasSuffix(".advice.json") })
        try Data(legacy.utf8).write(to: file)
        XCTAssertNil(lib.loadAdvice(account: "a", seq: 1))
    }

    func testLeagueDecodingReindexesBothPicksAndRejectsOddIndexes() throws {
        func option(_ id: String, bad: Bool = false) -> String {
            #"{"speciesId":"\#(id)","name":"\#(id)","self":false,"strength":\#(bad ? #""oops""# : "null"),"moves":null,"needs":null,"iv":null,"overCap":false,"cost":null}"#
        }
        func league(pick: String, experimental: String? = "3") -> JSONValue {
            let exp = experimental.map { #","experimental":\#($0)"# } ?? ""
            let json = #"{"options":[\#(option("a", bad: true)),\#(option("b")),\#(option("c")),\#(option("d"))],"pick":\#(pick)\#(exp),"source":"emulated"}"#
            return try! JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        }
        // The bad option sits before both picks: both indexes shift down by one and still name the same members.
        let r = try XCTUnwrap(BoxAdvice.LeagueRating.decode(league(pick: "2")))
        XCTAssertEqual(r.options.map(\.speciesId), ["b", "c", "d"])
        XCTAssertEqual(r.shown.speciesId, "c"); XCTAssertEqual(r.experimental.speciesId, "d")
        // A bad experimental option falls back to the shown member; a missing one does too.
        XCTAssertEqual(try XCTUnwrap(BoxAdvice.LeagueRating.decode(league(pick: "2", experimental: "0"))).experimental.speciesId, "c")
        XCTAssertEqual(try XCTUnwrap(BoxAdvice.LeagueRating.decode(league(pick: "2", experimental: nil))).experimental.speciesId, "c")
        // A pick that is fractional, negative, past the end or too big for an Int is no pick at all (and never traps).
        for odd in ["1.5", "-1", "9", "1e300", "-1e300"] { XCTAssertNil(BoxAdvice.LeagueRating.decode(league(pick: odd)), odd) }
        // An odd experimental index falls back to the shown member.
        for odd in ["1.5", "1e300", "-2"] { XCTAssertEqual(try XCTUnwrap(BoxAdvice.LeagueRating.decode(league(pick: "2", experimental: odd))).experimental.speciesId, "c", odd) }
        XCTAssertNil(BoxAdvice.LeagueRating.Option(json: .string("x")))
    }

    /// The hand-written option reader and the Codable one (which the cache uses) must agree on the engine's shape.
    func testOptionJSONReaderMatchesCodable() throws {
        let json = """
        {"speciesId":"toxapex","name":"Toxapex","self":true,"genderLocked":"male","strength":{"score":91.8,"rank":23,"of":1152},
         "moves":{"fast":"Poison Jab","charged":["Brine","Sludge Wave"]},"needs":["Brine"],
         "iv":{"rank":5,"pct":99.1,"rankPct":97.2,"level":24.5,"cp":1497},"overCap":false,
         "cost":{"dust":175000,"candy":120,"xl":0,"evolveCandy":50,"toLevel":24.5}}
        """
        let viaCodable = try JSONDecoder().decode(BoxAdvice.LeagueRating.Option.self, from: Data(json.utf8))
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        XCTAssertEqual(BoxAdvice.LeagueRating.Option(json: value), viaCodable)
        // Wrong types are rejected by both: a fractional dust figure, a non-string move.
        for bad in [json.replacingOccurrences(of: "175000", with: "175000.5"), json.replacingOccurrences(of: "\"Brine\",\"Sludge Wave\"", with: "\"Brine\",7")] {
            XCTAssertThrowsError(try JSONDecoder().decode(BoxAdvice.LeagueRating.Option.self, from: Data(bad.utf8)))
            XCTAssertNil(BoxAdvice.LeagueRating.Option(json: try JSONDecoder().decode(JSONValue.self, from: Data(bad.utf8))))
        }
    }

    /// The two league readers (the cache's Codable one and the engine-JSON one) must give the same answer on odd league-level shapes.
    func testLeagueReadersAgreeOnOddShapes() throws {
        let good = #"{"speciesId":"a","name":"a","self":false,"strength":null,"moves":null,"needs":null,"iv":null,"overCap":false,"cost":null}"#
        let other = good.replacingOccurrences(of: #""a""#, with: #""b""#)
        func rating(_ tail: String) -> (json: BoxAdvice.LeagueRating?, codable: BoxAdvice.LeagueRating?) {
            let text = #"{"options":[\#(good),\#(other)],\#(tail)}"#
            let value = try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
            return (BoxAdvice.LeagueRating.decode(value), try? JSONDecoder().decode(BoxAdvice.LeagueRating.self, from: Data(text.utf8)))
        }
        let cases = [
            #""pick":1,"experimental":0,"source":"export""#,
            #""pick":1,"source":"export""#,
            #""pick":1,"experimental":5,"source":"export""#, #""pick":1,"experimental":-1,"source":"export""#,
            #""pick":1,"experimental":1.5,"source":"export""#, #""pick":1,"experimental":1e300,"source":"export""#,
            #""pick":1,"experimental":"0","source":"export""#, #""pick":1,"experimental":null,"source":"export""#,
            #""pick":1,"experimental":0,"source":7"#, #""pick":1,"experimental":0,"source":null"#, #""pick":1,"experimental":0"#,
            #""pick":2,"experimental":0,"source":"export""#, #""pick":1.5,"source":"export""#, #""pick":"1","source":"export""#, #""pick":1e300"#,
        ]
        for tail in cases {
            let (a, b) = rating(tail)
            XCTAssertEqual(a, b, tail)
        }
        // The values themselves, not only the agreement.
        XCTAssertEqual(rating(#""pick":1,"experimental":1.5,"source":7"#).json?.experimentalIndex, 1)
        XCTAssertEqual(rating(#""pick":1,"experimental":1.5,"source":7"#).json?.source, "ranked")
        XCTAssertEqual(rating(#""pick":1,"experimental":0,"source":"export""#).json?.experimentalIndex, 0)
        XCTAssertNil(rating(#""pick":2"#).json)
    }

    func testBuildActionIsWordedFromTheSteps() {
        typealias S = BoxAdvice.Build.Step
        func build(powerUp: Bool = true, _ steps: [S]?) -> BoxAdvice.Build {
            BoxAdvice.Build(entryId: "e", title: "Xurkitree", cp: 3000, level: 40, ivs: nil, targetId: powerUp ? "x" : "y", targetName: "Y", powerUp: powerUp,
                            formChange: false, viaMega: false, needsDynamax: false, spares: 0, areas: ["Raids"], tier: "S", targetLevel: nil, dust: 0, candy: 0, xl: 0,
                            pvp: nil, score: 1, steps: steps)
        }
        XCTAssertEqual(build([]).action, "Already built", "an empty list is already built")
        XCTAssertEqual(build([S(kind: "powerUp", toLevel: 35, areas: ["raids"])]).action, "Power up to level 35 (Raids)")
        XCTAssertEqual(build([S(kind: "powerUp", toLevel: 30, areas: ["gym", "max"])]).action, "Power up to level 30 (Gym/Max)")
        XCTAssertEqual(build([S(kind: "powerUp", toLevel: 16, areas: ["gl"])]).action, "Power up to level 16 (GL)")
        XCTAssertEqual(build([S(kind: "powerUp")]).action, "Power up", "a power-up step without a level never reads 'to level 0'")
        XCTAssertEqual(build([S(kind: "secondMove", certain: true)]).action, "Second move")
        XCTAssertEqual(build([S(kind: "secondMove", certain: false)]).action, "Second move (if it doesn't have it)")
        // The Dynamax requirement is Max's alone: it does not make the build unfinished, and it is not hidden.
        XCTAssertEqual(build([S(kind: "needsDynamaxCopy")]).action, "Already built (Max needs a Dynamax copy)")
        var maxOnly = build([S(kind: "needsDynamaxCopy")]); maxOnly.areas = ["Max"]
        XCTAssertEqual(maxOnly.action, "Needs a Dynamax copy")
        maxOnly.steps = [S(kind: "powerUp", toLevel: 45, areas: ["max"]), S(kind: "needsDynamaxCopy")]
        XCTAssertEqual(maxOnly.action, "Power up to level 45 (Max; needs a Dynamax copy)")
        XCTAssertEqual(build([S(kind: "megaEvolve"), S(kind: "needsDynamaxCopy")]).action, "Mega evolve (Max needs a Dynamax copy)")
        XCTAssertEqual(build(powerUp: false, [S(kind: "evolve", to: "Gengar", candy: 100), S(kind: "megaEvolve"), S(kind: "eliteTM", count: 2), S(kind: "cdMove")]).action,
                       "Evolve to Gengar + Mega evolve + 2 Elite TMs + Community Day move")
        XCTAssertEqual(build([S(kind: "eliteTM", count: 1)]).action, "1 Elite TM")
        // A step this version does not know (or one with no kind) is still something to do.
        XCTAssertEqual(build([S(kind: "somethingNew")]).action, "More to do")
        XCTAssertEqual(BoxAdvice.Build.Step(json: .object(["to": .string("x")])).kind, "unknown")
        // The cost line carries dust, candy and XL only (Elite TMs and the Community Day move are steps).
        var withDust = build([]); withDust.dust = 5000
        XCTAssertEqual(withDust.costText, "5k dust")
        // A build read without the engine's steps falls back to the plain wording (never "Already built").
        XCTAssertEqual(build(nil).action, "Power up")
        XCTAssertEqual(build(powerUp: false, nil).action, "Evolve to Y")
        // The duplicate verdict is only for a copy with no build of its own, as on the Pokémon page.
        let dupe = BoxAdvice.Duplicate(name: "Eevee", count: 2, keep: ["CP 1, 15/15/15"], transfer: ["CP 2, 1/1/1"], keepIds: ["a"], transferIds: ["b"])
        XCTAssertEqual(BoxExport.adviceText(.init(builds: [], spareFor: [], duplicateOf: dupe, keep: false)), "duplicate of Eevee, transfer")
        XCTAssertFalse(BoxExport.adviceText(.init(builds: [build([])], spareFor: [], duplicateOf: dupe, keep: false)).contains("transfer"), "no transfer verdict under the copy's own build")
        XCTAssertFalse(BoxExport.adviceText(.init(builds: [build([])], spareFor: [], duplicateOf: dupe, keep: true)).contains("duplicate of"))
        // The export never words a spare as an action.
        let spare = BoxExport.adviceText(.init(builds: [], spareFor: [build([])], duplicateOf: nil, keep: false))
        XCTAssertFalse(spare.contains("Already built"))
        XCTAssertEqual(spare, "spare for the Y build (Xurkitree)")
    }

    /// Builds decoded from the REAL engine output (the bundle run on three entries), so the steps and the action cannot be constants.
    func testBuildsFromTheRealEngineCarryTheirSteps() throws {
        func record(_ index: Int, _ name: String, _ level: Double, _ ivs: (Int, Int, Int)) -> JSONValue {
            let json = """
            {"index":\(index),"name":"\(name)","form":"","gender":"","cp":500,"level":\(level),"levelMin":\(level),"levelMax":\(level),"shadow":false,"purified":false,"lucky":false,
             "ivs":{"atk":\(ivs.0),"def":\(ivs.1),"hp":\(ivs.2)},"ivPercent":80,"moves":[]}
            """
            return try! JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        }
        let rows = [record(1, "Xurkitree", 40, (15, 15, 15)), record(2, "Squirtle", 45, (0, 7, 14)), record(3, "Cramorant", 51, (15, 15, 15)), record(4, "Mankey", 12, (15, 15, 15)), record(5, "Snorlax", 10, (15, 15, 15))]
        let report = try CoreEngine().advise(box: .array(rows))
        try lib.commit(account: "a", entries: entries([100, 200, 300, 400, 500]), reason: .scan, note: "five", now: date(1))
        let box = try XCTUnwrap(lib.current(account: "a")).entries
        let advice = BoxAdvice.make(from: report, entries: box)
        func build(_ i: Int, _ target: String) throws -> BoxAdvice.Build { try XCTUnwrap(advice.builds.first { $0.entryId == box[i].id && $0.targetId == target }, target) }
        let xurk = try build(0, "xurkitree"), squirtle = try build(1, "blastoise"), cram = try build(2, "cramorant")
        XCTAssertEqual(xurk.steps, [])
        XCTAssertEqual(xurk.action, "Already built")
        // Ultra League's best level (49.5) is not what the Raids cost pays for, so there is no power-up step. The Max table lists Blastoise only
        // as Gigantamax, which the advisor never credits to an ordinary Dynamax copy, so there is no Dynamax step either.
        XCTAssertEqual(squirtle.steps?.map(\.kind), ["evolve", "megaEvolve"])
        XCTAssertEqual(squirtle.steps?.first { $0.kind == "evolve" }?.candy, 125)
        XCTAssertEqual(squirtle.action, "Evolve to Blastoise + Mega evolve")
        let climbing = try build(3, "annihilape")
        XCTAssertEqual(climbing.steps?.last, .init(kind: "powerUp", toLevel: 16, areas: ["gl"]))
        XCTAssertEqual(climbing.action, "Evolve to Annihilape + Power up to level 16 (GL)")
        // Snorlax climbs to 30 for Gym/Max: that goes past the best level of two leagues, which the app says (and the export repeats).
        let snor = try build(4, "snorlax")
        XCTAssertEqual(snor.steps?.first { $0.kind == "powerUp" }, .init(kind: "powerUp", toLevel: 30, areas: ["gym", "max"]))
        XCTAssertEqual(snor.leavesLeague, [.init(league: "UL", bestLevel: 27), .init(league: "GL", bestLevel: 16)])
        XCTAssertEqual(snor.leavesLeagueText, "going past 27 leaves UL, going past 16 leaves GL")
        XCTAssertEqual(snor.climbLevel, 30)
        XCTAssertNil(xurk.climbLevel)
        XCTAssertEqual(snor.action, "Power up to level 30 (Gym/Max; needs a Dynamax copy)")
        XCTAssertNil(xurk.leavesLeagueText)
        let exported = BoxExport.adviceText(advice.entries(for: box[4].id))
        XCTAssertTrue(exported.contains("going past 27 leaves UL, going past 16 leaves GL"), exported)
        XCTAssertEqual(cram.steps, [.init(kind: "secondMove", certain: false)])
        XCTAssertEqual(cram.action, "Second move (if it doesn't have it)")
        // A report whose first build has no `steps` key (not what the current engine produces) reads as nil, not as an empty list.
        guard case .object(var o) = report, case .array(var bs)? = o["builds"], case .object(var b0) = bs[0], case .string(let firstTarget)? = b0["targetId"] else { return XCTFail("shape") }
        b0["steps"] = nil; bs[0] = .object(b0); o["builds"] = .array(bs)
        let stripped = BoxAdvice.make(from: .object(o), entries: box).builds
        XCTAssertNil(try XCTUnwrap(stripped.first { $0.targetId == firstTarget }).steps)
        XCTAssertNotNil(try XCTUnwrap(stripped.first { $0.targetId != firstTarget }).steps)
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
