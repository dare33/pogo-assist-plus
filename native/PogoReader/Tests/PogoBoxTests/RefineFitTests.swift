import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// The rules that decide from the stats (CP, HP, exact bars) what the screen does not say: a regional form behind a bare name (`form-from-stats`).
final class RefineFitTests: XCTestCase {
    let gm = try! GameMaster.bundled()
    private func stats(_ id: String) -> BaseStats { gm.byId[id]!.baseStats! }

    /// `n` readings of one card, 0.4 s apart from `t`, with the values a Pokémon of `ids` shows.
    func card(_ name: String, ids: [String], cp: Int, hp: Int, ivs: IVs?, conf: Double = 0.9, at t: Double, n: Int = 4, tag: String) -> [FrameReading] {
        (0..<n).map { i in
            var f = FrameReading(frame: "\(tag)\(i)", time: t + Double(i) * 0.4)
            f.cp = cp; f.cpText = "CP\(cp)"; f.cpReads = [cp]
            f.name = name; f.nameText = name; f.nameConfidence = 1; f.nameWeak = false; f.nameAttached = false; f.speciesIds = ids
            f.hp = HP(current: hp, max: hp); f.hpText = "\(hp) / \(hp) HP"
            if let ivs { f.ivs = ivs; f.ivConfidence = conf }
            return f
        }
    }

    /// Readings of one card whose frames show these bars in turn (IVs and the reading's confidence).
    func card(_ name: String, ids: [String], cp: Int, hp: Int, bars: [(IVs, Double)], at t: Double, tag: String, cps: [Int]? = nil) -> [FrameReading] {
        bars.enumerated().map { i, b in
            var f = card(name, ids: ids, cp: cps?[i] ?? cp, hp: hp, ivs: b.0, conf: b.1, at: t + Double(i) * 0.4, n: 1, tag: "\(tag)\(i)-")[0]
            f.frame = "\(tag)\(i)"
            return f
        }
    }

    func refined(_ readings: [FrameReading]) throws -> (base: ScanResult, out: Refine.Refined) {
        let base = try sharedEngine.finish(readings: readings)
        return (base, try Refine.apply(to: base, readings: readings, ticks: [], engine: sharedEngine, paging: nil))
    }

    /// IVs and a level at which the CP and HP of `id` are given, such that the Kanto form (`plain`) gives that CP and HP at no level with these bars.
    func valuesOf(_ id: String, notFitting plain: String, other: String? = nil, otherFits: Bool = false, from start: Int = 0) throws -> (cp: Int, hp: Int, ivs: IVs, level: Double) {
        var seen = 0
        for a in stride(from: 15, through: 0, by: -1) { for d in stride(from: 15, through: 0, by: -1) { for h in stride(from: 15, through: 0, by: -1) {
            let ivs = IVs(atk: a, def: d, hp: h)
            for level in stride(from: 20.0, through: 30.0, by: 1.0) {
                let cp = cpAt(stats(id), ivs, level), hp = hpAt(stats(id), ivs, level)
                guard Refine.exactLevels(stats(id), cp: cp, hp: hp, ivs: ivs).count == 1, Refine.exactLevels(stats(plain), cp: cp, hp: hp, ivs: ivs).isEmpty,
                      !Refine.plainFitsNearby([plain], cp: cp, hp: hp, ivs: ivs, gameMaster: gm) else { continue }
                if let other { guard Refine.exactLevels(stats(other), cp: cp, hp: hp, ivs: ivs).isEmpty != otherFits else { continue } }
                if seen < start { seen += 1; continue }
                return (cp, hp, ivs, level)
            }
        } } }
        throw XCTSkip("no such values")
    }

    // MARK: form-from-stats

    func testAGalarianMeowthShownAsMeowthIsTakenFromTheStats() throws {
        let v = try valuesOf("meowth_galarian", notFitting: "meowth", other: "meowth_alolan")
        let readings = card("Meowth", ids: ["meowth"], cp: v.cp, hp: v.hp, ivs: v.ivs, at: 0, tag: "g")
        let (base, out) = try refined(readings)
        XCTAssertNotEqual(base.rows[0].solveStatus, "exact", "the Kanto stats do not give these bars")
        XCTAssertTrue(base.rows[0].flags.contains { $0 == "no-level-fits" || $0.hasPrefix("ambiguous-ivs") }, "\(base.rows[0].flags)")
        let r = try XCTUnwrap(out.scan.rows.first)
        XCTAssertEqual(out.scan.rows.count, 1)
        XCTAssertEqual(r.speciesId, "meowth_galarian")
        XCTAssertEqual(r.solveStatus, "exact")
        XCTAssertEqual(r.ivs, v.ivs); XCTAssertEqual(r.ivsRead, v.ivs); XCTAssertEqual(r.level, v.level)
        XCTAssertEqual(r.display, "Meowth", "the screen name stays")
        XCTAssertEqual(r.form, "Galar")
        XCTAssertTrue(r.flags.contains("form-from-stats:meowth_galarian"), "\(r.flags)")
        XCTAssertFalse(r.flags.contains { $0 == "no-level-fits" || $0.hasPrefix("ambiguous-ivs") })
        XCTAssertTrue(FlagInfo.checkFlags(r.flags, solveStatus: r.solveStatus).isEmpty, "a note, not a check")
        XCTAssertFalse(FlagInfo.explainNote("form-from-stats:meowth_galarian").isEmpty)
        XCTAssertEqual(r.frames.count, 4, "the frames stay")
        XCTAssertEqual(out.changes.filter { $0.kind == .formFromStats }.count, 1)
        XCTAssertTrue(out.scan.review.contains { $0.flags.contains("form-from-stats:meowth_galarian") })
    }

