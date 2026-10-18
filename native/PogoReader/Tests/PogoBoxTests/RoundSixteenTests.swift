import XCTest
@testable import PogoBox
@testable import PogoReader

/// Round 16: the merge's one-point HP tolerance (R1), IVs read one notch apart (R2), the IVs-now-read path (R3), the Full scan "not seen" list (R4), the stop wording (R5),
/// CP-only arming (R6). Synthetic rows from the game's own formulas, so the CP, HP and IVs are consistent.
final class RoundSixteenTests: XCTestCase {
    let gm = try! GameMaster.bundled()
    func date(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(d) * 86_400) }
    let iv = IVs(atk: 10, def: 11, hp: 12)

    func row(_ id: String = "pikachu", level: Double, ivs: IVs?, shown: IVs? = nil, hpDelta: Int = 0, cpDelta: Int = 0, truth: IVs? = nil) -> ScanRow {
        let bs = gm.byId[id]!.baseStats!, t = truth ?? ivs!
        let nf = GameMaster.nameAndForm(gm.byId[id]!.name)
        return ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: id, dex: gm.byId[id]?.dex, cp: cpAt(bs, t, level) + cpDelta, hp: hpAt(bs, t, level) + hpDelta,
                       ivs: ivs, ivsRead: ivs, ivsGuess: nil, level: ivs == nil ? nil : level, levelMax: ivs == nil ? nil : level, dust: 1000, solveStatus: ivs == nil ? "unknown-ivs" : "exact",
                       flags: ivs == nil ? ["ivs-unread"] : [], frames: [])
    }
    func entry(_ r: ScanRow, _ id: String = "e", corrections: Corrections = Corrections()) -> BoxEntry { BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0), corrections: corrections) }
    func plan(_ s: [ScanRow], _ v: [BoxEntry], _ k: BoxStore.Kind = .partial, unmatched: [Unmatched] = []) -> BoxMerge.Plan {
        BoxMerge.plan(scanned: s, unmatched: unmatched, into: v, kind: k, scanDate: date(5), gameMaster: gm)
    }

    // R1
    func testR1AnHPOnePointLowerWithBarsUnreadIsAskedNeverNew() {
        let saved = entry(row(level: 10, ivs: iv))
        for d in [-1, 1] {
            let p = plan([row(level: 10, ivs: nil, hpDelta: d, truth: iv)], [saved])
            XCTAssertTrue(p.new.isEmpty, "HP \(d)"); XCTAssertEqual(p.unsure.count, 1, "HP \(d)"); XCTAssertTrue(p.same.isEmpty && p.updated.isEmpty)
        }
        // two points lower is still a different Pokémon
        XCTAssertEqual(plan([row(level: 10, ivs: nil, hpDelta: -2, truth: iv)], [saved]).new.count, 1)
    }
    func testR1APowerUpWithHPOnePointLowerIsAskedNotNew() {
        let saved = entry(row(level: 10, ivs: iv))
        let p = plan([row(level: 16, ivs: iv, hpDelta: -1)], [saved])
        XCTAssertTrue(p.new.isEmpty); XCTAssertEqual(p.unsure.count, 1); XCTAssertTrue(p.updated.isEmpty)
    }

    // R2
    /// R2 was dropped: a genuine power-up whose bars were read one notch off on a stat is added as NEW. Accepted limit: asking added 14 questions on a big catch day (19 -> 33
    /// against the 29 the shared-triple rule exists to reduce) for a misread the device logs have not shown (run8 vs run9: 0 IV disagreements in 298 pairs).
    func testR2ABarsReadOneNotchOffOnAPowerUpIsNewAnAcceptedLimit() {
        let saved = entry(row(level: 10, ivs: iv))
        let p = plan([row(level: 16, ivs: IVs(atk: 9, def: 11, hp: 12), truth: iv)], [saved])
        XCTAssertEqual(p.new.count, 1); XCTAssertTrue(p.unsure.isEmpty); XCTAssertTrue(p.updated.isEmpty)
        // two notches off on a stat, or a lower CP, is New as well
        XCTAssertEqual(plan([row(level: 16, ivs: IVs(atk: 8, def: 11, hp: 12), truth: iv)], [saved]).new.count, 1)
        XCTAssertEqual(plan([row(level: 5, ivs: IVs(atk: 9, def: 11, hp: 12), truth: iv)], [saved]).new.count, 1)
    }

    // R3
    func testR3IVsNowReadIsAutomaticOnlyForAnUncorrectedEntryAtItsCurrentValues() {
        let unread = row(level: 10, ivs: nil, truth: iv)
        let read = row(level: 10, ivs: iv)
        let p = plan([read], [entry(unread)])
        XCTAssertEqual(p.updated.map { $0.reason }, [.ivsNowRead]); XCTAssertTrue(p.unsure.isEmpty)
        // hand-corrected CP: the scan matches the UNcorrected CP (`was`), which must be asked
        var corrected = unread; corrected.cp += 7
        let q = plan([read], [entry(corrected, corrections: Corrections(cp: Fix(was: unread.cp)))])
        XCTAssertTrue(q.updated.isEmpty); XCTAssertEqual(q.unsure.count, 1)
    }

    // R4
    func testR4ANamelessUnmatchedItemStillListsTheUnpairedEntriesAsMarkable() throws {
        let a = entry(row(level: 10, ivs: iv), "a"), b = entry(row("pidgey", level: 8, ivs: IVs(atk: 3, def: 4, hp: 5)), "b")
        let item = Unmatched(frame: "f1", cp: nil, name: nil, nameText: nil, hp: nil, ivs: nil, cpOptions: nil, frames: 3, reason: "name-not-read", into: nil, clip: nil)
        let p = plan([], [a, b], .full, unmatched: [item])
        XCTAssertEqual(Set(p.gone), ["a", "b"]); XCTAssertTrue(p.kept.isEmpty)
        XCTAssertEqual(BoxMerge.unreadLine(p), "1 Pokémon on screen could not be read (names: unknown). Some of the entries below may be those.")
        let named = Unmatched(frame: "f2", cp: nil, name: "Pikachu", nameText: "Pikachu", hp: nil, ivs: nil, cpOptions: nil, frames: 3, reason: "cp-not-read", into: nil, clip: nil)
        XCTAssertEqual(BoxMerge.unreadLine(plan([], [a, b], .full, unmatched: [item, named])), "2 Pokémon on screen could not be read (names: unknown, Pikachu). Some of the entries below may be those.")
        XCTAssertNil(BoxMerge.unreadLine(plan([], [a], .full)))
        // an untouched save removes nothing; marking removes
        XCTAssertEqual(try BoxMerge.apply(p, keepGone: BoxMerge.keepSet(plan: p, resolutions: [:], markedForRemoval: []), to: [a, b]).map { $0.id }, ["a", "b"])
        XCTAssertEqual(try BoxMerge.apply(p, keepGone: BoxMerge.keepSet(plan: p, resolutions: [:], markedForRemoval: ["b"]), to: [a, b]).map { $0.id }, ["a"])
    }

    // R5
    func testR5AnAddAndUpdateStopDoesNotClaimTheCommandRanOut() {
        let near = VoiceCommandFile.setSizes.first { ScanStop.nearestSize(read: 51, commandPeriod: 1.0) == $0 }
        let s = ScanStop.summary(lastName: "Stunfisk", lastCP: 902, read: 51, appraisalClosed: false, ranOut: near != nil, commandKnown: false, nearestSize: near)
        XCTAssertFalse(s.contains("This is the size of the command"), s)
        XCTAssertTrue(s.contains("If that is the one you said, it ran out") || s.contains("short of the command's size"), s)
        let sized = ScanStop.summary(lastName: "X", lastCP: 1, read: 50, appraisalClosed: nil, ranOut: true, commandKnown: false, nearestSize: 50)
        XCTAssertTrue(sized.contains("50 read is about the size of the \"Pogo scan 50\" command. If that is the one you said, it ran out."), sized)
        let named = ScanStop.summary(lastName: "X", lastCP: 1, read: 50, appraisalClosed: nil, ranOut: true, commandKnown: true)
        XCTAssertTrue(named.contains("the command the app named for your count: it ran out"), named)
    }

    // R6
    func testR6CPOnlyCardsOneNumberApartCountAsFiveCardsForArming() {
        var d = EndOfListDetector(period: 1.2)
        var t = 0.0
        for cp in [218, 219, 220, 221, 222] {
            for _ in 0..<2 { d.feed({ var r = FrameReading(); r.cp = cp; return r }(), time: t); t += 1.2 }
        }
        XCTAssertTrue(d.armed, "five different CP-only cards read twice each arm it")
    }

    // U3 (b)
    func testU3AnUnknownCommandIsNeverCalledShortOfItsSize() {
        let s = ScanStop.summary(lastName: "Abra", lastCP: 799, read: 51, appraisalClosed: false, ranOut: false, commandKnown: false)
        XCTAssertTrue(s.contains("It stopped after 51. If that was not the end of your list, open Abra"), s)
        XCTAssertFalse(s.contains("short of the command's size"), s)
    }
}
