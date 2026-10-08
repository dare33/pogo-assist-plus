import Foundation
import PogoReader

extension Refine {
    /// A form of the screen's species whose base stats differ from every form the screen name already maps to (`meowth_galarian` for "Meowth").
    struct AltForm: Equatable { var id: String; var stats: BaseStats }

    /// The species ids the screen name mapped to for this row (the grouper's candidates), from the row's own readings; the row's solved id when none were kept.
    static func screenIds(_ row: ScanRow, readings: [FrameReading], labelIndex: [String: Int]) -> [String] {
        for f in row.frames {
            if let l = f.frame.flatMap({ labelIndex[$0] }), let ids = readings[l].speciesIds, !ids.isEmpty { return ids }
        }
        return [row.speciesId]
    }

    /// The levels at which these base stats give exactly this CP and HP with exactly these IVs (tier 0 of the solver: no tolerance on the bars).
    static func exactLevels(_ stats: BaseStats, cp: Int, hp: Int, ivs: IVs) -> [Double] {
        levels.filter { cpAt(stats, ivs, $0) == cp && hpAt(stats, ivs, $0) == hp }
    }

    /// The other forms of the same dex number whose base stats differ from every screen form's, one per distinct set of stats. Shadow forms share their base's stats, so
    /// they never count as another form; a Mega or primal form has its own name on screen and is not what a bare name hides. Of several ids with the same stats (costumes) the plainest is used,
    /// the order the solver ranks equal forms in.
    static func alternativeForms(of ids: [String], gameMaster gm: GameMaster) -> [AltForm] {
        let dexes = Set(ids.compactMap { gm.byId[$0]?.dex })
        let own = Set(ids.compactMap { gm.byId[$0]?.baseStats })
        var best = [BaseStats: String]()
        for (id, s) in gm.byId where dexes.contains(s.dex) && !ids.contains(id) {
            guard let stats = s.baseStats, !own.contains(stats), !["_shadow", "_mega", "_primal"].contains(where: { id.contains($0) }) else { continue }
            if let b = best[stats], (b.count, b) <= (id.count, id) { continue }
            best[stats] = id
        }
        return best.map { AltForm(id: $0.value, stats: $0.key) }.sorted { $0.id < $1.id }
    }

    /// The solver's row for this Pokémon taken as `speciesIds` with this CP and these exact bars: the values go in as readings of three frames and `finish` is run on them
    /// (as `LevelSolve` and the hidden-CP rule do). nil unless the answer is the one row, solved `exact` with the bars given.
    static func solvedRow(_ row: ScanRow, speciesIds: [String], cp: Int, ivs: IVs, engine: CoreEngine) -> ScanRow? {
        var frames = [FrameReading]()
        for i in 0..<3 {
            var f = FrameReading(frame: "s\(i + 1)", time: Double(i) * 0.25)
            f.cp = cp; f.cpText = String(cp); f.cpReads = [cp]
            f.name = row.display; f.nameText = row.display; f.nameConfidence = 1; f.nameWeak = false; f.nameAttached = false
            f.speciesIds = speciesIds
            if let hp = row.hp { f.hp = HP(current: hp, max: hp); f.hpText = "\(hp) / \(hp) HP" }
            f.ivs = ivs; f.ivConfidence = 1
            frames.append(f)
        }
        guard let result = try? engine.finish(readings: frames), result.rows.count == 1, let r = result.rows.first,
              r.solveStatus == "exact", r.ivs == ivs, r.cp == cp, r.level != nil else { return nil }
        return r
    }

    /// The row with the solver's answer in it: species, name, form, CP, bars, level, range and dust, status `exact`. What the old solve said against it (`no-level-fits`, `ambiguous-ivs`,
    /// `ivs-corrected-from`, the old level and form notes) goes, and the new solve's level and form notes come in. Every other flag, the frames and the index stay.
    static func adopting(_ solved: ScanRow, into row: ScanRow, ivsRead: IVs) -> ScanRow {
        var out = row
        out.speciesId = solved.speciesId; out.name = solved.name; out.form = solved.form; out.dex = solved.dex; out.cp = solved.cp
        out.ivs = solved.ivs; out.ivsRead = ivsRead; out.ivsGuess = nil
        out.level = solved.level; out.levelMax = solved.levelMax; out.dust = solved.dust; out.solveStatus = "exact"
        let old = ["no-level-fits", "ambiguous-ivs", "ivs-corrected-from", "level-ambiguous", "form-ambiguous"]
        out.flags.removeAll { f in old.contains { f == $0 || f.hasPrefix($0 + ":") || f.hasPrefix($0 + "-") } }
        out.flags += solved.flags.filter { $0.hasPrefix("level-ambiguous") || $0.hasPrefix("form-ambiguous") }
        return out
    }