    func testTheFormIsFoundWhenTheSolverOnlyOfferedNearbyBars() throws {
        // the Kanto stats fit the CP and HP with some other bars (ambiguous-ivs), but not these: still the regional form
        var found = 0
        for k in 0..<40 {
            guard let v = try? valuesOf("sandshrew_alolan", notFitting: "sandshrew", from: k) else { break }
            let (base, out) = try refined(card("Sandshrew", ids: ["sandshrew"], cp: v.cp, hp: v.hp, ivs: v.ivs, at: 0, tag: "s"))
            guard base.rows.first?.solveStatus == "ambiguous" else { continue }
            found += 1
            XCTAssertEqual(out.scan.rows.first?.speciesId, "sandshrew_alolan", "\(v)")
            XCTAssertEqual(out.scan.rows.first?.solveStatus, "exact")
            if found == 2 { break }
        }
        XCTAssertGreaterThan(found, 0, "no ambiguous example found")
    }

    func testARowTheSolverTookExactlyIsNotTouched() throws {
        let ivs = IVs(atk: 11, def: 12, hp: 13), level = 20.0
        let cp = cpAt(stats("meowth"), ivs, level), hp = hpAt(stats("meowth"), ivs, level)
        let (base, out) = try refined(card("Meowth", ids: ["meowth"], cp: cp, hp: hp, ivs: ivs, at: 0, tag: "k"))
        XCTAssertEqual(out.scan.rows, base.rows.map { var r = $0; r.index = 1; return r })
        XCTAssertEqual(out.scan.rows[0].speciesId, "meowth")
    }

    func testAKantoPokemonMisreadByANotchIsNotTurnedIntoItsRegionalForm() throws {
        // a Kanto Sandshrew CP 466 / HP 74 with bars 0/0/3 at level 16, its HP bar read 0/0/4: those bars fit the Alolan form at level 15.5, but the plain form fits with one bar a notch off
        let kanto = IVs(atk: 0, def: 0, hp: 3), read = IVs(atk: 0, def: 0, hp: 4)
        XCTAssertEqual(cpAt(stats("sandshrew"), kanto, 16), 466); XCTAssertEqual(hpAt(stats("sandshrew"), kanto, 16), 74)
        XCTAssertTrue(Refine.exactLevels(stats("sandshrew"), cp: 466, hp: 74, ivs: read).isEmpty)
        XCTAssertEqual(Refine.exactLevels(stats("sandshrew_alolan"), cp: 466, hp: 74, ivs: read), [15.5])
        XCTAssertTrue(Refine.plainFitsNearby(["sandshrew"], cp: 466, hp: 74, ivs: read, gameMaster: gm))
        let (base, out) = try refined(card("Sandshrew", ids: ["sandshrew"], cp: 466, hp: 74, ivs: read, at: 0, tag: "z"))
        XCTAssertNotEqual(base.rows[0].solveStatus, "exact")
        XCTAssertEqual(out.scan.rows[0].speciesId, "sandshrew")
        XCTAssertNotEqual(out.scan.rows[0].solveStatus, "exact")
        XCTAssertFalse(out.scan.rows[0].flags.contains { $0.hasPrefix("form-from-stats") })
        XCTAssertFalse(FlagInfo.checkFlags(out.scan.rows[0].flags, solveStatus: out.scan.rows[0].solveStatus).isEmpty, "it still asks for a look")
    }

    func testTwoFormsThatFitMeanNothingChanges() throws {
        // both regional forms give this CP, HP and bars at exactly one level: the stats cannot say which
        let v = try valuesOf("meowth_galarian", notFitting: "meowth", other: "meowth_alolan", otherFits: true)
        let (_, out) = try refined(card("Meowth", ids: ["meowth"], cp: v.cp, hp: v.hp, ivs: v.ivs, at: 0, tag: "t"))
        let r = out.scan.rows[0]
        XCTAssertEqual(r.speciesId, "meowth")
        XCTAssertFalse(r.flags.contains { $0.hasPrefix("form-from-stats") })
        XCTAssertTrue(r.solveStatus != "exact")
    }

