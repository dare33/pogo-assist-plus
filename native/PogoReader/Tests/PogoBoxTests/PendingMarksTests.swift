import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// The page draws a mark the moment it is tapped and saves behind: the row it draws, and the one edit that takes the saved row to it (`PokemonPage.row(applying:)`,
/// `showing`, `edit(from:to:)`).
final class PendingMarksTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private func entry(_ speciesId: String = "scyther") -> BoxEntry {
        let sp = gm.byId[speciesId]!
        let nf = GameMaster.nameAndForm(sp.name)
        let r = ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: sp.id, dex: sp.dex, cp: 1500, hp: 120, ivs: IVs(atk: 10, def: 11, hp: 12), ivsRead: nil, ivsGuess: nil,
                        level: 20, levelMax: 20, dust: 2500, solveStatus: "exact", flags: [], frames: [])
        let d = Date(timeIntervalSince1970: 1_790_000_000)
        return BoxEntry(id: "e", row: r, firstSeen: d, lastSeen: d)
    }

    private typealias Tap = (ScanRow) -> BoxMerge.Edit
    private let taps: [(String, Tap)] = [
        ("Dynamax", { PokemonPage.toggleDynamax($0) }), ("Shadow", { PokemonPage.toggleShadow($0) }), ("Lucky", { PokemonPage.toggle(.lucky, $0) }),
        ("Purified", { PokemonPage.toggle(.purified, $0) }), ("Gigantamax", { PokemonPage.toggle(.gigantamax, $0) }),
        ("Best Buddy", { PokemonPage.toggle(.bestBuddy, $0) }), ("Weather-boosted", { PokemonPage.toggle(.weatherBoosted, $0) }),
    ]

    /// The row the page would draw after these taps, each made on the row the previous one gave.
    private func wanted(after sequence: [Int], from e: BoxEntry) throws -> ScanRow {
        var row = e.row
        for i in sequence {
            var from = e; from.row = row
            row = try XCTUnwrap(PokemonPage.row(applying: taps[i].1(row), to: from, gm: gm))
        }
        return row
    }

    func testAnEvenNumberOfTapsOnOneMarkIsNoEditAtAll() throws {
        var e = entry()
        for i in taps.indices {
            e.row.dynamax = taps[i].0 == "Gigantamax" ? true : nil   // the Gigantamax chip is only there while Dynamax is on
            let w = try wanted(after: [i, i], from: e)
            XCTAssertTrue(PokemonPage.sameMarks(w, e.row), taps[i].0)
            XCTAssertEqual(PokemonPage.edit(from: e.row, to: w), BoxMerge.Edit(), "\(taps[i].0) twice saves nothing")
        }
        e.row.dynamax = nil
        let odd = try wanted(after: [0, 0, 0], from: e)
        XCTAssertEqual(odd.dynamax, true)
        XCTAssertEqual(PokemonPage.edit(from: e.row, to: odd), BoxMerge.Edit(dynamax: .on))
    }

    func testShadowOnClearsPurifiedAndTheReverse() throws {
        let e = entry()
        XCTAssertEqual(try wanted(after: [3], from: e).shadow, 2)
        XCTAssertEqual(try wanted(after: [3, 1], from: e).shadow, 1, "Shadow on clears Purified")
        XCTAssertEqual(try wanted(after: [1, 3], from: e).shadow, 2, "Purified on clears Shadow")
        XCTAssertEqual(try wanted(after: [1, 1], from: e).shadow, 0, "Shadow off is marked neither by hand")
        XCTAssertEqual(PokemonPage.edit(from: e.row, to: try wanted(after: [1, 1], from: e)), BoxMerge.Edit(), "but from never marked it is no change to save")
        var shadowed = e; shadowed.row.shadow = 1
        XCTAssertEqual(PokemonPage.edit(from: shadowed.row, to: try wanted(after: [1], from: shadowed)), BoxMerge.Edit(shadow: .neither), "a saved Shadow turned off is saved")
    }

    /// Any run of taps, drawn at once, saved as the one edit from the saved row, ends with the saved row carrying exactly the marks that were drawn.
    func testAnyRunOfTapsSavesAsOneEditThatGivesTheDrawnMarks() throws {
        let e = entry()
        var seed: UInt64 = 7
        func next(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
        for _ in 0..<300 {
            let run = (0..<(1 + next(9))).map { _ in next(taps.count) }
            let w = try wanted(after: run, from: e)
            let edit = PokemonPage.edit(from: e.row, to: w)
            let saved = try BoxMerge.correct(e, with: edit, gameMaster: gm).row
            XCTAssertTrue(PokemonPage.sameMarks(saved, w), "taps \(run.map { taps[$0].0 })")
            XCTAssertTrue(edit.marksOnly)
            if PokemonPage.sameMarks(w, e.row) { XCTAssertEqual(edit, BoxMerge.Edit(), "taps \(run.map { taps[$0].0 }) cancel out") }
        }
    }

    /// The same, from a row that already carries marks, so turning marks off is covered (Dynamax off clears Gigantamax).
    func testSavedMarksCanBeTurnedOffAndOn() throws {
        var e = entry()
        e.row.dynamax = true; e.row.gigantamax = true; e.row.shadow = 1; e.row.lucky = true
        e.row.details = CopyDetails(bestBuddy: true)
        var seed: UInt64 = 99
        func next(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
        for _ in 0..<300 {
            let run = (0..<(1 + next(9))).map { _ in next(taps.count) }
            let w = try wanted(after: run, from: e)
            let saved = try BoxMerge.correct(e, with: PokemonPage.edit(from: e.row, to: w), gameMaster: gm).row
            XCTAssertTrue(PokemonPage.sameMarks(saved, w), "taps \(run.map { taps[$0].0 })")
        }
    }

    func testShowingTakesOnlyTheMarksFromTheWantedRow() throws {
        let e = entry()
        var w = try wanted(after: [0, 1], from: e)
        w.cp = 1   // not a mark: never shown
        let shown = PokemonPage.showing(w, on: e.row)
        XCTAssertEqual(shown.dynamax, true); XCTAssertEqual(shown.shadow, 1)
        XCTAssertEqual(shown.cp, e.row.cp)
    }
}
