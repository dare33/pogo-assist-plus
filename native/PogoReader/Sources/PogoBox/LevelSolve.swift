import Foundation
import PogoReader

/// After a hand correction: work out the level and power-up dust again for the corrected CP, HP and IVs by running the
/// project's JavaScript solver, the way `Refine` solves a hidden-CP row (the Pokémon's values go in as readings of three
/// frames and `finish` is run on them).
public enum LevelSolve {
    public enum Outcome: Equatable {
        /// Level, top of the level range, dust, and the flags the solver added (`level-ambiguous:…`).
        case fits(level: Double, levelMax: Double, dust: Int?, flags: [String])
        /// No level makes the CP, HP and IVs agree for this species.
        case noFit
        /// The solver could not be run or gave no single row; the entry is left as it is.
        case unavailable(String)
    }

    public static func solve(_ row: ScanRow, engine: CoreEngine) -> Outcome {
        guard let ivs = row.ivs else { return .unavailable("no IVs to solve with") }
        var frames = [FrameReading]()
        for i in 0..<3 {
            var f = FrameReading(frame: "s\(i + 1)", time: Double(i) * 0.25)
            f.cp = row.cp; f.cpText = String(row.cp); f.cpReads = [row.cp]
            f.name = row.display; f.nameText = row.display; f.nameConfidence = 1; f.nameWeak = false; f.nameAttached = false
            f.speciesIds = [row.speciesId]
            if let hp = row.hp { f.hp = HP(current: hp, max: hp); f.hpText = "\(hp) / \(hp) HP" }
            f.ivs = ivs; f.ivConfidence = 1
            frames.append(f)
        }
        do {
            let result = try engine.finish(readings: frames)
            guard result.rows.count == 1, let r = result.rows.first else { return .unavailable("the solver gave \(result.rows.count) rows") }
            // "exact" is the only answer where the IVs as typed fit; "corrected" means the solver changed them to make some level fit.
            guard r.solveStatus == "exact", r.ivs == ivs, let level = r.level else { return .noFit }
            return .fits(level: level, levelMax: r.levelMax ?? level, dust: r.dust, flags: r.flags.filter { $0.hasPrefix("level-ambiguous") })
        } catch { return .unavailable("\(error.localizedDescription)") }
    }

    /// The entry with level, range and dust from the solver, or the `no-level-fits` flag (and no level) when nothing fits.
    /// The person's values are kept either way. `notice` is a plain sentence for the person when something needs saying.
    public static func apply(to e: BoxEntry, engine: CoreEngine) -> (entry: BoxEntry, notice: String?) {
        guard e.row.ivs != nil else { return (e, nil) }
        var out = e
        switch solve(e.row, engine: engine) {
        case .fits(let level, let max, let dust, let flags):
            out.row.level = level; out.row.levelMax = max; out.row.dust = dust
            out.row.flags.removeAll { $0.hasPrefix("no-level-fits") || $0.hasPrefix("level-ambiguous") }
            out.row.flags += flags
            if out.row.solveStatus == "hand" { out.row.solveStatus = "exact" }
            return (out, nil)
        case .noFit:
            out.row.level = nil; out.row.levelMax = nil; out.row.dust = nil
            if !out.row.flags.contains("no-level-fits") { out.row.flags.append("no-level-fits") }
            return (out, "No level fits CP \(e.row.cp), HP \(e.row.hp.map(String.init) ?? "unknown") and IVs \(e.row.ivs!.atk)/\(e.row.ivs!.def)/\(e.row.ivs!.hp) for \(e.row.title). Your values are saved and the Pokémon is marked for a check. One of them is probably misread.")
        case .unavailable(let why):
            return (e, "Your values are saved, but the level could not be worked out again (\(why)). The old level is kept.")
        }
    }
}