    func testNoFormFitsMeansNothingChanges() throws {
        let ivs = IVs(atk: 11, def: 12, hp: 13)
        // a CP no Meowth has with these bars
        let cp = cpAt(stats("meowth"), ivs, 20) + 1, hp = hpAt(stats("meowth"), ivs, 20)
        let (base, out) = try refined(card("Meowth", ids: ["meowth"], cp: cp, hp: hp, ivs: ivs, at: 0, tag: "n"))
        let alt = Refine.alternativeForms(of: ["meowth"], gameMaster: gm).filter { !Refine.exactLevels($0.stats, cp: cp, hp: hp, ivs: ivs).isEmpty }
        try XCTSkipUnless(alt.isEmpty, "a form fits")
        XCTAssertEqual(out.scan.rows[0].speciesId, "meowth")
        XCTAssertEqual(out.scan.rows[0].flags, base.rows[0].flags)
    }

    func testShadowAndMegaFormsAreNotAnotherForm() {
        XCTAssertEqual(Refine.alternativeForms(of: ["meowth"], gameMaster: gm).map(\.id), ["meowth_alolan", "meowth_galarian"], "meowth_shadow shares the Kanto stats")
        XCTAssertEqual(Refine.alternativeForms(of: ["charizard"], gameMaster: gm).map(\.id), [], "Mega forms have their own names on screen")
        XCTAssertEqual(Refine.alternativeForms(of: ["vulpix"], gameMaster: gm).map(\.id), [], "Alolan Vulpix has the Kanto stats")
        XCTAssertEqual(Refine.alternativeForms(of: ["pikachu"], gameMaster: gm).map(\.id), [], "costume Pikachu share the stats")
        XCTAssertEqual(Refine.alternativeForms(of: ["deoxys"], gameMaster: gm).map(\.id), [], "battle-only forms with other stats are not a regional form behind a bare name")
        XCTAssertEqual(Refine.alternativeForms(of: ["charizard_mega_x"], gameMaster: gm).map(\.id), [], "a Mega row has its own name on screen")
        XCTAssertEqual(Refine.alternativeForms(of: ["meowth", "charizard_mega_y"], gameMaster: gm).map(\.id), [])
        XCTAssertEqual(Refine.alternativeForms(of: ["farfetchd"], gameMaster: gm).map(\.id), ["farfetchd_galarian"])
        XCTAssertEqual(Refine.alternativeForms(of: ["diglett"], gameMaster: gm).map(\.id), ["diglett_alolan"])
    }

    func testARowWhoseBarsAreStillMovingIsNotTried() throws {
        let v = try valuesOf("meowth_galarian", notFitting: "meowth")
        let (_, out) = try refined(card("Meowth", ids: ["meowth"], cp: v.cp, hp: v.hp, ivs: v.ivs, conf: 0.5, at: 0, tag: "u"))
        XCTAssertEqual(out.scan.rows[0].speciesId, "meowth")
        XCTAssertFalse(out.scan.rows[0].flags.contains { $0.hasPrefix("form-from-stats") })
    }

    // MARK: saved entries (BoxMerge pairs by species id)

    private func scanned(_ id: String, display: String, cp: Int, hp: Int, ivs: IVs?, flags: [String], status: String) -> ScanRow {
        let nf = GameMaster.nameAndForm(gm.byId[id]!.name)
        return ScanRow(index: 1, name: nf.name, display: display, form: nf.form, speciesId: id, dex: gm.byId[id]!.dex, cp: cp, hp: hp, ivs: ivs, ivsRead: ivs, ivsGuess: nil,
                       level: ivs == nil ? nil : 20, levelMax: ivs == nil ? nil : 20, dust: nil, solveStatus: status, flags: flags, frames: [])
    }
    private func saved(_ r: ScanRow, id: String) -> BoxEntry { BoxEntry(id: id, row: r, firstSeen: Date(timeIntervalSince1970: 1_790_000_000), lastSeen: Date(timeIntervalSince1970: 1_790_000_000), corrections: Corrections()) }
    private func plan(_ rows: [ScanRow], _ entries: [BoxEntry]) -> BoxMerge.Plan { BoxMerge.plan(scanned: rows, into: entries, kind: .full, scanDate: Date(timeIntervalSince1970: 1_790_864_000), gameMaster: gm) }

