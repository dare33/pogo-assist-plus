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
