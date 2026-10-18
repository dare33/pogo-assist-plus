import XCTest
@testable import PogoBox
@testable import PogoReader

/// Round 17: the extra-twin question offers a same-CP-and-HP entry (U5), the unread line says what was read (U6).
final class RoundSeventeenTests: XCTestCase {
    let gm = try! GameMaster.bundled()
    func date(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(d) * 86_400) }

    func fidough(_ ivs: IVs) -> ScanRow {
        ScanRow(index: 1, name: "Fidough", display: "Fidough", form: "", speciesId: "fidough", dex: 926, cp: 768, hp: 89, ivs: ivs, ivsRead: ivs, ivsGuess: nil, level: 20, levelMax: 20, dust: 1000,
                solveStatus: "exact", flags: [], frames: [])
    }
    func entry(_ r: ScanRow, _ id: String) -> BoxEntry { BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0)) }
    let a = IVs(atk: 15, def: 4, hp: 10), b = IVs(atk: 15, def: 11, hp: 12)

    func testU5TheSecondFidoughIsOfferedAndNotListedAsNotSeen() throws {
        let saved = [entry(fidough(a), "a"), entry(fidough(b), "b")]
        let p = BoxMerge.plan(scanned: [fidough(a), fidough(a)], into: saved, kind: .full, scanDate: date(5), gameMaster: gm)
        XCTAssertEqual(p.unsure.count, 1); let u = p.unsure[0]
        XCTAssertEqual(u.kind, .extraTwin); XCTAssertEqual(u.candidates, ["a", "b"], "the paired entry first, then the same-CP-and-HP one")
        // unanswered, or left out: the other entry is not on the Not seen list
        XCTAssertTrue(BoxMerge.goneReport(p, resolutions: [:]).gone.isEmpty)
        XCTAssertTrue(BoxMerge.goneReport(p, resolutions: [u.scanned: .leaveOut]).gone.isEmpty)
        // "add a second": the 15/11/12 one was not seen, so it is listed (kept unless marked)
        XCTAssertEqual(BoxMerge.goneReport(p, resolutions: [u.scanned: .new]).gone, ["b"])
        // "It is this one" for it: seen, saved IVs kept, flagged to check, and no second 15/4/10 added
        XCTAssertEqual(BoxMerge.effect(p, u, candidate: saved[1], gameMaster: gm), .keepsIVsAndFlags)
        let out = try BoxMerge.apply(p, resolutions: [u.scanned: .existing("b")], keepGone: BoxMerge.keepSet(plan: p, resolutions: [u.scanned: .existing("b")], markedForRemoval: []), to: saved)
        XCTAssertEqual(out.map { $0.id }, ["a", "b"]); XCTAssertEqual(out[1].row.ivs, b); XCTAssertTrue(out[1].row.flags.contains(BoxMerge.ivsRescanFlag))
        // an untouched save with "leave out" removes nothing
        XCTAssertEqual(try BoxMerge.apply(p, resolutions: [u.scanned: .leaveOut], keepGone: BoxMerge.keepSet(plan: p, resolutions: [u.scanned: .leaveOut], markedForRemoval: []), to: saved).count, 2)
        // a lone saved Fidough: the question is the old one, with the one candidate
        let one = BoxMerge.plan(scanned: [fidough(a), fidough(a)], into: [entry(fidough(a), "a")], kind: .full, scanDate: date(5), gameMaster: gm)
        XCTAssertEqual(one.unsure.first?.candidates, ["a"])
    }

    func testU6TheUnreadLineSaysWhatWasRead() {
        func item(name: String?, text: String?, cp: Int?) -> Unmatched { Unmatched(frame: "f", cp: cp, name: name, nameText: text, hp: nil, ivs: nil, cpOptions: nil, frames: 3, reason: "cp-not-read", into: nil, clip: nil) }
        let p = BoxMerge.plan(scanned: [], unmatched: [item(name: nil, text: "Tinkat", cp: 282), item(name: "Pikachu", text: "Pikachu", cp: nil), item(name: nil, text: nil, cp: nil)],
                              into: [entry(fidough(a), "a")], kind: .full, scanDate: date(5), gameMaster: gm)
        XCTAssertEqual(BoxMerge.unreadLine(p), "3 Pokémon on screen could not be read (names: Tinkat… CP 282, Pikachu, unknown). Some of the entries below may be those.")
    }
}
