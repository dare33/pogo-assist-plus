import XCTest
@testable import PogoBox
@testable import PogoReader

/// Round 19: an entry paired as Same is never an extra twin's candidate or "not seen" (L4), an extra twin's other candidate keeps its IVs (L5), a finish by the person never reads as
/// "ended by itself" (M2).
final class RoundNineteenTests: XCTestCase {
    let gm = try! GameMaster.bundled()
    func date(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(d) * 86_400) }
    func fidough(_ ivs: IVs, status: String = "exact", guess: IVs? = nil) -> ScanRow {
        ScanRow(index: 1, name: "Fidough", display: "Fidough", form: "", speciesId: "fidough", dex: 926, cp: 768, hp: 89, ivs: ivs, ivsRead: ivs, ivsGuess: guess, level: 20, levelMax: 20, dust: 1000,
                solveStatus: status, flags: [], frames: [])
    }
    func entry(_ r: ScanRow, _ id: String) -> BoxEntry { BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0)) }
    let a = IVs(atk: 15, def: 4, hp: 10), b = IVs(atk: 15, def: 11, hp: 12)

    /// Scanned a, a, b against saved a, b: b is paired as Same by the second component, so it is neither offered for the extra a nor listed as not seen.
    func testL4AnEntryPairedAsSameIsNotAnExtraTwinCandidateOrNotSeen() throws {
        let saved = [entry(fidough(a), "a"), entry(fidough(b), "b")]
        let p = BoxMerge.plan(scanned: [fidough(a), fidough(a), fidough(b)], into: saved, kind: .full, scanDate: date(5), gameMaster: gm)
        XCTAssertTrue(p.same.contains { $0.savedId == "b" })
        let u = try XCTUnwrap(p.unsure.first { $0.kind == .extraTwin })
        XCTAssertEqual(u.candidates, ["a"], "b was paired, so it is not offered")
        for res in [[:], [u.scanned: BoxMerge.Resolution.new], [u.scanned: .leaveOut]] as [[Int: BoxMerge.Resolution]] {
            XCTAssertTrue(BoxMerge.goneReport(p, resolutions: res).gone.isEmpty, "\(res)")
        }
        XCTAssertTrue(p.unpaired.isEmpty)
    }

    /// The extra twin's other candidate keeps its saved IVs even when they were a shaky read; the first candidate is only marked seen.
    func testL5AnExtraTwinsOtherCandidateKeepsItsShakySavedIVs() throws {
        let shaky = entry(fidough(b, status: "approximate", guess: b), "b")
        let saved = [entry(fidough(a), "a"), shaky]
        let p = BoxMerge.plan(scanned: [fidough(a), fidough(a)], into: saved, kind: .full, scanDate: date(5), gameMaster: gm)
        let u = try XCTUnwrap(p.unsure.first)
        XCTAssertEqual(u.kind, .extraTwin); XCTAssertEqual(u.candidates, ["a", "b"])
        XCTAssertTrue(BoxMerge.ivsReplaceable(fidough(a), shaky), "the shaky entry would be replaced by any other kind of question")
        XCTAssertEqual(BoxMerge.effect(p, u, candidate: shaky, gameMaster: gm), .keepsIVsAndFlags)
        let out = try BoxMerge.apply(p, resolutions: [u.scanned: .existing("b")], keepGone: [], to: saved)
        XCTAssertEqual(out.first { $0.id == "b" }?.row.ivs, b); XCTAssertTrue(out.first { $0.id == "b" }?.row.flags.contains(BoxMerge.ivsRescanFlag) == true)
    }

    /// M2: a scan the person finished says so everywhere the app words it, and a pause that did not resume does not say it carried on.
    func testM2APersonsFinishNeverReadsAsEndedByItself() {
        let d = ScanKindAdvice.decide(endedAtListEnd: false, pokemonRead: 298, typedCount: 300, logTruncated: false, logFailed: false, commandPeriod: 1.2)
        XCTAssertFalse(d.fullIsSound); XCTAssertNil(ScanKindAdvice.matchSentence(pokemonRead: 298, decision: d), "no 'matches the count' for a scan the person finished")
        let line = ScanStop.summary(lastName: "A", lastCP: 1, read: 298, appraisalClosed: false, ranOut: false, commandKnown: true, matchSentence: ScanKindAdvice.matchSentence(pokemonRead: 298, decision: d), paused: ["A (CP 1), not resumed: you finished it"], byPerson: true)
        XCTAssertTrue(line.hasPrefix("You finished the scan")); XCTAssertFalse(line.contains("by itself")); XCTAssertFalse(line.contains("resumed after")); XCTAssertFalse(line.contains("carried on"))
        let timeout = ScanStop.summary(lastName: "A", lastCP: 1, read: 5, appraisalClosed: nil, ranOut: false, commandKnown: true, paused: ["A (CP 1), not resumed: the scan finished at the timeout"])
        XCTAssertTrue(timeout.contains("not resumed") && !timeout.contains("resumed after") && !timeout.contains("carried on") && !timeout.contains("You finished"))
    }
}