    func testARowWithAFormFromStatsPairsWithTheEntrySavedBeforeTheFormWasKnown() {
        // saved by an earlier scan: fitted no level, so the plain species id and no IVs
        let before = saved(scanned("meowth", display: "Meowth", cp: 644, hp: 100, ivs: nil, flags: ["no-level-fits"], status: "none"), id: "old")
        let now = scanned("meowth_galarian", display: "Meowth", cp: 644, hp: 100, ivs: IVs(atk: 1, def: 5, hp: 11), flags: ["form-from-stats:meowth_galarian"], status: "exact")
        let p = plan([now], [before])
        XCTAssertTrue(p.new.isEmpty, "not a new Pokémon: \(p)")
        XCTAssertTrue(p.gone.isEmpty, "the old entry is not left behind: \(p)")
        XCTAssertEqual(p.updated.count + p.unsure.count + p.same.count, 1)
        // without the flag it would be another species
        var plain = now; plain.flags = []
        XCTAssertEqual(plan([plain], [before]).new, [0])
    }

    func testAnUnsolvedRowStillFindsTheEntrySavedWithAFormFromStats() {
        let entry = saved(scanned("meowth_galarian", display: "Meowth", cp: 644, hp: 100, ivs: IVs(atk: 1, def: 5, hp: 11), flags: ["form-from-stats:meowth_galarian"], status: "exact"), id: "e")
        let unread = scanned("meowth", display: "Meowth", cp: 64, hp: 100, ivs: nil, flags: ["no-level-fits"], status: "none")
        let p = plan([unread], [entry])
        XCTAssertTrue(p.unsure.contains { $0.scanned == 0 && $0.candidates.contains("e") }, "asked about it, not new: \(p)")
        // an entry of the same species WITHOUT the flag is another Pokémon's form: not offered
        var noFlag = entry; noFlag.row.flags = []
        XCTAssertFalse(plan([unread], [noFlag]).unsure.contains { $0.candidates.contains("e") })
    }

    // MARK: ivs-chosen-by-fit

    /// A Pokémon of `id` at `level` with `good` bars, and bars one def step off that give its CP and HP at no level.
    private func twoStates(_ id: String = "togepi", level: Double = 20, good: IVs = IVs(atk: 13, def: 11, hp: 14)) -> (cp: Int, hp: Int, good: IVs, bad: IVs) {
        let cp = cpAt(stats(id), good, level), hp = hpAt(stats(id), good, level)
        for d in [-1, 1, -2, 2] {
            let bad = IVs(atk: good.atk, def: good.def + d, hp: good.hp)
            if bad.def >= 0, bad.def <= 15, Refine.exactLevels(stats(id), cp: cp, hp: hp, ivs: bad).isEmpty { return (cp, hp, good, bad) }
        }
        XCTFail("no off state"); return (cp, hp, good, good)
    }

    func testTheStateThatFitsIsKeptWhenTheVoteChoseAnother() throws {
        // Togepi 359 / 74: one reading at 0.79 of the wrong bars, then the right bars three times at 0.696 (below settled), so the solver takes the first
        let t = twoStates()
        let readings = card("Togepi", ids: ["togepi"], cp: t.cp, hp: t.hp, bars: [(t.bad, 0.79), (t.good, 0.696), (t.good, 0.696), (t.good, 0.696)], at: 0, tag: "t")
        let (base, out) = try refined(readings)
        XCTAssertNotEqual(base.rows[0].solveStatus, "exact", "\(base.rows[0].flags)")
        XCTAssertEqual(out.scan.rows.count, 1)
        let r = out.scan.rows[0]
        XCTAssertEqual(r.ivs, t.good); XCTAssertEqual(r.ivsRead, t.good); XCTAssertEqual(r.solveStatus, "exact"); XCTAssertEqual(r.level, 20)
        XCTAssertTrue(r.flags.contains("ivs-chosen-by-fit:13/11/14"), "\(r.flags)")
        XCTAssertFalse(r.flags.contains { $0.hasPrefix("ambiguous-ivs") || $0 == "no-level-fits" || $0.hasPrefix("ivs-corrected") })
        XCTAssertTrue(FlagInfo.checkFlags(r.flags, solveStatus: r.solveStatus).isEmpty, "a note on an exact row")
        XCTAssertEqual(out.changes.filter { $0.kind == .ivsChosenByFit }.count, 1)
    }

    func testTwoStatesThatBothFitChangeNothing() throws {
        // two real Pokémon with the same name, CP and HP: both states fit, so the choice is not ours
        let id = "togepi"
        var pair: (CP: Int, HP: Int, a: IVs, b: IVs)?
        search: for hpIv in 0...15 { for level in [20.0, 21.0, 22.0] {
            var byCp = [Int: IVs]()
            for a in 0...15 { for d in 0...15 {
                let v = IVs(atk: a, def: d, hp: hpIv), cp = cpAt(stats(id), v, level)
                if let other = byCp[cp], other != v { pair = (cp, hpAt(stats(id), v, level), other, v); break search }
                byCp[cp] = v
            } }
        } }
        let p = try XCTUnwrap(pair)
        let readings = card("Togepi", ids: ["togepi"], cp: p.CP, hp: p.HP, bars: [(p.a, 0.9), (p.a, 0.9), (p.b, 0.9), (p.b, 0.9)], at: 0, tag: "b")
        let (base, out) = try refined(readings)
        XCTAssertFalse(out.scan.rows.contains { $0.flags.contains { $0.hasPrefix("ivs-chosen-by-fit") } }, "\(out.scan.rows.map(\.flags))")
        XCTAssertEqual(out.scan.rows.map(\.ivs), base.rows.map(\.ivs), "the rows are what the solver and the other passes made of it")
    }

