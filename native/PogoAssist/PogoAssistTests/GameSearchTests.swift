import XCTest
@testable import PogoAssist
@testable import PogoBox
import PogoReader

/// The search a Review question offers. A "could be this saved one" question (Darentas scan of 23 Nov 2026: Meowth CP 445 read, Meowth CP 121 saved) names both CPs,
/// so the game shows two Pokémon when they are different and one when they are the same.
final class GameSearchTests: XCTestCase {
    private func row(_ name: String, cp: Int, hp: Int?, ivs: IVs? = nil, species: String? = nil, flags: [String] = []) -> ScanRow {
        ScanRow(index: 1, name: name, display: name, form: "", speciesId: species ?? name.lowercased(), dex: nil, cp: cp, hp: hp, ivs: ivs, ivsRead: ivs, ivsGuess: nil,
                level: nil, levelMax: nil, dust: nil, solveStatus: ivs == nil ? "ambiguous" : "exact", flags: flags, frames: [])
    }

    private func entry(_ id: String, _ r: ScanRow) -> BoxEntry { BoxEntry(id: id, row: r, firstSeen: Date(timeIntervalSince1970: 0), lastSeen: Date(timeIntervalSince1970: 0)) }

    private func search(_ kind: BoxMerge.Unsure.Kind, read: ScanRow, saved: [BoxEntry]) -> String? {
        let u = BoxMerge.Unsure(scanned: 0, candidates: saved.map(\.id), kind: kind)
        return GameSearch.text([GameSearch.part(for: u, row: read, saved: Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) }))])
    }

    func testAmbiguousNamesTheSavedCPAndTheReadCP() {
        let saved = entry("a", row("Meowth", cp: 121, hp: 42, ivs: IVs(atk: 6, def: 6, hp: 3)))
        XCTAssertEqual(search(.ambiguous, read: row("Meowth", cp: 445, hp: 80), saved: [saved]), "meowth&cp121,cp445")
    }

    func testAmbiguousWithSeveralCandidatesNamesEachOnce() {
        let saved = [entry("a", row("Bunnelby", cp: 350, hp: 84)), entry("b", row("Bunnelby", cp: 83, hp: 45)), entry("c", row("Bunnelby", cp: 350, hp: 84))]
        XCTAssertEqual(search(.ambiguous, read: row("Bunnelby", cp: 95, hp: 44), saved: saved), "bunnelby&cp350,cp83,cp95")
    }

    func testAmbiguousEvolutionNamesBothSpecies() {
        let saved = entry("a", row("Machoke", cp: 834, hp: 110))
        XCTAssertEqual(search(.ambiguous, read: row("Machamp", cp: 1266, hp: 130), saved: [saved]), "machoke,machamp&cp834,cp1266")
    }

    func testUntrustedCPsAreSearchedByHP() {
        let saved = entry("a", row("Meowth", cp: 12, hp: 42, flags: ["no-level-fits"]))
        XCTAssertEqual(search(.ambiguous, read: row("Meowth", cp: 445, hp: 80), saved: [saved]), "meowth&hp42,cp445")
        let good = entry("b", row("Meowth", cp: 121, hp: 42))
        XCTAssertEqual(search(.ambiguous, read: row("Meowth", cp: 45, hp: 80, flags: ["no-level-fits"]), saved: [good]), "meowth&cp121,hp80")
    }

    func testMegaOnEitherSideKeepsTheReadCPOnly() {
        let base = entry("a", row("Blaziken", cp: 2819, hp: 150))
        XCTAssertEqual(search(.ambiguous, read: row("Blaziken", cp: 3600, hp: 150, species: "blaziken_mega"), saved: [base]), "blaziken&cp3600")
        let mega = entry("b", row("Blaziken", cp: 3600, hp: 150, species: "blaziken_mega"))
        XCTAssertEqual(search(.ambiguous, read: row("Blaziken", cp: 2819, hp: 150), saved: [mega]), "blaziken&cp2819")
    }

    func testTooManyCandidatesKeepsTheReadCPOnly() {
        let saved = (0...GameSearch.mostCandidates).map { entry("s\($0)", row("Pidgey", cp: 100 + $0, hp: 30)) }
        XCTAssertEqual(search(.ambiguous, read: row("Pidgey", cp: 426, hp: 60), saved: saved), "pidgey&cp426")
        XCTAssertEqual(search(.ambiguous, read: row("Pidgey", cp: 426, hp: 60), saved: Array(saved.dropLast())), "pidgey&cp100,cp101,cp102,cp103,cp104,cp105,cp426")
    }

    func testOtherKindsAreUnchanged() {
        let saved = entry("a", row("Dialga", cp: 2302, hp: 131, ivs: IVs(atk: 15, def: 14, hp: 15)))
        let read = row("Dialga", cp: 2820, hp: 145, ivs: IVs(atk: 15, def: 14, hp: 15))
        XCTAssertEqual(search(.poweredUp, read: read, saved: [saved]), "dialga&cp2302,cp2820")
        XCTAssertEqual(search(.partialRead, read: row("Dialga", cp: 230, hp: 131), saved: [saved]), "dialga&hp131")
        XCTAssertEqual(search(.misreadSaved, read: read, saved: [saved]), "dialga&cp2820")
        XCTAssertEqual(search(.extraTwin, read: read, saved: [saved]), "dialga&cp2820")
    }
}
