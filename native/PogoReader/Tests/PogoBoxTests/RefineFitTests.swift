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
                guard Refine.exactLevels(stats(id), cp: cp, hp: hp, ivs: ivs).count == 1, Refine.exactLevels(stats(plain), cp: cp, hp: hp, ivs: ivs).isEmpty else { continue }
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
}