    func testTwoStatesThatBothFailChangeNothing() throws {
        let t = twoStates()
        let worse = IVs(atk: t.bad.atk, def: t.bad.def, hp: t.bad.hp == 0 ? 1 : t.bad.hp - 1)
        try XCTSkipUnless(Refine.exactLevels(stats("togepi"), cp: t.cp, hp: t.hp, ivs: worse).isEmpty)
        let (base, out) = try refined(card("Togepi", ids: ["togepi"], cp: t.cp, hp: t.hp, bars: [(t.bad, 0.79), (worse, 0.696), (worse, 0.696)], at: 0, tag: "w"))
        XCTAssertEqual(out.scan.rows[0].flags, base.rows[0].flags)
        XCTAssertEqual(out.scan.rows[0].solveStatus, base.rows[0].solveStatus)
    }

    func testAStateHeldByOneReadingIsNotEnough() throws {
        let t = twoStates()
        let (_, out) = try refined(card("Togepi", ids: ["togepi"], cp: t.cp, hp: t.hp, bars: [(t.bad, 0.79), (t.bad, 0.79), (t.good, 0.696)], at: 0, tag: "o"))
        XCTAssertFalse(out.scan.rows[0].flags.contains { $0.hasPrefix("ivs-chosen-by-fit") })
    }

    func testBarsThatChangeWithTheCpReadAreTwoPokemonAndNotChosenBetween() throws {
        // Staraptor 1958 beside 1954: the CP read changes with the bars, so a state fitting "the row's CP" says nothing about the other
        let t = twoStates("staraptor", level: 25, good: IVs(atk: 12, def: 11, hp: 12))
        let other = cpAt(stats("staraptor"), t.bad, 25)
        let readings = card("Staraptor", ids: ["staraptor"], cp: t.cp, hp: t.hp, bars: [(t.good, 0.9), (t.good, 0.9), (t.bad, 0.9), (t.bad, 0.9)], at: 0, tag: "c", cps: [t.cp, t.cp, other, other])
        let (_, out) = try refined(readings)
        XCTAssertFalse(out.scan.rows.contains { $0.flags.contains { $0.hasPrefix("ivs-chosen-by-fit") } }, "\(out.scan.rows.map { "\($0.cp) \($0.flags)" })")
    }

    func testTwoRealTwinsWhoseSecondHasBarsMisreadByANotchStayTwoRows() throws {
        // device-run8's two Fidough (CP 768, HP 89, bars 15/4/10 and 15/11/12 on consecutive beats) are two Pokémon. Misread the second's bars by one notch (15/11/13, which fit no level) and
        // it looks exactly like one card with a flickering state, but the cut the beat allowed stays a cut and the second twin asks for its look: choosing by fit would hide a real Pokémon.
        var readings = try ReplayReadings.load(url: Fixture.url("device-run8-fidough-stretch.replay.jsonl")).readings
        let ticks = try ReplayReadings.load(url: Fixture.url("device-run8-fidough-stretch.replay.jsonl")).ticks
        let both = try Refine.apply(to: try sharedEngine.finish(readings: readings), readings: readings, ticks: ticks, engine: sharedEngine, paging: PagingHint(pagedByCommand: true))
        XCTAssertEqual(both.scan.rows.filter { $0.display == "Fidough" && $0.cp == 768 }.count, 2, "both states fit: two rows as before")
        XCTAssertFalse(both.scan.rows.contains { $0.flags.contains { $0.hasPrefix("ivs-chosen-by-fit") } })
        let misread = IVs(atk: 15, def: 11, hp: 13)
        XCTAssertTrue(Refine.exactLevels(stats("fidough"), cp: 768, hp: 89, ivs: misread).isEmpty)
        for i in readings.indices where readings[i].name == "Fidough" && readings[i].ivs == IVs(atk: 15, def: 11, hp: 12) { readings[i].ivs = misread }
        // (the second Fidough's CP is partly hidden on some frames in the log: read in full here)
        for i in readings.indices where readings[i].name == "Fidough" && readings[i].hp?.max == 89 { readings[i].cp = 768; readings[i].cpText = "CP768"; readings[i].cpReads = [768] }
        let out = try Refine.apply(to: try sharedEngine.finish(readings: readings), readings: readings, ticks: ticks, engine: sharedEngine, paging: PagingHint(pagedByCommand: true))
        let f = out.scan.rows.filter { $0.display == "Fidough" && $0.cp == 768 }
        XCTAssertEqual(f.count, 2, "\(out.changes)")
        XCTAssertTrue(f.allSatisfy { $0.flags.contains("split-by-bars") })
        XCTAssertFalse(f.contains { $0.flags.contains { $0.hasPrefix("ivs-chosen-by-fit") } }, "\(f.map(\.flags))")
        XCTAssertTrue(f.contains { !FlagInfo.checkFlags($0.flags, solveStatus: $0.solveStatus).isEmpty }, "the check stays: \(f.map(\.flags))")
        XCTAssertEqual(out.changes.filter { $0.kind == .ivsChosenByFit }.count, 0)
    }

