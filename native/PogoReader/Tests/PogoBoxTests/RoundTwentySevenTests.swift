import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// Round 27 (run20, the phone trial of a8b519b): a card whose CP was read with one digit wrong beside its own solved row is folded in, and the question for a row that cannot be
/// identified by its CP offers the same-species, same-HP entries first, ranked.
final class RoundTwentySevenTests: XCTestCase {
    private let hint = PagingHint(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds)
    private let gm = try! GameMaster.bundled()
    private func date(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(d) * 86_400) }

    // MARK: change 2, on run20

    func testRun20sThreeOneDigitMisreadsAreFoldedIntoTheirOwnCards() throws {
        let out = try ScanPipeline.process(replay: Fixture.url("run20-closed-digit-misreads.replay.jsonl"), engine: sharedEngine, paging: hint).scan.rows
        XCTAssertFalse(out.contains { [9017, 987, 982, 82].contains($0.cp) }, "none of the three misread rows is left: \(out.map { "\($0.display) \($0.cp)/\($0.hp ?? 0) \($0.flags)" })")
        let ch = out.filter { $0.display == "Charizard" }
        XCTAssertEqual(ch.map { $0.cp }, [2017]); XCTAssertTrue(ch.first?.flags.contains("folded-digit-misread:9017") == true)
        XCTAssertEqual(out.filter { $0.display == "Staraptor" && $0.hp == 141 && $0.cp == 1987 }.count, 1)
        XCTAssertTrue(out.first { $0.display == "Staraptor" && $0.cp == 1987 }?.flags.contains { $0.hasSuffix(":987") } == true, "folded in (a note when the beat is regular, a check by the digit rule on the whole log)")
        let s140 = out.first { $0.display == "Staraptor" && $0.hp == 140 && $0.cp == 1982 }
        XCTAssertTrue(s140?.flags.contains("folded-digit-misread:982") == true, "the two-reading row (82, 982) votes 982: one digit missing from 1982")
        XCTAssertTrue(out.contains { $0.display == "Staraptor" && $0.hp == 142 && $0.cp == 1982 }, "the neighbour with another HP is its own Pokémon")
        XCTAssertEqual(FlagInfo.severity(of: "folded-digit-misread:982", solveStatus: "exact"), .check)
    }

    // MARK: change 2, the rule

    private func fr(_ t: Double, cp: Int, hp: Int) -> FrameLabel {
        FrameLabel(frame: "f\(Int(t * 100))", time: t, cp: cp, cpText: String(cp), name: "Charizard", hp: "\(hp)/\(hp)", ivs: "12/13/13", ivConfidence: 0.9, sharpness: 1, clip: nil)
    }
    private func row(_ i: Int, cp: Int, hp: Int, times: [Double], fits: Bool, exact: Bool = true, bars: IVs? = IVs(atk: 12, def: 13, hp: 13), species: String = "charizard") -> ScanRow {
        ScanRow(index: i, name: "Charizard", display: "Charizard", form: "", speciesId: species, dex: 6, cp: cp, hp: hp, ivs: fits ? bars : nil, ivsRead: bars, ivsGuess: nil, level: fits ? 20 : nil, levelMax: fits ? 20 : nil,
                dust: 0, solveStatus: fits && exact ? "exact" : "none", flags: fits ? [] : ["no-level-fits"], frames: times.map { fr($0, cp: cp, hp: hp) })
    }
    private func fold(_ rows: [ScanRow]) -> [ScanRow] { Refine.absorbFragments(ScanResult(rows: rows, review: [], unmatched: [])).scan.rows }
    /// Pidgey and Rattata before and after, 9 s apart, so the fragment's neighbours are the Charizard rows only.
    private func line(_ middle: [ScanRow]) -> [ScanRow] {
        [row(1, cp: 1500, hp: 90, times: [0, 0.4, 0.8], fits: true, species: "pidgey").with(name: "Pidgey")] + middle + [row(9, cp: 1400, hp: 91, times: [10, 10.4, 10.8], fits: true, species: "rattata").with(name: "Rattata")]
    }
    private func own(_ times: [Double] = [2.4, 2.8]) -> ScanRow { row(3, cp: 2017, hp: 132, times: times, fits: true) }

    func testOneDigitMisreadsOfEveryKindFoldAndCarryTheirOwnFlag() {
        for (cp, label) in [(9017, "one digit changed"), (217, "one missing"), (20177, "one extra")] {
            let out = fold(line([row(2, cp: cp, hp: 132, times: [1.6], fits: false), own()]))
            XCTAssertEqual(out.count, 3, label)
            XCTAssertTrue(out.first { $0.cp == 2017 }?.flags.contains("folded-digit-misread:\(cp)") == true, label)
            XCTAssertEqual(FlagInfo.severity(of: "folded-digit-misread:\(cp)", solveStatus: "exact"), .check)
        }
        XCTAssertTrue(FlagInfo.explain("folded-digit-misread:9017").contains("one digit different (9017)"))
        XCTAssertFalse(FlagInfo.explain("folded-digit-misread:9017").contains("slid"), "its own text, not the sliding-in one")
    }

    func testWhatMustNeverBeFolded() {
        // a row that FITS a level is a real Pokémon, however close its CP
        XCTAssertEqual(fold(line([row(2, cp: 2018, hp: 132, times: [1.6], fits: true), own()])).count, 4)
        // two digits off
        XCTAssertEqual(fold(line([row(2, cp: 9917, hp: 132, times: [1.6], fits: false), own()])).count, 4)
        // another HP
        XCTAssertEqual(fold(line([row(2, cp: 9017, hp: 131, times: [1.6], fits: false), own()])).count, 4)
        // three readings
        XCTAssertEqual(fold(line([row(2, cp: 9017, hp: 132, times: [1.6, 2.0, 2.4], fits: false), own([2.8, 3.2])])).count, 4)
        // an unsolved neighbour, 0.8 s away (outside the older rules' 0.4 s, inside the digit rule's 0.85 s: only `exact` stops it)
        XCTAssertEqual(fold(line([row(2, cp: 9017, hp: 132, times: [1.2], fits: false), row(3, cp: 2017, hp: 132, times: [2.0, 2.4], fits: true, exact: false)])).count, 4)
        XCTAssertEqual(fold(line([row(2, cp: 9017, hp: 132, times: [1.2], fits: false), row(3, cp: 2017, hp: 132, times: [2.0, 2.4], fits: true)])).count, 3, "the same with an exact neighbour folds")
        // another species with the same name (a regional form): speciesId, not the name
        XCTAssertEqual(fold(line([row(2, cp: 9017, hp: 132, times: [1.6], fits: false, species: "charizard_other"), own([2.0, 2.4])])).count, 4)
        // both neighbours qualify: nothing is folded
        XCTAssertEqual(fold(line([row(2, cp: 2017, hp: 132, times: [1.0, 1.4], fits: true), row(3, cp: 9017, hp: 132, times: [2.0], fits: false), row(4, cp: 2017, hp: 132, times: [2.8, 3.2], fits: true)])).count, 5)
        XCTAssertEqual(fold(line([row(2, cp: 2017, hp: 132, times: [1.0, 1.4], fits: true), row(3, cp: 9017, hp: 132, times: [2.0], fits: false), row(4, cp: 2017, hp: 131, times: [2.8, 3.2], fits: true)])).count, 4, "one qualifying neighbour folds")
    }

    /// The limit on the gap to the neighbour's nearest reading: inside it folds, just over it refuses.
    func testTheGapLimitAtItsBoundary() {
        XCTAssertEqual(fold(line([row(2, cp: 9017, hp: 132, times: [1.2], fits: false), row(3, cp: 2017, hp: 132, times: [1.2 + ScanResultGap.inside, 3.2], fits: true)])).count, 3)
        XCTAssertEqual(fold(line([row(2, cp: 9017, hp: 132, times: [1.2], fits: false), row(3, cp: 2017, hp: 132, times: [1.2 + ScanResultGap.outside, 3.2], fits: true)])).count, 4)
    }

    /// Bars: with the fragment's bars read, at least two of the three stats equal the neighbour's. The five real folds all pass; the reviewer's twin (13/14/15 against 12/15/15) is not folded.
    func testTheBarsMustAgreeInAtLeastTwoStats() {
        let neighbour = IVs(atk: 12, def: 13, hp: 13)
        func folds(_ frag: IVs?) -> Bool { fold(line([row(2, cp: 9017, hp: 132, times: [1.6], fits: false, bars: frag), row(3, cp: 2017, hp: 132, times: [2.0, 2.4], fits: true, bars: neighbour)])).count == 3 }
        XCTAssertTrue(folds(neighbour), "all three equal (987, 982, 951)")
        XCTAssertTrue(folds(IVs(atk: 12, def: 13, hp: 10)), "run20's Charizard 9017: 12/13/10 against 12/13/13, two equal")
        XCTAssertTrue(folds(nil), "no bars read: the other conditions decide")
        XCTAssertFalse(folds(IVs(atk: 13, def: 14, hp: 13)), "one equal")
        let twin = fold(line([row(2, cp: 199, hp: 142, times: [1.4], fits: false, bars: IVs(atk: 13, def: 14, hp: 15)), row(3, cp: 1994, hp: 142, times: [2.0, 2.4], fits: true, bars: IVs(atk: 12, def: 15, hp: 15))]))
        XCTAssertEqual(twin.count, 4, "a real Staraptor 1995/142 read once as 199 beside 1994/142 is not folded (bars 13/14/15 against 12/15/15)")
    }

    /// A fold that a bars split undoes is kept by neither part.
    func testASplitKeepsNoFoldFlag() {
        var r = row(3, cp: 2017, hp: 132, times: [2.0], fits: true)
        r.flags = ["folded-digit-misread:9017", "folded-first-reading:632", "absorbed-fragment:2011", "cp-outlier-dropped:1910"]
        XCTAssertEqual(Refine.carriedFlagsForSplit(r), ["absorbed-fragment:2011", "cp-outlier-dropped:1910"])
    }

    // MARK: change 1

    private func saved(_ id: String, species: String, cp: Int, hp: Int, ivs: IVs) -> BoxEntry {
        let nf = GameMaster.nameAndForm(gm.byId[species]?.name ?? species)
        let r = ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: species, dex: gm.byId[species]?.dex, cp: cp, hp: hp, ivs: ivs, ivsRead: ivs, ivsGuess: nil, level: 20, levelMax: 20, dust: 0, solveStatus: "exact", flags: [], frames: [])
        return BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0))
    }
    private func misread(cp: Int, hp: Int, bars: IVs) -> ScanRow {
        ScanRow(index: 1, name: "Charizard", display: "Charizard", form: "", speciesId: "charizard", dex: 6, cp: cp, hp: hp, ivs: nil, ivsRead: bars, ivsGuess: nil, level: nil, levelMax: nil, dust: nil, solveStatus: "none", flags: ["no-level-fits"], frames: [])
    }
    private func family() -> [BoxEntry] {
        (0..<15).map { saved("c\($0)", species: "charizard", cp: 1000 + $0 * 61, hp: 100 + $0, ivs: IVs(atk: $0 % 16, def: 5, hp: 7)) } + (0..<20).map { saved("m\($0)", species: "charmander", cp: 300 + $0 * 17, hp: 40 + $0, ivs: IVs(atk: 3, def: $0 % 16, hp: 9)) }
    }

    private func solvedRow(_ species: String, cp: Int, hp: Int, bars: IVs) -> ScanRow {
        let nf = GameMaster.nameAndForm(gm.byId[species]?.name ?? species)
        return ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: species, dex: gm.byId[species]?.dex, cp: cp, hp: hp, ivs: bars, ivsRead: bars, ivsGuess: nil, level: 20, levelMax: 20, dust: 0, solveStatus: "exact", flags: [], frames: [])
    }
    private func apply(_ p: BoxMerge.Plan, _ res: [Int: BoxMerge.Resolution], _ box: [BoxEntry]) throws -> [BoxEntry] {
        try BoxMerge.apply(p, resolutions: res, keepGone: BoxMerge.keepSet(plan: p, resolutions: res, markedForRemoval: []), to: box)
    }

    /// The phone case: the scan holds BOTH the real Charizard 2017/132 row (paired as Same with the owner's entry) and the 9017 row (three readings: the fold does not fire). The owner has
    /// no other Charizard with HP 131-133, so the only same-species, same-HP entry is the one already paired: the question offers exactly it, first, marked as already seen.
    func testTheRun20QuestionOffersTheAlreadyPairedEntryAloneAndFirst() throws {
        let dev = NSString(string: "~/Developer/personal/pogo-frames/device-runs").expandingTildeInPath
        guard let csv = (try? FileManager.default.contentsOfDirectory(atPath: dev + "/run20-full-pause-stall-a8b519b"))?.first(where: { $0.hasSuffix(".csv") }).map({ URL(fileURLWithPath: dev + "/run20-full-pause-stall-a8b519b/" + $0) }) else { throw XCTSkip("run20 is not on this machine") }
        let box = try RoundTwentyOneTests.csvBox(csv, gm: gm, date: date(0), supply: [])
        let own = try XCTUnwrap(box.first { $0.row.speciesId == "charizard" && $0.row.cp == 2017 && $0.row.hp == 132 })
        let real = solvedRow("charizard", cp: 2017, hp: 132, bars: try XCTUnwrap(own.row.ivs))
        let p = BoxMerge.plan(scanned: [real, misread(cp: 9017, hp: 132, bars: IVs(atk: 12, def: 13, hp: 10))], into: box, kind: .partial, scanDate: date(5), gameMaster: gm)
        XCTAssertTrue(p.same.contains { $0.savedId == own.id }, "the real row is paired")
        let u = try XCTUnwrap(p.unsure.first { $0.scanned == 1 })
        XCTAssertEqual(u.candidates.first, own.id); XCTAssertEqual(p.rankedCounts[1], 1, "exactly one ranked candidate before 'Show all'")
        XCTAssertGreaterThan(u.candidates.count, 1, "the family follows, behind 'Show all'")
        // choosing the already-seen entry means a second read of that Pokémon: it changes nothing, exactly as leaving the row out does
        XCTAssertEqual(BoxMerge.effect(p, u, candidate: own, gameMaster: gm), .seenOnly)
        let chosen = try apply(p, [1: .existing(own.id)], box), left = try apply(p, [1: .leaveOut], box)
        XCTAssertEqual(chosen.map { $0.id }, left.map { $0.id }); XCTAssertEqual(chosen.map { $0.row }, left.map { $0.row })
    }

    /// Unpaired entries always come before paired ones, even when the paired one is digit-closer; each group is ranked the same way.
    func testUnpairedCandidatesComeBeforeAlreadyPairedOnes() {
        let box = [saved("paired", species: "charizard", cp: 2017, hp: 132, ivs: IVs(atk: 12, def: 13, hp: 13)), saved("free", species: "charizard", cp: 1500, hp: 132, ivs: IVs(atk: 0, def: 0, hp: 0))]
        let p = BoxMerge.plan(scanned: [solvedRow("charizard", cp: 2017, hp: 132, bars: IVs(atk: 12, def: 13, hp: 13)), misread(cp: 9017, hp: 132, bars: IVs(atk: 12, def: 13, hp: 13))], into: box, kind: .partial, scanDate: date(5), gameMaster: gm)
        let u = p.unsure.first { $0.scanned == 1 }
        XCTAssertEqual(Array((u?.candidates ?? []).prefix(2)), ["free", "paired"]); XCTAssertEqual(p.rankedCounts[1], 2)
    }

    /// Offering a ranked entry does not take it out of the pool: row 0 is asked about y (HP 131, its bars equal) and is offered z (HP 132, the exact HP) beside it; row 1, a part read of z,
    /// still matches z by itself. One question, not two.
    func testARankedExtraIsOnlyOfferedNotTakenFromTheOtherRows() {
        let box = [saved("z", species: "zapdos", cp: 1987, hp: 132, ivs: IVs(atk: 14, def: 11, hp: 15)), saved("y", species: "zapdos", cp: 1500, hp: 131, ivs: IVs(atk: 1, def: 2, hp: 3))]
        func zap(cp: Int, bars: IVs) -> ScanRow {
            var r = solvedRow("zapdos", cp: cp, hp: 132, bars: bars); r.ivs = nil; r.level = nil; r.levelMax = nil; r.solveStatus = "none"; r.flags = ["no-level-fits"]; return r
        }
        let p = BoxMerge.plan(scanned: [zap(cp: 1970, bars: IVs(atk: 1, def: 2, hp: 3)), zap(cp: 987, bars: IVs(atk: 14, def: 11, hp: 15))], into: box, kind: .partial, scanDate: date(5), gameMaster: gm)
        XCTAssertEqual(p.unsure.map { $0.scanned }, [0], "\(p.unsure.map { "\($0.scanned) \($0.kind) \($0.candidates)" })")
        XCTAssertEqual(p.unsure.first?.candidates.first, "z", "z is offered first (the exact HP)")
        XCTAssertEqual(p.partMatches.map { $0.scanned }, [1])
    }

    /// With no entry of the exact HP, entries one point off are ranked (a misread HP).
    func testOneHPOffIsRankedOnlyWhenNoEntryHasTheExactHP() {
        let off = saved("off", species: "charizard", cp: 2017, hp: 131, ivs: IVs(atk: 12, def: 13, hp: 13))
        let p = BoxMerge.plan(scanned: [misread(cp: 9017, hp: 132, bars: IVs(atk: 12, def: 13, hp: 10))], into: family() + [off], kind: .partial, scanDate: date(5), gameMaster: gm)
        XCTAssertEqual(p.unsure[0].candidates.first, "off"); XCTAssertEqual(p.rankedCounts[0], 1)
        let exact = saved("exact", species: "charizard", cp: 1400, hp: 132, ivs: IVs(atk: 1, def: 1, hp: 1))
        let q = BoxMerge.plan(scanned: [misread(cp: 9017, hp: 132, bars: IVs(atk: 12, def: 13, hp: 10))], into: family() + [off, exact], kind: .partial, scanDate: date(5), gameMaster: gm)
        XCTAssertEqual(q.unsure[0].candidates.first, "exact"); XCTAssertEqual(q.rankedCounts[0], 1, "the one-point-off entry is not ranked beside an exact one")
    }

    func testRankingByCPDigitsThenBars() {
        let read = IVs(atk: 12, def: 13, hp: 10)
        let box = family() + [
            saved("far-bars-near-cp", species: "charizard", cp: 2017, hp: 132, ivs: IVs(atk: 0, def: 0, hp: 0)),      // one digit apart, bars far
            saved("near-bars-other-cp", species: "charizard", cp: 1500, hp: 132, ivs: IVs(atk: 12, def: 13, hp: 10)),   // not a digit apart, bars equal
            saved("mid-bars-near-cp", species: "charizard", cp: 9617, hp: 132, ivs: IVs(atk: 12, def: 13, hp: 12)),    // two digits? 9617 vs 9017: one digit apart, bars close
        ]
        let p = BoxMerge.plan(scanned: [misread(cp: 9017, hp: 132, bars: read)], into: box, kind: .partial, scanDate: date(5), gameMaster: gm)
        XCTAssertEqual(Array(p.unsure[0].candidates.prefix(3)), ["mid-bars-near-cp", "far-bars-near-cp", "near-bars-other-cp"], "digits first, then bars")
        XCTAssertEqual(p.rankedCounts[0], 3)
    }

    func testFallbackToTodaysListWhenNoSameHPEntryExists() {
        let p = BoxMerge.plan(scanned: [misread(cp: 9017, hp: 132, bars: IVs(atk: 12, def: 13, hp: 10))], into: family(), kind: .partial, scanDate: date(5), gameMaster: gm)
        XCTAssertNil(p.rankedCounts[0]); XCTAssertEqual(p.unsure.first?.kind, .ambiguous)
    }

    /// run15 against the owner's box after run20 (needs the device logs; skipped elsewhere): the questions that remain and what each offers.
    /// run20's own scan against the owner's box: the questions that remain and the size of each list (printed for the report; the three misread rows are folded, so none is expected).
    func testRun20AgainstTheOwnersBoxAsksNothingAboutTheFoldedRows() throws {
        let dev = NSString(string: "~/Developer/personal/pogo-frames/device-runs").expandingTildeInPath
        let dir = dev + "/run20-full-pause-stall-a8b519b"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir), let log = names.first(where: { $0.hasSuffix(".replay.jsonl") }), let csv = names.first(where: { $0.hasSuffix(".csv") }) else { throw XCTSkip("run20 is not on this machine") }
        let rows = try ScanPipeline.process(replay: URL(fileURLWithPath: dir + "/" + log), engine: sharedEngine, paging: hint).scan.rows
        let box = try RoundTwentyOneTests.csvBox(URL(fileURLWithPath: dir + "/" + csv), gm: gm, date: date(0), supply: [rows])
        let p = BoxMerge.plan(scanned: rows, into: box, kind: .partial, scanDate: date(5), gameMaster: gm)
        print("R20 OWNER BOX \(box.count): rows \(rows.count) same \(p.same.count) updated \(p.updated.count) unsure \(p.unsure.count) new \(p.new.count) \(p.unsure.map { "\(rows[$0.scanned].display) \(rows[$0.scanned].cp) \($0.kind) candidates \($0.candidates.count) ranked \(p.rankedCounts[$0.scanned] ?? 0)" })")
        XCTAssertFalse(p.unsure.contains { rows[$0.scanned].flags.contains("no-level-fits") && ($0.kind == .ambiguous) && $0.candidates.count > 20 }, "no question offers the whole family")
    }

    func testRun15AgainstTheOwnersCurrentBox() throws {
        let dev = NSString(string: "~/Developer/personal/pogo-frames/device-runs").expandingTildeInPath
        func file(_ dir: String, _ suffix: String) -> URL? {
            (try? FileManager.default.contentsOfDirectory(atPath: dev + "/" + dir))?.filter { $0.hasSuffix(suffix) }.sorted().first.map { URL(fileURLWithPath: dev + "/" + dir + "/" + $0) }
        }
        guard let r15 = file("run15-full-2000-scan-20261003T101008Z-84391adc", ".replay.jsonl"), let r12 = file("run12-tap-1500", ".replay.jsonl"), let csv = file("run20-full-pause-stall-a8b519b", ".csv") else { throw XCTSkip("device runs not on this machine") }
        let rows15 = try ScanPipeline.process(replay: r15, engine: sharedEngine, paging: hint).scan.rows
        let rows12 = try ScanPipeline.process(replay: r12, engine: sharedEngine, paging: hint).scan.rows
        let box = try RoundTwentyOneTests.csvBox(csv, gm: gm, date: date(0), supply: [rows12, rows15])
        let p = BoxMerge.plan(scanned: rows15, into: box, kind: .full, scanDate: date(5), gameMaster: gm)
        print("R15 CURRENT BOX \(box.count): same \(p.same.count) updated \(p.updated.count) unsure \(p.unsure.count) new \(p.new.count) gone \(p.gone.count) \(p.unsure.map { "\(rows15[$0.scanned].display) \(rows15[$0.scanned].cp) \($0.kind) candidates \($0.candidates.count) ranked \(p.rankedCounts[$0.scanned] ?? 0)" })")
    }
}

private enum ScanResultGap { static let inside = 0.84, outside = 0.86 }

private extension ScanRow {
    func with(name: String) -> ScanRow { var r = self; r.name = name; r.display = name; r.speciesId = name.lowercased(); return r }
}
