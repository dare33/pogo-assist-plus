import Foundation
import PogoReader
import PogoImport

/// From screenshot readings to the same `ScanPipeline.Outcome` the review screen takes, built beside `ScanPipeline` rather than through it: `ScanPipeline.process` is about time
/// (a replay log, repeated frames voted into a card, swipe ticks, pauses, pace) and none of that exists for a picture. Each screenshot was read once (`StillReader`); here it is
/// solved on its own by the project's JavaScript `finish` (one reading, one row, so no screenshot is ever grouped with, voted against or dropped as a neighbour of another), the
/// rows are put in order, and `BoxMerge` does the rest exactly as for a scan: matching to the saved box, the questions, hand corrections kept.
public enum StillImport {
    /// What the solver made of one reading.
    public enum Solved: Equatable {
        case row(ScanRow)
        /// The reading fits a Pokémon but the bars give no one set of IVs (ambiguous, or the solver found none).
        case ivsMissing(String)
        /// CP, HP and bars fit no level of any Pokémon of that name: one of them was misread.
        case unreadable(String)
    }

    /// One screenshot reading to at most one row. A row is returned only when it has IVs: a Pokémon with no IVs is not added to a box from a picture (see `ScreenshotImporter`).
    public static func solve(_ reading: FrameReading, engine: CoreEngine) -> Solved {
        guard let result = try? engine.finish(readings: [reading]), result.rows.count == 1, var row = result.rows.first else {
            return .unreadable("The values read could not be turned into one Pokémon.")
        }
        if row.ivs == nil {
            // `none`: the read bars fit no level at that CP and HP (the JS flags the row `no-level-fits`); `ambiguous`: several sets of IVs fit and the row keeps none.
            if row.solveStatus == "none" { return .unreadable("The CP, HP and appraisal bars do not fit any level of that Pokémon, so one of them was misread. Take the screenshot again.") }
            return .ivsMissing("The appraisal bars did not give one set of IVs for this CP and HP.")
        }
        row.index = 1
        return .row(row)
    }

    /// Rows for the review, in the order given, numbered from 1. Each row's single frame label is the item's id, so a row can always be traced to its screenshot.
    static func numbered(_ rows: [ScanRow]) -> [ScanRow] {
        var out = rows
        for i in out.indices { out[i].index = i + 1 }
        return out
    }

    /// The review's flagged list, as `finish` builds it for a scan.
    static func reviewEntries(_ rows: [ScanRow]) -> [ReviewEntry] {
        rows.filter { !$0.flags.isEmpty }.map {
            ReviewEntry(index: $0.index, name: $0.name, cp: $0.cp, hp: $0.hp, ivs: $0.ivs, ivsRead: $0.ivsRead, ivsGuess: $0.ivsGuess, level: $0.level, levelMax: $0.levelMax,
                        flags: $0.flags, frames: $0.frames, clip: $0.clip, shadow: $0.shadow)
        }
    }

    /// What the review calls a scan: the rows, and the numbers it shows (a screenshot import has no frames, ticks, pace or duration).
    public static func outcome(rows: [ScanRow], screenshots: Int) -> ScanPipeline.Outcome {
        let numbered = numbered(rows)
        let scan = ScanResult(rows: numbered, review: reviewEntries(numbered), unmatched: [])
        return ScanPipeline.Outcome(scan: scan, readings: screenshots, ticks: 0, drops: 0, duration: 0, changes: [], notices: [], timings: ScanPipeline.Timings(), pace: nil, pauses: [])
    }

    /// The identity a retake or a twin would share: species and form, CP, HP and IVs all equal. NOT proof of the same Pokémon (the owner has genuine twins), which is why a match
    /// only holds the later one back for the person's say and never merges anything.
    struct Look: Hashable {
        var speciesId: String, cp: Int, hp: Int?, ivs: IVs?
        init(_ r: ScanRow) { speciesId = r.speciesId; cp = r.cp; hp = r.hp; ivs = r.ivs }
    }

    /// The species and IVs only: the same Pokémon before and after a power-up, or another one with the same IVs.
    struct SameIVs: Hashable {
        var speciesId: String, ivs: IVs?
        init(_ r: ScanRow) { speciesId = r.speciesId; ivs = r.ivs }
    }

    /// Items (in order) whose Pokémon looks like an earlier item's in the same batch: `repeatOf` is that earlier item's id. `rows` maps item id to its solved row; items that are a
    /// copy of another screenshot or have no row are not considered.
    public static func repeats(items: [ImportItem], rows: [String: ScanRow]) -> [String: String] {
        var firstLook = [Look: String](), firstIVs = [SameIVs: String](), out = [String: String]()
        for item in items where item.duplicateOf == nil {
            guard let row = rows[item.id] else { continue }
            let look = Look(row), same = SameIVs(row)
            if let earlier = firstLook[look] ?? firstIVs[same] { out[item.id] = earlier } else { firstLook[look] = item.id; firstIVs[same] = item.id }
        }
        return out
    }

    /// "Nickit, CP 212" for an item whose reading is kept.
    public static func title(of item: ImportItem) -> String? {
        guard let data = item.reading, let r = try? JSONDecoder().decode(FrameReading.self, from: data), let name = r.name else { return nil }
        return r.cp.map { "\(name), CP \($0)" } ?? name
    }

    static func decode(_ item: ImportItem) -> FrameReading? { item.reading.flatMap { try? JSONDecoder().decode(FrameReading.self, from: $0) } }
}