    /// Cards of Togepi at other levels (so other CPs, each its own row) on the 1.2 s beat: three readings 0.4 s apart each, from `start`.
    private func beat(_ count: Int, from start: Double, tag: String) -> [FrameReading] {
        let ivs = IVs(atk: 10, def: 10, hp: 10)
        return (0..<count).flatMap { k -> [FrameReading] in
            let level = 10.0 + Double(k) * 0.5
            return card("Togepi", ids: ["togepi"], cp: cpAt(stats("togepi"), ivs, level), hp: hpAt(stats("togepi"), ivs, level), ivs: ivs, at: start + Double(k) * 1.2, n: 3, tag: "\(tag)\(k)-")
        }
    }

    /// Run27's Staraptor 1951 / HP 140 (row 35): 11/12/12 gives CP 1952 at HP 140, so only 11/11/13 fits. `stay` readings 0.4 s apart, the first half 11/12/12 and the rest 11/11/13, in the middle of a steady beat.
    private func staraptorInABeat(stay: Int, cpReads: [Int?]) throws -> Refine.Refined {
        let a = IVs(atk: 11, def: 12, hp: 12), b = IVs(atk: 11, def: 11, hp: 13)
        let hp = 140
        XCTAssertEqual(cpAt(stats("staraptor"), b, 25), 1951); XCTAssertEqual(hpAt(stats("staraptor"), b, 25), hp); XCTAssertNotEqual(cpAt(stats("staraptor"), a, 25), 1951)
        var star = card("Staraptor", ids: ["staraptor"], cp: 1951, hp: hp, bars: (0..<stay).map { $0 < stay / 2 ? (a, 0.79) : (b, 0.696) }, at: 7 * 1.2, tag: "st")
        for i in star.indices { let r = cpReads[i % cpReads.count]; star[i].cp = r; star[i].cpText = r.map { "CP\($0)" } ?? ""; star[i].cpReads = r.map { [$0] } }
        let readings = beat(7, from: 0, tag: "p") + star + beat(7, from: 7 * 1.2 + Double(stay) * 0.4 + 0.4, tag: "q")
        let base = try sharedEngine.finish(readings: readings)
        return try Refine.apply(to: base, readings: readings, ticks: [], engine: sharedEngine, paging: nil)
    }

    func testThreeCardsOverTwoSecondsWithBarsOneNotchApartKeepTheirCheck() throws {
        // run27's Staraptor: the CP read 1951 once and then hid (or read 951 and 51) while the bars went 11/12/12 to 11/11/13. Two real Pokémon of CP 1952 and 1951 look like one flickering card
        // once the second is exact; the stay is two seconds on a 1.2 s beat, so choosing the state that fits would hide the first
        let out = try staraptorInABeat(stay: 6, cpReads: [1951, nil, nil, 1951, 951, 51])
        let rows = out.scan.rows.filter { $0.display == "Staraptor" }
        XCTAssertFalse(rows.isEmpty)
        XCTAssertFalse(rows.contains { $0.flags.contains { $0.hasPrefix("ivs-chosen-by-fit") } }, "\(rows.map(\.flags))")
        XCTAssertTrue(rows.contains { !FlagInfo.checkFlags($0.flags, solveStatus: $0.solveStatus).isEmpty }, "the check stays: \(rows.map { "\($0.solveStatus) \($0.flags)" })")
    }

    func testAStayOfTwoSecondsIsNotChosenEvenWhenEveryCpReadMatches() throws {
        // the span guard alone: every reading that has a CP reads the row's, the stay is still longer than one card's
        let out = try staraptorInABeat(stay: 6, cpReads: [1951])
        XCTAssertFalse(out.scan.rows.contains { $0.flags.contains { $0.hasPrefix("ivs-chosen-by-fit") } }, "\(out.scan.rows.filter { $0.display == "Staraptor" }.map(\.flags))")
    }