    /// One bar state of a row's readings: how many readings held it, the best confidence among them, and whether one of them read the row's own CP.
    struct BarState { var ivs: IVs; var count: Int; var confidence: Double; var atRowCp: Bool }

    /// The distinct bar states of a row's readings. Readings below `settledBarsConfidence` count: the state the solver should have kept is often held by readings at 0.696 while one
    /// reading at 0.79 won the vote (Togepi, Combee, Axew), and the fit test in `chooseByFit` is what guards against a transient one.
    static func barStates(_ row: ScanRow) -> [BarState] {
        var out = [BarState]()
        for f in row.frames {
            guard let text = f.ivs else { continue }
            let p = text.split(separator: "/").compactMap { Int($0) }
            guard p.count == 3 else { continue }
            let v = IVs(atk: p[0], def: p[1], hp: p[2]), conf = f.ivConfidence ?? 0
            if let i = out.firstIndex(where: { $0.ivs == v }) { out[i].count += 1; out[i].confidence = max(out[i].confidence, conf); out[i].atRowCp = out[i].atRowCp || f.cp == row.cp }
            else { out.append(BarState(ivs: v, count: 1, confidence: conf, atRowCp: f.cp == row.cp)) }
        }
        return out
    }

    /// Rule `ivs-chosen-by-fit`. A stay whose readings hold two or more bar states keeps one: today the vote (a 0.72 reading beats a 0.70 majority of three) or, when the
    /// states are held long enough, a cut into two Pokémon. A real Pokémon's bars always give its CP and HP at some level, so a state that gives them at none is a misread or a
    /// card sliding in. Each state is asked whether the row's CP and HP are reachable with exactly those bars: when EXACTLY ONE state is, the row is kept whole with it, solved exact,
    /// with `ivs-chosen-by-fit:<state>`. When none of the states fits the forms the screen name shows, the other forms of the species are asked (as `form-from-stats` does) and a
    /// state that fits exactly one of them at exactly one level is taken with that form. Two states that both fit are two real Pokémon (or one that cannot be told apart): nil, and the
    /// caller does what it did before. Same when none fits. The state taken must be held by at least two readings: one reading can be the previous card's bars on their way, and
    /// a transient value fitting the CP and HP by chance is too weak a reason to overrule the vote.
    static func chooseByFit(_ row: ScanRow, readings: [FrameReading], labelIndex: [String: Int], engine: CoreEngine, gameMaster: GameMaster?) -> (row: ScanRow, detail: String)? {
        guard let gm = gameMaster, let hp = row.hp, row.cp > 0, !row.flags.contains("name-low-confidence") else { return nil }
        let states = barStates(row)
        guard states.count >= 2 else { return nil }
        // Bars that change WITH the CP read are two Pokémon (Staraptor CP 1958 with 12/11/13 beside CP 1954 with 12/11/12, joined because the reads are one digit apart): the row's CP says
        // nothing about a state none of whose readings had it.
        guard states.allSatisfy(\.atRowCp) else { return nil }
        let screen = screenIds(row, readings: readings, labelIndex: labelIndex)
        func screenFits(_ v: IVs) -> [String] { screen.filter { id in gm.byId[id]?.baseStats.map { !exactLevels($0, cp: row.cp, hp: hp, ivs: v).isEmpty } == true } }
        let fitting = states.filter { !screenFits($0.ivs).isEmpty }
        var chosen: IVs, ids: [String], altForm: String? = nil
        if fitting.count == 1 {
            guard fitting[0].count >= 2 else { return nil }
            chosen = fitting[0].ivs; ids = screenFits(chosen)
        } else if fitting.isEmpty {
            let alts = alternativeForms(of: screen, gameMaster: gm)
            let pairs = states.flatMap { s in alts.map { (s.ivs, $0, exactLevels($0.stats, cp: row.cp, hp: hp, ivs: s.ivs)) } }.filter { !$0.2.isEmpty }
            guard pairs.count == 1, pairs[0].2.count == 1, states.first(where: { $0.ivs == pairs[0].0 })!.count >= 2 else { return nil }
            chosen = pairs[0].0; ids = [pairs[0].1.id]; altForm = pairs[0].1.id
        } else { return nil }
        guard let solved = solvedRow(row, speciesIds: ids, cp: row.cp, ivs: chosen, engine: engine) else { return nil }
        var fixed = adopting(solved, into: row, ivsRead: chosen)
        let key = "\(chosen.atk)/\(chosen.def)/\(chosen.hp)"
        fixed.flags.append("ivs-chosen-by-fit:\(key)")
        if let altForm { fixed.flags.append("form-from-stats:\(altForm)") }
        let others = states.filter { $0.ivs != chosen }.map { "\($0.ivs.atk)/\($0.ivs.def)/\($0.ivs.hp) x\($0.count)" }.joined(separator: ", ")
        return (fixed, "\(row.display) CP \(row.cp): bars \(key) x\(states.first { $0.ivs == chosen }!.count) fit the CP and HP, \(others) do not\(altForm.map { " (as \($0))" } ?? ""): kept as one Pokemon with \(key)")
    }

