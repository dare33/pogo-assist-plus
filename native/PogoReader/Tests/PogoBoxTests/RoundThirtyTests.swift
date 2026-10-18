import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// Round 30: an untrusted row (it fits no level) matches saved entries by its screen name, a ranked head with ONE entry already paired is asked about, a Nidoran whose symbol was read
/// is never folded into the other sex, and the already-paired question is exercised through a full scan.
final class RoundThirtyTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private func date(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(d) * 86_400) }
    private let ownBars = IVs(atk: 12, def: 13, hp: 13)

    // MARK: 1, an untrusted row matches by screen name

    /// A fragment with NO bars read, 0.8 s before its card (outside the older rules' 0.42 s and the digit rule, which needs the bars read), fits no level and carries the first form its name could be;
    /// the owner's entry has the form the solver chose for the card. Before round 30 it found no candidate and was added as a phantom entry. (Built as rows: the grouper itself joins a
    /// fragment with no bars to its card when both are read, so this is the case where the two rows were kept apart.)
    func testAnUnfoldedFragmentOfAMultiFormSpeciesIsAskedAboutTheOwnersEntry() throws {
        for (name, solved, first, cp, hp, digit) in forms {
            var frag = scanned(species: first, display: name, cp: digit, hp: hp, fits: false, times: [5.0]); frag.ivsRead = nil
            let card = scanned(species: solved, display: name, cp: cp, hp: hp, fits: true, times: [5.8, 6.2])
            let rows = fold([far(1, 0), frag, card, far(9, 20)])
            XCTAssertEqual(rows.count, 4, "\(name): not folded: \(rows.map { "\($0.cp) \($0.flags)" })")
            let box = [BoxEntry(id: "own", row: card, firstSeen: date(0), lastSeen: date(0))]
            for kind in [BoxStore.Kind.full, .partial] {
                let p = BoxMerge.plan(scanned: rows, into: box, kind: kind, scanDate: date(1), gameMaster: gm)
                let fi = try XCTUnwrap(rows.firstIndex { $0.cp == digit })
                XCTAssertFalse(p.new.contains(fi), "\(name) \(kind): no phantom entry: \(p.new)")
                XCTAssertEqual(p.same.map { $0.savedId }, ["own"])
                let u = try XCTUnwrap(p.unsure.first { $0.scanned == fi }, "\(name) \(kind)")
                XCTAssertEqual(u.candidates, ["own"]); XCTAssertEqual(u.kind, .ambiguous)
                XCTAssertEqual(BoxMerge.goneReport(p, resolutions: [fi: .existing("own")]).gone, [])
            }
        }
    }

    /// A row that SOLVED (a trusted species id) still matches only its own form: a saved entry of the other form is no candidate.
    func testATrustedRowStillMatchesOnlyItsOwnForm() throws {
        let hangry = entry("hangry", species: "morpeko_hangry", cp: 1353, hp: 110)
        var full = scanned(species: "morpeko_full_belly", display: "Morpeko", cp: 9353, hp: 110, fits: true)   // solved, so its id is the solver's choice
        full.flags = []
        let p = BoxMerge.plan(scanned: [full], into: [hangry], kind: .partial, scanDate: date(1), gameMaster: gm)
        XCTAssertEqual(p.new, [0]); XCTAssertTrue(p.unsure.isEmpty)
        // the same row flagged as fitting no level is asked about the entry
        // a trusted row with no IVs and a part-read CP (the solver chose its form; no `no-level-fits` flag) is no part read of the other form's entry either
        var trustedPart = scanned(species: "morpeko_full_belly", display: "Morpeko", cp: 353, hp: 110, fits: false); trustedPart.flags = []; trustedPart.solveStatus = "unknown-ivs"
        let t = BoxMerge.plan(scanned: [trustedPart], into: [hangry], kind: .partial, scanDate: date(1), gameMaster: gm)
        XCTAssertEqual(t.new, [0]); XCTAssertTrue(t.unsure.isEmpty)
        let untrusted = scanned(species: "morpeko_full_belly", display: "Morpeko", cp: 9353, hp: 110, fits: false)
        let q = BoxMerge.plan(scanned: [untrusted], into: [hangry], kind: .partial, scanDate: date(1), gameMaster: gm)
        XCTAssertTrue(q.new.isEmpty); XCTAssertEqual(q.unsure.first?.candidates, ["hangry"])
        // another screen name is never a candidate, whatever the row
        let other = scanned(species: "charizard", display: "Charizard", cp: 9353, hp: 110, fits: false)
        XCTAssertEqual(BoxMerge.plan(scanned: [other], into: [hangry], kind: .partial, scanDate: date(1), gameMaster: gm).new, [0])
    }

    /// A part read (the CP's digits are a run of the entry's) of a multi-form species: the same, through `partialCandidates`.
    func testAPartReadOfAMultiFormSpeciesIsAskedAboutTheOwnersEntry() throws {
        let hangry = entry("hangry", species: "morpeko_hangry", cp: 1353, hp: 110)
        let part = scanned(species: "morpeko_full_belly", display: "Morpeko", cp: 353, hp: 110, fits: false)
        let p = BoxMerge.plan(scanned: [part], into: [hangry], kind: .partial, scanDate: date(1), gameMaster: gm)
        XCTAssertTrue(p.new.isEmpty, "\(p.new)")
        // Round 31: the entry is of another form id, so the automatic part match (strict species test) never pairs it: it is asked as a partial read.
        XCTAssertTrue(p.same.isEmpty && p.partMatches.isEmpty, "\(p.same) \(p.partMatches)")
        let u = try XCTUnwrap(p.unsure.first)
        XCTAssertEqual(u.kind, .partialRead); XCTAssertEqual(u.candidates, ["hangry"])
    }

    private let forms = [("Morpeko", "morpeko_hangry", "morpeko_full_belly", 1353, 110, 9353), ("Giratina", "giratina_origin", "giratina_altered", 2581, 199, 9581)]

    /// The combination the reviewers named, BUILT AS ScanRows (not through the engine): the owner's entry (the card's form id) is ALREADY PAIRED to its exact card in this scan, and a no-bars
    /// no-level-fit row of the other form id is the only other row: a question offering that entry as already seen, never a phantom New entry.
    func testAnUntrustedRowWhoseOnlyEntryIsAlreadyPairedToItsCardIsAsked() throws {
        for (name, solved, first, cp, hp, digit) in forms {
            let card = scanned(species: solved, display: name, cp: cp, hp: hp, fits: true)
            var frag = scanned(species: first, display: name, cp: digit, hp: hp, fits: false); frag.ivsRead = nil
            XCTAssertNotEqual(card.speciesId, frag.speciesId)
            let box = [BoxEntry(id: "own", row: card, firstSeen: date(0), lastSeen: date(0))]
            for kind in [BoxStore.Kind.full, .partial] {
                let p = BoxMerge.plan(scanned: [card, frag], into: box, kind: kind, scanDate: date(1), gameMaster: gm)
                XCTAssertEqual(p.new, [], "\(name) \(kind)")
                XCTAssertEqual(p.same.map { $0.savedId }, ["own"])
                let u = try XCTUnwrap(p.unsure.first { $0.scanned == 1 })
                XCTAssertEqual(u.candidates, ["own"]); XCTAssertEqual(u.kind, .ambiguous); XCTAssertEqual(p.rankedCounts[1], 1)
                XCTAssertEqual(BoxMerge.effect(p, u, candidate: box[0], gameMaster: gm), .seenOnly)
                let r: [Int: BoxMerge.Resolution] = [1: .existing("own")]
                let after = try BoxMerge.apply(p, resolutions: r, keepGone: BoxMerge.keepSet(plan: p, resolutions: r, markedForRemoval: []), to: box)
                XCTAssertEqual(after.map { $0.row }, box.map { $0.row }, "the box is unchanged")
            }
        }
    }

    // MARK: 2, the mixed head

    private func charizard(cp: Int, hp: Int = 132, bars: IVs, fits: Bool, times: [Double] = []) -> ScanRow { scanned(species: "charizard", display: "Charizard", cp: cp, hp: hp, bars: bars, fits: fits) }

    func testAMixedHeadIsAskedAndTheUnpairedEntryIsNotListedNotSeenWhileItIsOpen() throws {
        let own = entry("own", species: "charizard", cp: 2817, hp: 132), other = entry("other", species: "charizard", cp: 2500, hp: 132, ivs: IVs(atk: 1, def: 1, hp: 1))
        let rows = [charizard(cp: 2817, bars: ownBars, fits: true), charizard(cp: 2017, bars: IVs(atk: 12, def: 13, hp: 10), fits: false)]
        for kind in [BoxStore.Kind.full, .partial] {
            let p = BoxMerge.plan(scanned: rows, into: [own, other], kind: kind, scanDate: date(5), gameMaster: gm)
            XCTAssertEqual(p.new, [], "\(kind)")
            XCTAssertEqual(p.same.map { $0.savedId }, ["own"])
            let u = try XCTUnwrap(p.unsure.first { $0.scanned == 1 })
            XCTAssertEqual(u.kind, .ambiguous, "an empty candidate list is not 'all misreads'")
            XCTAssertEqual(u.candidates, ["other", "own"], "the head as built: unpaired first"); XCTAssertEqual(p.rankedCounts[1], 2)
            if kind == .partial { XCTAssertEqual(p.gone, []); continue }
            // goneReport: open -> nothing; the row was a second read of the paired entry -> the look-alike was not seen; it was the look-alike -> seen; new or left out -> not seen
            XCTAssertEqual(p.gone, [], "open")
            XCTAssertEqual(BoxMerge.goneReport(p, resolutions: [:]).gone, [])
            XCTAssertEqual(BoxMerge.goneReport(p, resolutions: [1: .existing("own")]).gone, ["other"])
            XCTAssertEqual(BoxMerge.goneReport(p, resolutions: [1: .existing("other")]).gone, [])
            XCTAssertEqual(BoxMerge.goneReport(p, resolutions: [1: .new]).gone, ["other"])
            XCTAssertEqual(BoxMerge.goneReport(p, resolutions: [1: .leaveOut]).gone, ["other"])
            // apply for each answer: no entry written twice, no saved row rewritten
            for (name, res) in [("own", BoxMerge.Resolution.existing("own")), ("other", .existing("other")), ("left out", .leaveOut), ("new", .new)] {
                let r = [1: res]
                let after = try BoxMerge.apply(p, resolutions: r, keepGone: BoxMerge.keepSet(plan: p, resolutions: r, markedForRemoval: []), to: [own, other])
                XCTAssertEqual(Set(after.map { $0.id }).count, after.count, name)
                XCTAssertEqual(after.first { $0.id == "own" }?.row, own.row, "\(name): own is not rewritten")
                XCTAssertEqual(after.first { $0.id == "other" }?.row, other.row, "\(name): other is not rewritten")
                XCTAssertEqual(after.count, name == "new" ? 3 : 2, name)
            }
        }
    }

    func testAMixedHeadOneHPOffIsAsked() throws {
        let own = entry("own", species: "charizard", cp: 2017, hp: 132), off = entry("off", species: "charizard", cp: 9999, hp: 131, ivs: IVs(atk: 1, def: 1, hp: 1))
        let rows = [charizard(cp: 2017, bars: ownBars, fits: true), charizard(cp: 9017, bars: IVs(atk: 12, def: 13, hp: 10), fits: false)]
        let p = BoxMerge.plan(scanned: rows, into: [own, off], kind: .full, scanDate: date(5), gameMaster: gm)
        XCTAssertEqual(p.new, [])
        let u = try XCTUnwrap(p.unsure.first { $0.scanned == 1 })
        XCTAssertEqual(u.kind, .ambiguous); XCTAssertEqual(u.candidates, ["off", "own"])
        XCTAssertEqual(BoxMerge.goneReport(p, resolutions: [:]).gone, [])
    }

    /// A head of unpaired entries only (nothing paired in this scan) still leaves the row New.
    func testAHeadOfUnpairedEntriesOnlyIsStillNew() {
        let other = entry("other", species: "charizard", cp: 2500, hp: 132, ivs: IVs(atk: 1, def: 1, hp: 1))
        let p = BoxMerge.plan(scanned: [charizard(cp: 2017, bars: IVs(atk: 12, def: 13, hp: 10), fits: false)], into: [other], kind: .full, scanDate: date(5), gameMaster: gm)
        XCTAssertEqual(p.new, [0]); XCTAssertTrue(p.unsure.isEmpty)
    }

    // MARK: 4, the all-paired question in a full scan

    func testTheAllPairedQuestionIsAmbiguousAndSafeInAFullScan() throws {
        let own = entry("own", species: "charizard", cp: 2017, hp: 132), bystander = entry("bystander", species: "charmander", cp: 300, hp: 40, ivs: IVs(atk: 3, def: 4, hp: 5))
        let box = [own, bystander]
        let rows = [charizard(cp: 2017, bars: ownBars, fits: true), charizard(cp: 9017, bars: IVs(atk: 1, def: 2, hp: 3), fits: false)]
        let p = BoxMerge.plan(scanned: rows, into: box, kind: .full, scanDate: date(5), gameMaster: gm)
        XCTAssertEqual(p.new, [])
        let u = try XCTUnwrap(p.unsure.first { $0.scanned == 1 })
        XCTAssertEqual(u.kind, .ambiguous); XCTAssertEqual(u.candidates, ["own"])
        XCTAssertEqual(p.same.map { $0.savedId }, ["own"])
        for (name, res, count) in [("already seen", BoxMerge.Resolution.existing("own"), 2), ("it is new", .new, 3), ("left out", .leaveOut, 2)] {
            let r = [1: res]
            // the entry the scan never reached is the only one listed, whatever the answer; the paired one never is
            XCTAssertEqual(BoxMerge.goneReport(p, resolutions: r).gone, ["bystander"], name)
            let after = try BoxMerge.apply(p, resolutions: r, keepGone: BoxMerge.keepSet(plan: p, resolutions: r, markedForRemoval: []), to: box)
            XCTAssertEqual(after.count, count, name)
            XCTAssertEqual(after.filter { $0.id == "own" }.count, 1, "\(name): one own entry (no double pair)")
            XCTAssertEqual(after.first { $0.id == "own" }?.row, own.row, "\(name): own is not rewritten")
            XCTAssertEqual(after.first { $0.id == "bystander" }?.row, bystander.row, name)
            XCTAssertEqual(after.first { $0.id == "bystander" }?.lastSeen, date(0), "\(name): not seen, not marked seen")
            XCTAssertEqual(after.first { $0.id == "own" }?.lastSeen, date(5), name)
        }
        XCTAssertEqual(BoxMerge.goneReport(p, resolutions: [:]).gone, ["bystander"], "open")
        XCTAssertEqual(BoxMerge.leftOutLine(p, resolutions: [1: .leaveOut]) != nil, true)
    }

    // MARK: 3, Nidoran

    private func nidoranRow(_ i: Int, species: String, text: String, cp: Int, times: [Double], fits: Bool, bars: IVs?) -> ScanRow {
        let frames = times.map { FrameLabel(frame: "f\(Int($0 * 1000))", time: $0, cp: cp, cpText: String(cp), name: text, hp: "60/60", ivs: "12/13/13", ivConfidence: 0.9, sharpness: 1, clip: nil) }
        return ScanRow(index: i, name: species == "nidoran_female" ? "Nidoran♀" : "Nidoran♂", display: "Nidoran", form: "", speciesId: species, dex: species == "nidoran_female" ? 29 : 32, cp: cp, hp: 60,
                       ivs: fits ? bars : nil, ivsRead: bars, ivsGuess: nil, level: fits ? 20 : nil, levelMax: fits ? 20 : nil, dust: 0, solveStatus: fits ? "exact" : "none", flags: fits ? [] : ["no-level-fits"], frames: frames)
    }
    private func pidgey(_ i: Int, _ t: Double) -> ScanRow {
        ScanRow(index: i, name: "Pidgey", display: "Pidgey", form: "", speciesId: "pidgey", dex: 16, cp: 500, hp: 50, ivs: ownBars, ivsRead: ownBars, ivsGuess: nil, level: 20, levelMax: 20, dust: 0, solveStatus: "exact", flags: [],
                frames: [t, t + 0.4, t + 0.8].map { FrameLabel(frame: "p\(Int($0 * 1000))", time: $0, cp: 500, cpText: "500", name: "Pidgey", hp: "50/50", ivs: "12/13/13", ivConfidence: 0.9, sharpness: 1, clip: nil) })
    }
    private func far(_ i: Int, _ t: Double) -> ScanRow { var r = pidgey(i, t); r.index = i; return r }
    private func fold(_ rows: [ScanRow]) -> [ScanRow] { Refine.absorbFragments(ScanResult(rows: rows, review: [], unmatched: [])).scan.rows }
    /// fragment text and card text: the raw name each reading was taken from ("Nidoran♀" when the symbol was read, "Nidoran" when it was not)
    private func nidoranFolds(fragment: (String, String), card: (String, String)) -> (digit: Int, sliding: Int) {
        let digit = fold([pidgey(1, 0), nidoranRow(2, species: fragment.0, text: fragment.1, cp: 9017, times: [5.0], fits: false, bars: IVs(atk: 12, def: 13, hp: 10)),
                          nidoranRow(3, species: card.0, text: card.1, cp: 2017, times: [5.8, 6.2], fits: true, bars: ownBars), pidgey(9, 20)]).count
        let sliding = fold([pidgey(1, 0), nidoranRow(2, species: fragment.0, text: fragment.1, cp: 632, times: [5.0], fits: false, bars: IVs(atk: 1, def: 2, hp: 3)),
                            nidoranRow(3, species: card.0, text: card.1, cp: 1632, times: [5.4, 5.8, 6.2], fits: true, bars: ownBars), pidgey(9, 20)]).count
        return (digit, sliding)
    }

    func testANidoranWhoseSexWasReadIsNotFoldedIntoTheOtherSex() {
        let f = nidoranFolds(fragment: ("nidoran_female", "Nidoran♀"), card: ("nidoran_male", "Nidoran♂"))
        XCTAssertEqual(f.digit, 4, "digit rule"); XCTAssertEqual(f.sliding, 4, "sliding-in rule")
        // the same sex read on both: folded
        let same = nidoranFolds(fragment: ("nidoran_male", "Nidoran♂"), card: ("nidoran_male", "Nidoran♂"))
        XCTAssertEqual(same.digit, 3); XCTAssertEqual(same.sliding, 3)
    }

    func testANidoranWhoseSexWasNotReadStillFolds() {
        // the fragment's symbol was not read (its id is the first sex its name could be), the card's was: folded, as in round 29
        let a = nidoranFolds(fragment: ("nidoran_female", "Nidoran"), card: ("nidoran_male", "Nidoran♂"))
        XCTAssertEqual(a.digit, 3); XCTAssertEqual(a.sliding, 3)
        // neither read
        let b = nidoranFolds(fragment: ("nidoran_female", "Nidoran"), card: ("nidoran_male", "Nidoran"))
        XCTAssertEqual(b.digit, 3); XCTAssertEqual(b.sliding, 3)
        // the card's symbol was not read, the fragment's was
        let c = nidoranFolds(fragment: ("nidoran_female", "Nidoran♀"), card: ("nidoran_male", "Nidoran"))
        XCTAssertEqual(c.digit, 3); XCTAssertEqual(c.sliding, 3)
    }

    // MARK: helpers

    private func entry(_ id: String, species: String, cp: Int, hp: Int, ivs: IVs? = nil) -> BoxEntry {
        let nf = GameMaster.nameAndForm(gm.byId[species]?.name ?? species)
        let bars = ivs ?? ownBars
        let r = ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: species, dex: gm.byId[species]?.dex, cp: cp, hp: hp, ivs: bars, ivsRead: bars, ivsGuess: nil, level: 20, levelMax: 20, dust: 0, solveStatus: "exact", flags: [], frames: [])
        return BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0))
    }
    private func scanned(species: String, display: String, cp: Int, hp: Int, bars: IVs? = nil, fits: Bool, times: [Double] = []) -> ScanRow {
        let b = bars ?? ownBars
        return ScanRow(index: 1, name: display, display: display, form: "", speciesId: species, dex: gm.byId[species]?.dex, cp: cp, hp: hp, ivs: fits ? b : nil, ivsRead: b, ivsGuess: nil, level: fits ? 20 : nil, levelMax: fits ? 20 : nil,
                       dust: fits ? 0 : nil, solveStatus: fits ? "exact" : "none", flags: fits ? [] : ["no-level-fits"],
                       frames: times.map { FrameLabel(frame: "f\(Int($0 * 1000))", time: $0, cp: cp, cpText: String(cp), name: display, hp: "\(hp)/\(hp)", ivs: "12/13/13", ivConfidence: 0.9, sharpness: 1, clip: nil) })
    }

}