    func testABarStateWhoseReadingsReadAnotherCpIsNotChosenEvenInOneStay() throws {
        // the CP guard alone: a stay of one card's length (4 readings), but one reading of the fitting state read 951
        let out = try staraptorInABeat(stay: 4, cpReads: [1951, 1951, 951, 1951])
        XCTAssertFalse(out.scan.rows.contains { $0.flags.contains { $0.hasPrefix("ivs-chosen-by-fit") } }, "\(out.scan.rows.filter { $0.display == "Staraptor" }.map(\.flags))")
    }

    func testAStayWithNoBeatKnownAndMoreReadingsThanOneCardGivesIsNotChosen() throws {
        let t = twoStates()
        let bars: [(IVs, Double)] = [(t.bad, 0.79)] + Array(repeating: (t.good, 0.696), count: 4)
        let (_, out) = try refined(card("Togepi", ids: ["togepi"], cp: t.cp, hp: t.hp, bars: bars, at: 0, tag: "m"))
        XCTAssertFalse(out.scan.rows.contains { $0.flags.contains { $0.hasPrefix("ivs-chosen-by-fit") } })
        let (_, four) = try refined(card("Togepi", ids: ["togepi"], cp: t.cp, hp: t.hp, bars: Array(bars.prefix(4)), at: 0, tag: "f"))
        XCTAssertTrue(four.scan.rows.contains { $0.flags.contains { $0.hasPrefix("ivs-chosen-by-fit") } }, "four readings are one card")
    }

    func testAnEarlyMisreadAndTwoSettledFittingReadingsInOneBeatAreChosenByFit() throws {
        // the legitimate case on a known beat: one card (0.8 s of readings on the 1.2 s beat), the previous card's bars on the first frame, the right bars on the next two
        let t = twoStates("staraptor", level: 25, good: IVs(atk: 11, def: 11, hp: 13))
        let star = card("Staraptor", ids: ["staraptor"], cp: t.cp, hp: t.hp, bars: [(t.bad, 0.79), (t.good, 0.696), (t.good, 0.696)], at: 7 * 1.2, tag: "ok")
        let readings = beat(7, from: 0, tag: "p") + star + beat(7, from: 7 * 1.2 + 1.2, tag: "q")
        let out = try Refine.apply(to: try sharedEngine.finish(readings: readings), readings: readings, ticks: [], engine: sharedEngine, paging: nil)
        let r = try XCTUnwrap(out.scan.rows.first { $0.display == "Staraptor" })
        XCTAssertEqual(r.ivs, t.good); XCTAssertEqual(r.solveStatus, "exact")
        XCTAssertTrue(r.flags.contains { $0.hasPrefix("ivs-chosen-by-fit") }, "\(r.flags)")
    }

    func testTheStateThatFitsAnotherFormIsTakenWithThatForm() throws {
        // Meowth 317 / 68 of run28: the bars that fit are the Alolan form's, and the vote chose the other state
        let v = try valuesOf("meowth_alolan", notFitting: "meowth", other: "meowth_galarian")
        var wrong = v.ivs; wrong.def = wrong.def == 0 ? 1 : wrong.def - 1
        try XCTSkipUnless(Refine.exactLevels(stats("meowth_alolan"), cp: v.cp, hp: v.hp, ivs: wrong).isEmpty && Refine.exactLevels(stats("meowth"), cp: v.cp, hp: v.hp, ivs: wrong).isEmpty)
        let (_, out) = try refined(card("Meowth", ids: ["meowth"], cp: v.cp, hp: v.hp, bars: [(wrong, 0.79), (v.ivs, 0.696), (v.ivs, 0.696)], at: 0, tag: "a"))
        let r = out.scan.rows[0]
        XCTAssertEqual(r.speciesId, "meowth_alolan"); XCTAssertEqual(r.solveStatus, "exact"); XCTAssertEqual(r.ivs, v.ivs)
        XCTAssertTrue(r.flags.contains("ivs-chosen-by-fit:\(v.ivs.atk)/\(v.ivs.def)/\(v.ivs.hp)") && r.flags.contains("form-from-stats:meowth_alolan"), "\(r.flags)")
    }

    // MARK: cp-recovered (leading digit)

    /// Frames of one card whose CP reads are these, in turn (the bars are not settled, so the JavaScript's own recovery does not run).
    private func shortCard(_ name: String, ids: [String], reads: [Int], hp: Int, ivs: IVs, conf: Double = 0.5) -> [FrameReading] {
        card(name, ids: ids, cp: reads[0], hp: hp, bars: reads.map { _ in (ivs, conf) }, at: 0, tag: "d", cps: reads)
    }