    /// `chooseByFit` for the rows the solver did not take exactly whose readings hold more than one bar state and that were not cut by `splitByBars` (the cut chooses for itself).
    /// Only when the state that fits is not the one the row already has: then the row has the form it needs and `form-from-stats` (run last) says so.
    static func chooseBarsByFit(_ scan: ScanResult, readings: [FrameReading], engine: CoreEngine, gameMaster: GameMaster?) -> (scan: ScanResult, marks: [(label: String, detail: String)]) {
        var labelIndex = [String: Int]()
        for (i, r) in readings.enumerated() { if let f = r.frame, labelIndex[f] == nil { labelIndex[f] = i } }
        var rows = scan.rows, marks = [(label: String, detail: String)]()
        for (n, row) in rows.enumerated() where row.solveStatus != "exact" {
            guard let fit = chooseByFit(row, readings: readings, labelIndex: labelIndex, engine: engine, gameMaster: gameMaster), fit.row.ivsRead != row.ivsRead else { continue }
            rows[n] = fit.row
            marks.append((row.frames.first?.frame ?? "", fit.detail))
        }
        guard !marks.isEmpty else { return (scan, []) }
        return (ScanResult(rows: rows, review: rows.filter { !$0.flags.isEmpty }.map(reviewEntry), unmatched: scan.unmatched), marks)
    }

    /// Rule `form-from-stats`. The game shows a regional form's bare name ("Meowth" for a Galarian Meowth), so the read bars fit no level of the Kanto stats and the solver gives up
    /// (`no-level-fits`) or offers nearby IV sets (`ambiguous-ivs`). A row the solver did not take exactly, with HP and settled bars read, is tried against the other forms of its species
    /// (`alternativeForms`): when EXACTLY ONE of them gives this CP and HP with exactly these bars, and at exactly one level, the row is that form. Zero or several: nothing changes.
    /// Run last, on the finished rows: it changes one row's values and flags and never its place or its frames.
    static func formFromStats(_ scan: ScanResult, readings: [FrameReading], engine: CoreEngine, gameMaster: GameMaster?) -> (scan: ScanResult, changes: [(label: String, detail: String)]) {
        guard let gm = gameMaster else { return (scan, []) }
        var labelIndex = [String: Int]()
        for (i, r) in readings.enumerated() { if let f = r.frame, labelIndex[f] == nil { labelIndex[f] = i } }
        var rows = scan.rows, changes = [(label: String, detail: String)]()
        for (n, row) in rows.enumerated() {
            guard ["none", "ambiguous", "corrected"].contains(row.solveStatus), let hp = row.hp, let read = row.ivsRead, row.cp > 0,
                  !row.flags.contains("bars-unsettled"), !row.flags.contains("name-low-confidence") else { continue }
            let fits = alternativeForms(of: screenIds(row, readings: readings, labelIndex: labelIndex), gameMaster: gm)
                .map { ($0, exactLevels($0.stats, cp: row.cp, hp: hp, ivs: read)) }.filter { !$0.1.isEmpty }
            guard fits.count == 1, fits[0].1.count == 1, let solved = solvedRow(row, speciesIds: [fits[0].0.id], cp: row.cp, ivs: read, engine: engine) else { continue }
            var fixed = adopting(solved, into: row, ivsRead: read)
            fixed.flags.append("form-from-stats:\(fits[0].0.id)")
            rows[n] = fixed
            changes.append((row.frames.first?.frame ?? "", "\(row.display) CP \(row.cp): the bars \(read.atk)/\(read.def)/\(read.hp) fit no level of \(row.speciesId) and fit \(fits[0].0.id) at level \(solved.level.map { String($0) } ?? "?") only"))
        }
        guard !changes.isEmpty else { return (scan, []) }
        return (ScanResult(rows: rows, review: rows.filter { !$0.flags.isEmpty }.map(reviewEntry), unmatched: scan.unmatched), changes)
    }
}
