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
        XCTAssertEqual(ch.map { $0.cp }, [2017]); XCTAssertTrue(ch.first?.flags.contains("folded-first-reading:9017") == true)
        XCTAssertEqual(out.filter { $0.display == "Staraptor" && $0.hp == 141 && $0.cp == 1987 }.count, 1)
        XCTAssertTrue(out.first { $0.display == "Staraptor" && $0.cp == 1987 }?.flags.contains { $0.hasSuffix(":987") } == true, "folded in (a note when the beat is regular, a check by the digit rule on the whole log)")
        let s140 = out.first { $0.display == "Staraptor" && $0.hp == 140 && $0.cp == 1982 }
        XCTAssertTrue(s140?.flags.contains("folded-first-reading:982") == true, "the two-reading row (82, 982) votes 982: one digit missing from 1982")
        XCTAssertTrue(out.contains { $0.display == "Staraptor" && $0.hp == 142 && $0.cp == 1982 }, "the neighbour with another HP is its own Pokémon")
        XCTAssertEqual(FlagInfo.severity(of: "folded-first-reading:982", solveStatus: "exact"), .check)
    }

    // MARK: change 2, the rule

    private func fr(_ t: Double, cp: Int, hp: Int) -> FrameLabel {
        FrameLabel(frame: "f\(Int(t * 100))", time: t, cp: cp, cpText: String(cp), name: "Charizard", hp: "\(hp)/\(hp)", ivs: "12/13/13", ivConfidence: 0.9, sharpness: 1, clip: nil)
    }
    private func row(_ i: Int, cp: Int, hp: Int, times: [Double], fits: Bool, exact: Bool = true) -> ScanRow {
        let bars = IVs(atk: 12, def: 13, hp: 13)
        return ScanRow(index: i, name: "Charizard", display: "Charizard", form: "", speciesId: "charizard", dex: 6, cp: cp, hp: hp, ivs: fits ? bars : nil, ivsRead: bars, ivsGuess: nil, level: fits ? 20 : nil, levelMax: fits ? 20 : nil,
                       dust: 0, solveStatus: fits && exact ? "exact" : "none", flags: fits ? [] : ["no-level-fits"], frames: times.map { fr($0, cp: cp, hp: hp) })
    }
    private func fold(_ rows: [ScanRow]) -> [ScanRow] { Refine.absorbFragments(ScanResult(rows: rows, review: [], unmatched: [])).scan.rows }
    private func line(_ frag: ScanRow, _ n: ScanRow) -> [ScanRow] {
        let pre = row(1, cp: 1500, hp: 90, times: [0, 0.4, 0.8], fits: true).with(name: "Pidgey"), post = row(4, cp: 1400, hp: 91, times: [10, 10.4, 10.8], fits: true).with(name: "Rattata")
        return [pre, frag, n, post]
    }

    func testOneDigitMisreadsOfEveryKindFoldButARealPokemonNeverDoes() {
        let own = row(3, cp: 2017, hp: 132, times: [2.4, 2.8], fits: true)
        for (cp, label) in [(9017, "one digit changed"), (217, "one missing"), (20177, "one extra")] {
            let frag = row(2, cp: cp, hp: 132, times: [1.6], fits: false)
            XCTAssertEqual(fold(line(frag, own)).count, 3, label)
        }
        // a row that FITS a level is a real Pokémon, however close its CP: never folded
        XCTAssertEqual(fold(line(row(2, cp: 2018, hp: 132, times: [1.6], fits: true), own)).count, 4)
        // two digits off, another HP, three readings, an unsolved neighbour, a gap of a beat: not folded
        XCTAssertEqual(fold(line(row(2, cp: 9917, hp: 132, times: [1.6], fits: false), own)).count, 4)
        XCTAssertEqual(fold(line(row(2, cp: 9017, hp: 131, times: [1.6], fits: false), own)).count, 4)
        XCTAssertEqual(fold(line(row(2, cp: 9017, hp: 132, times: [1.6, 2.0, 2.4], fits: false), row(3, cp: 2017, hp: 132, times: [2.8, 3.2], fits: true))).count, 4)
        XCTAssertEqual(fold(line(row(2, cp: 9017, hp: 132, times: [1.6], fits: false), row(3, cp: 2017, hp: 132, times: [2.8], fits: true, exact: false))).count, 4)
        XCTAssertEqual(fold(line(row(2, cp: 9017, hp: 132, times: [0.8 + 0.0], fits: false), row(3, cp: 2017, hp: 132, times: [2.8, 3.2], fits: true))).count, 4, "1.6 s between their readings is a paging boundary")
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

    func testTheRun20CharizardIsOfferedItsOwnEntryFirstAndAloneBeforeShowAll() {
        let box = family() + [saved("own", species: "charizard", cp: 2017, hp: 132, ivs: IVs(atk: 12, def: 13, hp: 13))]
        let p = BoxMerge.plan(scanned: [misread(cp: 9017, hp: 132, bars: IVs(atk: 12, def: 13, hp: 10))], into: box, kind: .partial, scanDate: date(5), gameMaster: gm)
        XCTAssertEqual(p.unsure.count, 1)
        XCTAssertEqual(p.unsure[0].candidates.first, "own"); XCTAssertEqual(p.rankedCounts[0], 1, "exactly one ranked candidate is shown before 'Show all'")
        XCTAssertGreaterThan(p.unsure[0].candidates.count, 1, "the family follows, behind 'Show all'")
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

private extension ScanRow {
    func with(name: String) -> ScanRow { var r = self; r.name = name; r.display = name; r.speciesId = name.lowercased(); return r }
}