    func testALeadingDigitCutOffOnEveryFrameIsRecoveredWhenOneCandidateFits() throws {
        // Moltres 1917 / HP 130 / bars 11/11/12 (run28): every frame read "917" or "17"
        let ivs = IVs(atk: 11, def: 11, hp: 12)
        let cp = cpAt(stats("moltres"), ivs, 20), hp = hpAt(stats("moltres"), ivs, 20)
        XCTAssertEqual(cp, 1917)
        let (base, out) = try refined(shortCard("Moltres", ids: ["moltres"], reads: [917, 17, 917, 17], hp: hp, ivs: ivs))
        XCTAssertTrue(base.rows[0].flags.contains("no-level-fits"), "\(base.rows[0].flags)")
        let r = out.scan.rows[0]
        XCTAssertEqual(r.cp, 1917); XCTAssertEqual(r.solveStatus, "exact"); XCTAssertEqual(r.level, 20); XCTAssertEqual(r.ivs, ivs)
        XCTAssertTrue(r.flags.contains("cp-recovered:1917-from-917"), "\(r.flags)")
        XCTAssertFalse(r.flags.contains("no-level-fits"))
        XCTAssertTrue(FlagInfo.checkFlags(r.flags, solveStatus: r.solveStatus).filter { !$0.hasPrefix("bars-unsettled") }.isEmpty)
        XCTAssertEqual(out.changes.filter { $0.kind == .cpRecovered }.count, 1)
    }

    func testATwoDigitReadGetsAHundredsDigit() throws {
        // a Pidgey whose CP is three digits and shows only its last two
        let ivs = IVs(atk: 5, def: 6, hp: 7)
        let level = try XCTUnwrap(levels.first { cpAt(stats("pidgey"), ivs, $0) >= 100 && cpAt(stats("pidgey"), ivs, $0) < 1000 && cpAt(stats("pidgey"), ivs, $0) % 100 >= 10 && Refine.exactLevels(stats("pidgey"), cp: cpAt(stats("pidgey"), ivs, $0), hp: hpAt(stats("pidgey"), ivs, $0), ivs: ivs).count == 1 })
        let hp = hpAt(stats("pidgey"), ivs, level), cp = cpAt(stats("pidgey"), ivs, level)
        let (base, out) = try refined(shortCard("Pidgey", ids: ["pidgey"], reads: [cp % 100, cp % 100, cp % 100], hp: hp, ivs: ivs))
        XCTAssertTrue(base.rows[0].flags.contains("no-level-fits"), "\(base.rows[0].flags)")
        let r = out.scan.rows[0]
        XCTAssertEqual(r.cp, cp, "\(r.flags)")
        XCTAssertTrue(r.flags.contains("cp-recovered:\(cp)-from-\(cp % 100)"), "\(r.flags)")
    }

    func testTwoCandidatesThatFitMeanNothingChanges() throws {
        // two levels with the same HP give two CPs; the frames read the tail of each: both candidates fit, so the digit is not ours to supply
        let ivs = IVs(atk: 11, def: 11, hp: 12)
        let st = stats("moltres")
        var pair: (Int, Int, Int)?
        for (a, b) in zip(levels, levels.dropFirst()) {
            let c1 = cpAt(st, ivs, a), c2 = cpAt(st, ivs, b)
            if hpAt(st, ivs, a) == hpAt(st, ivs, b), c1 / 1000 == c2 / 1000, c1 >= 1000, c2 != c1 { pair = (c1, c2, hpAt(st, ivs, a)); break }
        }
        let p = try XCTUnwrap(pair)
        let (base, out) = try refined(shortCard("Moltres", ids: ["moltres"], reads: [p.0 % 1000, p.1 % 1000, p.0 % 1000, p.1 % 1000], hp: p.2, ivs: ivs))
        XCTAssertTrue(base.rows.contains { $0.flags.contains("no-level-fits") }, "\(base.rows.map(\.flags))")
        XCTAssertFalse(out.scan.rows.contains { $0.flags.contains { $0.hasPrefix("cp-recovered") } }, "\(out.scan.rows.map { "\($0.cp) \($0.flags)" })")
    }

    func testNoCandidateThatFitsMeansNothingChanges() throws {
        // run28's Moltres "939" / "29" with HP 132 and bars 10/15/14: the stats give 1938 at that HP, which is no digit put in front of what was read
        let ivs = IVs(atk: 10, def: 15, hp: 14)
        let (base, out) = try refined(shortCard("Moltres", ids: ["moltres"], reads: [29, 939], hp: 132, ivs: ivs, conf: 0.9))
        XCTAssertTrue(base.rows[0].flags.contains("no-level-fits"))
        XCTAssertEqual(out.scan.rows[0].cp, base.rows[0].cp)
        XCTAssertTrue(out.scan.rows[0].flags.contains("no-level-fits"))
        XCTAssertFalse(out.scan.rows[0].flags.contains { $0.hasPrefix("cp-recovered") })
    }
}
