import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// Round 29: the folds of round 28 compare the screen name, not the solved species (multi-form species), the fallback gap has its slack back, the digit rule needs the bars read,
/// a row whose only same-species, same-HP entry is already paired is asked about it, and a bars split drops the fold flag.
final class RoundTwentyNineTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private func date(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(d) * 86_400) }
    private let bars = IVs(atk: 12, def: 13, hp: 14)

    // MARK: A, the real engine

    /// Two screen names that map to more than one species id DO hold a regional form, so display equality folds across it (as round 27's `name` did): "Darmanitan" holds the Galarian Zen form
    /// (the Galarian standard form has its own name, "Galarian Darmanitan"), and "Tauros" holds the three Paldean breeds, which the table names Aqua, Blaze and Combat (no regional word in the name,
    /// so those three are listed by hand). Every other shared screen name is a form without a regional prefix. A regional form of any other species has its own name ("Alolan Raichu").
    func testExactlyDarmanitanAndTaurosShareAScreenNameWithARegionalForm() throws {
        let table = try SpeciesTable.bundled()
        let regionalWords = ["alolan", "galarian", "hisuian", "paldean"]
        let paldeanBreeds: Set<String> = ["tauros_aqua", "tauros_blaze", "tauros_combat"]
        var multi = 0
        var holding = [String: [String]]()
        for c in displayNames(table) where c.speciesIds.count > 1 {
            multi += 1
            let regional = c.speciesIds.filter { id in regionalWords.contains { id.contains($0) } || paldeanBreeds.contains(id) }
            if !regional.isEmpty { holding[c.display] = regional.sorted() }
        }
        XCTAssertEqual(multi, 52)
        XCTAssertEqual(holding, ["Darmanitan": ["darmanitan_galarian_zen"], "Tauros": ["tauros_aqua", "tauros_blaze", "tauros_combat"]])
        let ids = Dictionary(uniqueKeysWithValues: displayNames(table).map { ($0.display, $0.speciesIds) })
        XCTAssertNotNil(ids["Alolan Raichu"]); XCTAssertEqual(ids["Raichu"], ["raichu"])
        XCTAssertEqual(ids["Galarian Darmanitan"], ["darmanitan_galarian_standard"])
        XCTAssertEqual(Set(try XCTUnwrap(ids["Darmanitan"])), ["darmanitan_galarian_zen", "darmanitan_standard", "darmanitan_zen"])
        XCTAssertEqual(Set(try XCTUnwrap(ids["Tauros"])), paldeanBreeds.union(["tauros"]))
    }

    private func card(_ ids: [String: [String]], _ name: String, cp: Int?, hp: Int, ivs: IVs?, t: Double) -> FrameReading {
        var f = FrameReading(frame: "f\(Int(t * 100))", time: t); f.name = name; f.baseName = name; f.form = ""; f.speciesIds = ids[name]
        f.cp = cp; f.cpText = cp.map(String.init) ?? ""
        f.hp = HP(current: hp, max: hp); f.ivs = ivs; f.ivConfidence = 0.9; f.nameConfidence = 1; f.sharpness = 1; f.nameText = name; return f
    }

    private struct Case { let name: String; let cp: Int; let hp: Int; let part: Int; let digit: Int }
    private let cases = [Case(name: "Morpeko", cp: 1353, hp: 110, part: 353, digit: 9353), Case(name: "Giratina", cp: 2581, hp: 199, part: 581, digit: 9581)]

    /// The fragment first (`fragmentTimes`), then the card's three readings from 2.0 s. A gap reading with no CP stands where the digit-misread variant has a missing reading.
    private func run(_ c: Case, fragmentCp: Int, fragmentBars: IVs?, fragmentTime: Double) throws -> (base: ScanResult, refined: Refine.Refined) {
        let ids = Dictionary(uniqueKeysWithValues: displayNames(try SpeciesTable.bundled()).map { ($0.display, $0.speciesIds) })
        var rs = [card(ids, c.name, cp: fragmentCp, hp: c.hp, ivs: fragmentBars, t: fragmentTime)]
        if fragmentTime < 1.5 { rs.append(card(ids, c.name, cp: nil, hp: c.hp, ivs: nil, t: 1.6)) }
        rs += [2.0, 2.4, 2.8].map { card(ids, c.name, cp: c.cp, hp: c.hp, ivs: bars, t: $0) }
        let base = try sharedEngine.finish(readings: rs)
        return (base, try Refine.apply(to: base, readings: rs, ticks: [], engine: sharedEngine))
    }

    private func merged(_ base: ScanResult, _ refined: Refine.Refined, kind: BoxStore.Kind) throws -> BoxMerge.Plan {
        // the owner's entry is the card as it was solved (the exact row), whatever the fragment became
        let neighbour = try XCTUnwrap(base.rows.last)
        let box = [BoxEntry(id: "own", row: neighbour, firstSeen: date(0), lastSeen: date(0))]
        return BoxMerge.plan(scanned: refined.scan.rows, into: box, kind: kind, scanDate: date(1), gameMaster: gm)
    }

    /// A sliding-in part read (353 of 1353, 0.4 s before its card, bars still animating) of a multi-form species folds although the row that fits no level carries the FIRST form its name could be.
    func testASlidingInPartReadOfAMultiFormSpeciesIsFolded() throws {
        for c in cases {
            let r = try run(c, fragmentCp: c.part, fragmentBars: IVs(atk: 1, def: 2, hp: 3), fragmentTime: 1.6)
            XCTAssertEqual(r.base.rows.count, 2, c.name)
            XCTAssertNotEqual(r.base.rows[0].speciesId, r.base.rows[1].speciesId, "\(c.name): the scenario needs the two rows to carry different forms")
            XCTAssertEqual(r.refined.scan.rows.count, 1, "\(c.name): \(r.refined.scan.rows.map { "\($0.speciesId) \($0.cp) \($0.flags)" })")
            XCTAssertTrue(r.refined.scan.rows[0].flags.contains("folded-first-reading:\(c.part)"), "\(c.name): by the sliding-in rule, not the digit rule (its bars differ)")
            for kind in [BoxStore.Kind.full, .partial] {
                let p = try merged(r.base, r.refined, kind: kind)
                XCTAssertTrue(p.new.isEmpty && p.unsure.isEmpty, "\(c.name) \(kind): no phantom entry"); XCTAssertEqual(p.same.count, 1)
            }
        }
    }

    /// A one-digit misread (9353 for 1353, 0.8 s before: outside the older rule's 0.42 s) with two bars equal folds by the digit rule.
    func testADigitMisreadOfAMultiFormSpeciesIsFolded() throws {
        for c in cases {
            let r = try run(c, fragmentCp: c.digit, fragmentBars: IVs(atk: 12, def: 13, hp: 10), fragmentTime: 1.2)
            XCTAssertEqual(r.base.rows.count, 2, c.name)
            XCTAssertNotEqual(r.base.rows[0].speciesId, r.base.rows[1].speciesId, "\(c.name): the scenario needs the two rows to carry different forms")
            XCTAssertEqual(r.refined.scan.rows.count, 1, "\(c.name): \(r.refined.scan.rows.map { "\($0.speciesId) \($0.cp) \($0.flags)" })")
            XCTAssertTrue(r.refined.scan.rows[0].flags.contains("folded-digit-misread:\(c.digit)"), c.name)
            for kind in [BoxStore.Kind.full, .partial] {
                let p = try merged(r.base, r.refined, kind: kind)
                XCTAssertTrue(p.new.isEmpty && p.unsure.isEmpty, "\(c.name) \(kind): no phantom entry"); XCTAssertEqual(p.same.count, 1)
            }
        }
    }

    // MARK: A, a regional form is never folded into another form

    private func fr(_ t: Double, cp: Int, name: String) -> FrameLabel {
        FrameLabel(frame: "f\(Int(t * 1000))", time: t, cp: cp, cpText: String(cp), name: name, hp: "100/100", ivs: "12/13/13", ivConfidence: 0.9, sharpness: 1, clip: nil)
    }
    private func row(_ i: Int, display: String, species: String, cp: Int, times: [Double], fits: Bool, bars: IVs? = IVs(atk: 12, def: 13, hp: 13)) -> ScanRow {
        ScanRow(index: i, name: "Raichu", display: display, form: "", speciesId: species, dex: 26, cp: cp, hp: 100, ivs: fits ? bars : nil, ivsRead: bars, ivsGuess: nil, level: fits ? 20 : nil, levelMax: fits ? 20 : nil,
                dust: 0, solveStatus: fits ? "exact" : "none", flags: fits ? [] : ["no-level-fits"], frames: times.map { fr($0, cp: cp, name: display) })
    }
    private func fold(_ rows: [ScanRow]) -> [ScanRow] { Refine.absorbFragments(ScanResult(rows: rows, review: [], unmatched: [])).scan.rows }
    private func far(_ i: Int, _ t: Double) -> ScanRow { row(i, display: "Pidgey", species: "pidgey", cp: 500, times: [t, t + 0.4, t + 0.8], fits: true) }

    func testARegionalFormNeverFoldsIntoTheOtherForm() {
        // the same Pokémon (the same screen name): folded by each rule
        let sliding = fold([far(1, 0), row(2, display: "Raichu", species: "raichu", cp: 632, times: [5.0], fits: false, bars: IVs(atk: 1, def: 2, hp: 3)), row(3, display: "Raichu", species: "raichu", cp: 1632, times: [5.4, 5.8, 6.2], fits: true), far(9, 20)])
        XCTAssertEqual(sliding.count, 3, "control: the sliding-in rule folds the same name")
        let digit = fold([far(1, 0), row(2, display: "Raichu", species: "raichu", cp: 9017, times: [5.0], fits: false), row(3, display: "Raichu", species: "raichu", cp: 2017, times: [5.8, 6.2], fits: true), far(9, 20)])
        XCTAssertEqual(digit.count, 3, "control: the digit rule folds the same name")
        // another form under another screen name: neither rule folds it
        let slidingOther = fold([far(1, 0), row(2, display: "Raichu", species: "raichu", cp: 632, times: [5.0], fits: false, bars: IVs(atk: 1, def: 2, hp: 3)), row(3, display: "Alolan Raichu", species: "raichu_alolan", cp: 1632, times: [5.4, 5.8, 6.2], fits: true), far(9, 20)])
        XCTAssertEqual(slidingOther.count, 4)
        let digitOther = fold([far(1, 0), row(2, display: "Raichu", species: "raichu", cp: 9017, times: [5.0], fits: false), row(3, display: "Alolan Raichu", species: "raichu_alolan", cp: 2017, times: [5.8, 6.2], fits: true), far(9, 20)])
        XCTAssertEqual(digitOther.count, 4)
    }

    // MARK: B, the fallback slack

    /// The device's normal reading step is 0.400036 s: a first-row sliding-in part read (no beat before it) 0.400036 s before its card, bars animating, is folded.
    func testAFirstRowSlidingInPartReadOneReadingStepBeforeItsCardIsFolded() {
        let step = 0.400036
        let out = fold([row(1, display: "Charizard", species: "charizard", cp: 632, times: [10.0], fits: false, bars: IVs(atk: 1, def: 2, hp: 3)),
                        row(2, display: "Charizard", species: "charizard", cp: 1632, times: [10 + step, 10 + 2 * step, 10 + 3 * step], fits: true),
                        far(3, 20)])
        XCTAssertEqual(out.count, 2, "\(out.map { "\($0.cp) \($0.flags)" })")
        XCTAssertTrue(out[0].flags.contains("folded-first-reading:632"))
        XCTAssertEqual(Refine.fragmentFallbackSlackSeconds, 0.02)
    }

    // MARK: C, the digit rule needs the bars read

    func testAFragmentWhoseBarsWereNotReadIsNotFoldedByTheDigitRule() {
        func digit(_ bars: IVs?) -> Int {
            // 0.8 s before its card: outside the sliding-in rule's reach, so only the digit rule can fold it
            fold([far(1, 0), row(2, display: "Charizard", species: "charizard", cp: 9017, times: [5.0], fits: false, bars: bars), row(3, display: "Charizard", species: "charizard", cp: 2017, times: [5.8, 6.2], fits: true), far(9, 20)]).count
        }
        XCTAssertEqual(digit(IVs(atk: 12, def: 13, hp: 10)), 3, "control: bars read, two equal")
        XCTAssertEqual(digit(nil), 4, "bars not read: it stays a row")
        // stated limit: within one reading step of its card the OLDER rules still fold it (barsCompatible is true for unread bars), with their own flag
        let near = fold([far(1, 0), row(2, display: "Charizard", species: "charizard", cp: 9017, times: [5.4], fits: false, bars: nil), row(3, display: "Charizard", species: "charizard", cp: 2017, times: [5.8, 6.2], fits: true), far(9, 20)])
        XCTAssertEqual(near.count, 3); XCTAssertTrue(near.first { $0.cp == 2017 }?.flags.contains("absorbed-other-cp:9017") == true)
    }

    // MARK: D, a row asked about the only entry already paired in this scan

    private func entry(_ id: String, species: String, cp: Int, hp: Int, ivs: IVs) -> BoxEntry {
        let nf = GameMaster.nameAndForm(gm.byId[species]?.name ?? species)
        let r = ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: species, dex: gm.byId[species]?.dex, cp: cp, hp: hp, ivs: ivs, ivsRead: ivs, ivsGuess: nil, level: 20, levelMax: 20, dust: 0, solveStatus: "exact", flags: [], frames: [])
        return BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0))
    }
    private func scannedRow(cp: Int, hp: Int, bars: IVs, fits: Bool) -> ScanRow {
        ScanRow(index: 1, name: "Charizard", display: "Charizard", form: "", speciesId: "charizard", dex: 6, cp: cp, hp: hp, ivs: fits ? bars : nil, ivsRead: bars, ivsGuess: nil, level: fits ? 20 : nil, levelMax: fits ? 20 : nil,
                dust: fits ? 0 : nil, solveStatus: fits ? "exact" : "none", flags: fits ? [] : ["no-level-fits"], frames: [])
    }

    func testARowWhoseOnlySameHPEntryIsAlreadyPairedIsAskedNotNew() throws {
        let own = entry("own", species: "charizard", cp: 2017, hp: 132, ivs: IVs(atk: 12, def: 13, hp: 13))
        let box = [own, entry("other", species: "charmander", cp: 300, hp: 40, ivs: IVs(atk: 3, def: 4, hp: 5))]
        let p = BoxMerge.plan(scanned: [scannedRow(cp: 2017, hp: 132, bars: IVs(atk: 12, def: 13, hp: 13), fits: true), scannedRow(cp: 9017, hp: 132, bars: IVs(atk: 1, def: 2, hp: 3), fits: false)], into: box, kind: .partial, scanDate: date(5), gameMaster: gm)
        XCTAssertTrue(p.same.contains { $0.scanned == 0 && $0.savedId == "own" }, "the exact row is paired")
        XCTAssertTrue(p.new.isEmpty, "not a phantom New entry: \(p.new)")
        let u = try XCTUnwrap(p.unsure.first { $0.scanned == 1 })
        XCTAssertEqual(u.candidates, ["own"]); XCTAssertEqual(p.rankedCounts[1], 1)
        XCTAssertEqual(BoxMerge.effect(p, u, candidate: own, gameMaster: gm), .seenOnly, "offered as already seen")
        let res: [Int: BoxMerge.Resolution] = [1: .existing("own")]
        let after = try BoxMerge.apply(p, resolutions: res, keepGone: BoxMerge.keepSet(plan: p, resolutions: res, markedForRemoval: []), to: box)
        let left: [Int: BoxMerge.Resolution] = [1: .leaveOut]
        let untouched = try BoxMerge.apply(p, resolutions: left, keepGone: BoxMerge.keepSet(plan: p, resolutions: left, markedForRemoval: []), to: box)
        XCTAssertEqual(after.map { $0.id }, box.map { $0.id }); XCTAssertEqual(after.map { $0.row }, box.map { $0.row }, "the box is unchanged")
        XCTAssertEqual(after.map { $0.lastSeen }, untouched.map { $0.lastSeen })
        // "It is new" stays available
        let asNew: [Int: BoxMerge.Resolution] = [1: .new]
        XCTAssertEqual(try BoxMerge.apply(p, resolutions: asNew, keepGone: BoxMerge.keepSet(plan: p, resolutions: asNew, markedForRemoval: []), to: box).count, 3)
    }

    // MARK: E, a bars split drops the fold flags (through the call site)

    func testABarsSplitDropsTheFoldFlagFromBothPartsAndKeepsTheOthers() throws {
        let l = try ReplayReadings.load(url: Fixture.url("device-run8-fidough-stretch.replay.jsonl"))
        var scan = try sharedEngine.finish(readings: l.readings)
        let k = try XCTUnwrap(scan.rows.firstIndex { $0.display == "Fidough" && $0.cp == 768 })
        scan.rows[k].flags += ["folded-first-reading:68", "folded-digit-misread:9768", "absorbed-fragment:700"]
        let split = try Refine.splitByBars(scan, readings: l.readings, engine: sharedEngine, hintPeriod: nil)
        let parts = split.scan.rows.filter { $0.display == "Fidough" && $0.cp == 768 }
        XCTAssertEqual(parts.count, 2, "the row is split")
        for p in parts {
            XCTAssertTrue(p.flags.contains("split-by-bars"))
            XCTAssertTrue(p.flags.contains("absorbed-fragment:700"), "other carried flags stay: \(p.flags)")
            XCTAssertFalse(p.flags.contains { $0.hasPrefix("folded-") }, "the fold warning is dropped from both parts: \(p.flags)")
        }
    }
}
