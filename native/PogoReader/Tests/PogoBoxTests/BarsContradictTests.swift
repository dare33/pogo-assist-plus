import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// A row whose IVs were not solved is matched as one with no IVs, but its bars were read: a saved entry those bars GROSSLY contradict is not offered as "maybe this one,
/// powered up" (`BoxMerge.barsContradict`). The first numbers are Greg's Darentas scan of 23 Nov 2026: Meowth CP 445 / HP 80, bars read 15/11/15 on all three frames
/// (38 IV sets fit, none of them near the bars), against a saved Meowth CP 121 / HP 42 with 6/6/3. The others are misreads from the device runs, which must stay questions.
final class BarsContradictTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private func date(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(d) * 86_400) }
    private func iv(_ a: Int, _ d: Int, _ h: Int) -> IVs { IVs(atk: a, def: d, hp: h) }
    private func text(_ i: IVs) -> String { "\(i.atk)/\(i.def)/\(i.hp)" }

    /// `frames`: what each frame read off the bars; by default three frames that all read `read`.
    private func row(_ id: String, cp: Int, hp: Int?, ivs: IVs? = nil, read: IVs? = nil, frames: [IVs?]? = nil, guess: IVs? = nil, status: String? = nil, flags: [String] = []) -> ScanRow {
        let nf = GameMaster.nameAndForm(gm.byId[id]?.name ?? id)
        let bars = read ?? ivs
        let labels = (frames ?? [bars, bars, bars]).enumerated().map { i, f in
            FrameLabel(frame: "r\(i)", time: Double(i) * 0.4, cp: cp, cpText: "CP\(cp)", name: nf.name, hp: hp.map { "\($0)/\($0)" }, ivs: f.map(text), ivConfidence: 0.7, sharpness: 0, clip: nil)
        }
        return ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: id, dex: gm.byId[id]?.dex, cp: cp, hp: hp, ivs: ivs, ivsRead: bars, ivsGuess: guess,
                       level: nil, levelMax: nil, dust: nil, solveStatus: status ?? (ivs == nil ? "ambiguous" : "exact"), flags: flags, frames: labels)
    }
    private func entry(_ r: ScanRow, _ id: String, was: IVs? = nil) -> BoxEntry {
        BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0), corrections: was.map { Corrections(ivs: Fix(was: $0)) } ?? Corrections())
    }
    private func plan(_ s: [ScanRow], _ v: [BoxEntry], _ k: BoxStore.Kind = .partial) -> BoxMerge.Plan { BoxMerge.plan(scanned: s, into: v, kind: k, scanDate: date(5), gameMaster: gm) }
    private func at(_ id: String, _ level: Double, _ ivs: IVs) -> (cp: Int, hp: Int) { let b = gm.byId[id]!.baseStats!; return (cpAt(b, ivs, level), hpAt(b, ivs, level)) }

    private var savedMeowth: ScanRow { row("meowth", cp: 121, hp: 42, ivs: iv(6, 6, 3)) }
    private let ambiguous = ["ambiguous-ivs:38-fit", "bars-unsettled"]
    private func meowth(read: IVs, frames: [IVs?]? = nil, guess: IVs? = nil) -> ScanRow { row("meowth", cp: 445, hp: 80, read: read, frames: frames, guess: guess, flags: ambiguous) }

    // MARK: the case the rule exists for

    func testTheMeowthWhoseBarsGrosslyContradictTheSavedIVsIsNewNotAQuestion() {
        let p = plan([meowth(read: iv(15, 11, 15), guess: iv(14, 11, 9))], [entry(savedMeowth, "m")])
        XCTAssertTrue(p.unsure.isEmpty, "bars 15/11/15 on every frame cannot be a 6/6/3 Meowth")
        XCTAssertEqual(p.new, [0])
    }

    func testWithNoBarsReadTheSameRowIsStillAsked() {
        // The question this rule removes exists only because the bars are ignored: with none read there is nothing to contradict, and it is asked as before.
        let p = plan([row("meowth", cp: 445, hp: 80, frames: [nil, nil, nil], flags: ["ambiguous-ivs:38-fit"])], [entry(savedMeowth, "m")])
        XCTAssertEqual(p.unsure.map(\.candidates), [["m"]])
        XCTAssertEqual(p.unsure.first?.kind, .ambiguous)
    }

    // MARK: what keeps it from rejecting the true Pokémon

    func testOneFrameOrFramesThatDisagreeProveNothing() {
        let bars = iv(15, 11, 15)
        for frames: [IVs?] in [[bars], [bars, nil, nil], [bars, bars, iv(15, 11, 14)], []] {
            XCTAssertEqual(plan([meowth(read: bars, frames: frames)], [entry(savedMeowth, "m")]).unsure.map(\.candidates), [["m"]], "frames \(frames.map { $0.map(text) ?? "-" })")
        }
        XCTAssertEqual(plan([meowth(read: bars, frames: [bars, nil, bars])], [entry(savedMeowth, "m")]).new, [0], "two frames that agree, one without bars")
    }

    func testFramesThatAgreeWithEachOtherButNotWithTheRowsBarsProveNothing() {
        // run15 Wattrel: five frames read 5/7/11, the row's bars are 5/8/11.
        let other = iv(15, 11, 14)
        XCTAssertEqual(plan([meowth(read: iv(15, 11, 15), frames: [other, other, other])], [entry(savedMeowth, "m")]).unsure.map(\.candidates), [["m"]])
    }

    func testOnlyTwoStatsMoreThanABarSegmentOffIsAContradiction() {
        // against the saved 6/6/3
        for near in [iv(15, 6, 3), iv(6, 6, 15), iv(11, 11, 8), iv(12, 11, 3), iv(8, 9, 6)] {
            XCTAssertEqual(plan([meowth(read: near)], [entry(savedMeowth, "m")]).unsure.map(\.candidates), [["m"]], "bars \(text(near)) are not two stats more than 5 away")
        }
        for far in [iv(12, 12, 3), iv(12, 6, 9), iv(6, 12, 9)] {
            XCTAssertEqual(plan([meowth(read: far)], [entry(savedMeowth, "m")]).new, [0], "bars \(text(far))")
        }
    }

    func testTheSolversGuessNearTheSavedIVsKeepsTheQuestion() {
        let p = plan([meowth(read: iv(15, 11, 15), guess: iv(6, 7, 3))], [entry(savedMeowth, "m")])
        XCTAssertEqual(p.unsure.map(\.candidates), [["m"]])
    }

    /// The failure the rule must not cause: a Pokémon that was powered up, read with the kind of misread the device runs show, silently becoming New.
    func testARealPowerUpWithMisreadBarsIsStillAsked() {
        // run15 Wattrel: true 5/10/11, bars read 5/8/11. run24 Ekans: true 14/11/13, bars 9/11/13. run12 Weezing: true 2/15/3, bars 8/10/3. run15 Hatenna: true 11/11/3, bars 11/9/6.
        let cases: [(id: String, truth: IVs, bars: IVs)] = [("wattrel", iv(5, 10, 11), iv(5, 8, 11)), ("ekans", iv(14, 11, 13), iv(9, 11, 13)), ("weezing", iv(2, 15, 3), iv(8, 10, 3)), ("hatenna", iv(11, 11, 3), iv(11, 9, 6))]
        for c in cases {
            let before = at(c.id, 10, c.truth), after = at(c.id, 20, c.truth)
            let saved = entry(row(c.id, cp: before.cp, hp: before.hp, ivs: c.truth), "s")
            for kind in [BoxStore.Kind.partial, .full] {
                let p = plan([row(c.id, cp: after.cp, hp: after.hp, read: c.bars, flags: ["ambiguous-ivs:9-fit"])], [saved], kind)
                XCTAssertEqual(p.unsure.map(\.candidates), [["s"]], "\(c.id) powered up, bars \(text(c.bars)) for \(text(c.truth)), \(kind)")
                XCTAssertTrue(p.new.isEmpty, "\(c.id): not New")
            }
        }
    }

    func testAnEvolvedRowIsJudgedTheSameWay() {
        let ivs = iv(3, 4, 2), a = at("machop", 10, ivs), b = at("machoke", 20, ivs)
        let saved = entry(row("machop", cp: a.cp, hp: a.hp, ivs: ivs), "s")
        XCTAssertEqual(plan([row("machoke", cp: b.cp, hp: b.hp, read: iv(4, 4, 8), flags: ["ambiguous-ivs:9-fit"])], [saved]).unsure.map(\.candidates), [["s"]], "an ordinary misread: asked")
        XCTAssertEqual(plan([row("machoke", cp: b.cp, hp: b.hp, read: iv(15, 4, 14), flags: ["ambiguous-ivs:9-fit"])], [saved]).new, [0], "bars on every frame two stats more than 5 away")
    }

    // MARK: never judged

    func testTheSameCPWithAnHPEqualOnePointOffOrUnreadIsKept() {
        let read = row("weezing", cp: 883, hp: 85, read: iv(15, 2, 15), flags: ambiguous)
        func saved(cp: Int, hp: Int?) -> BoxEntry { entry(row("weezing", cp: cp, hp: hp, ivs: iv(2, 15, 3)), "w") }
        XCTAssertFalse(BoxMerge.barsContradict(read, saved(cp: 883, hp: 85)))
        XCTAssertFalse(BoxMerge.barsContradict(read, saved(cp: 883, hp: 84)))
        XCTAssertFalse(BoxMerge.barsContradict(read, saved(cp: 883, hp: nil)))
        XCTAssertFalse(BoxMerge.barsContradict(row("weezing", cp: 883, hp: nil, read: iv(15, 2, 15), flags: ambiguous), saved(cp: 883, hp: 85)))
        XCTAssertTrue(BoxMerge.barsContradict(read, saved(cp: 883, hp: 80)), "same CP, another HP: judged")
        XCTAssertTrue(BoxMerge.barsContradict(read, saved(cp: 700, hp: 76)))
    }

    func testRowsAndEntriesThatAreNeverJudged() {
        let bars = iv(15, 11, 15), m = entry(savedMeowth, "m")
        XCTAssertTrue(BoxMerge.barsContradict(meowth(read: bars), m), "the judged case, for contrast")
        XCTAssertFalse(BoxMerge.barsContradict(row("meowth", cp: 445, hp: 80, ivs: bars), m), "clean IVs: other rules decide")
        XCTAssertFalse(BoxMerge.barsContradict(row("meowth", cp: 9445, hp: 80, read: bars, status: "none", flags: ["no-level-fits"]), m), "its CP is what was misread: rule 7's ranked list")
        XCTAssertFalse(BoxMerge.barsContradict(row("meowth", cp: 0, hp: 80, read: bars, flags: ambiguous), m), "no CP")
        XCTAssertFalse(BoxMerge.barsContradict(meowth(read: bars), entry(row("meowth", cp: 121, hp: 42, frames: []), "m")), "a saved entry with no IVs")
        XCTAssertFalse(BoxMerge.barsContradict(meowth(read: bars), entry(savedMeowth, "m", was: iv(15, 10, 9))), "its IVs before the hand correction are not two stats away")
        XCTAssertFalse(BoxMerge.barsContradict(meowth(read: bars, guess: iv(14, 11, 9)), entry(savedMeowth, "m", was: iv(14, 10, 9))), "the solver's guess is within a notch of its IVs before the correction")
        let corrected = row("meowth", cp: 445, hp: 80, ivs: iv(6, 6, 3), read: bars, status: "corrected", flags: ["ivs-corrected-from-15/11/15"])
        XCTAssertFalse(BoxMerge.cleanIVs(corrected))
        XCTAssertFalse(BoxMerge.barsContradict(corrected, m), "the solver's corrected value is the saved one's IVs")
    }

    func testANoLevelFitsRowKeepsItsCandidateThroughThePlan() {
        let nlf = row("meowth", cp: 1445, hp: 80, read: iv(15, 11, 15), status: "none", flags: ["no-level-fits"])
        let with = plan([nlf], [entry(savedMeowth, "m")]), bare = plan([row("meowth", cp: 1445, hp: 80, frames: [], status: "none", flags: ["no-level-fits"])], [entry(savedMeowth, "m")])
        XCTAssertEqual(with.unsure.map(\.candidates), bare.unsure.map(\.candidates), "the bars change nothing for a row whose CP fits no level")
    }
}
