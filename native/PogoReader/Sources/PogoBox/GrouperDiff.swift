import Foundation
import PogoReader

/// A diagnostic, not a gate: the package's streaming `LiveGrouper` (as the extension runs it) against the
/// refined JavaScript rows, for the same readings and swipe ticks. Rows are aligned in order by name + CP
/// (a longest common subsequence), so a row only one side has does not shift the rest.
/// Uses `LiveGrouper` exactly as it is; this file is the only place PogoBox touches it.
public struct GrouperDiff {
    public struct Pair { public var refined: ScanRow; public var live: LiveRow }

    public var refinedCount: Int
    public var liveCount: Int
    public var matched: [Pair]
    public var onlyRefined: [ScanRow]
    public var onlyLive: [LiveRow]
    public var hpDiffers: [Pair]
    public var ivsDiffers: [Pair]
    public var flagsDiffer: [Pair]

    /// Run `LiveGrouper` over `readings`, feeding each tick right before the first reading at or after its
    /// time (as `pogo-read` and the extension do), then compare with `refined`.
    public static func compute(refined: [ScanRow], readings: [FrameReading], ticks: [Double], species: SpeciesTable? = try? SpeciesTable.bundled()) -> GrouperDiff {
        compare(refined: refined, live: liveRows(readings: readings, ticks: ticks, species: species))
    }

    /// `LiveGrouper`'s rows for these readings and ticks (ticks fed right before the first reading at or after them).
    public static func liveRows(readings: [FrameReading], ticks: [Double], species: SpeciesTable? = try? SpeciesTable.bundled()) -> [LiveRow] {
        var grouper = LiveGrouper(species: species)
        let sorted = ticks.filter { $0.isFinite }.sorted()
        var next = 0
        for r in readings {
            if let t = r.time { while next < sorted.count, sorted[next] <= t { grouper.swipe(at: sorted[next]); next += 1 } }
            grouper.add(r)
        }
        grouper.finish()
        return grouper.rows
    }

    static func compare(refined: [ScanRow], live: [LiveRow]) -> GrouperDiff {
        func same(_ r: ScanRow, _ l: LiveRow) -> Bool { l.cp == r.cp && (l.name == r.display || l.name == r.name) }
        let n = refined.count, m = live.count
        var lcs = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lcs[i][j] = same(refined[i], live[j]) ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }
        var matched = [Pair](), onlyRefined = [ScanRow](), onlyLive = [LiveRow]()
        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, same(refined[i], live[j]) { matched.append(Pair(refined: refined[i], live: live[j])); i += 1; j += 1 }
            else if i < n, j == m || lcs[i + 1][j] >= lcs[i][j + 1] { onlyRefined.append(refined[i]); i += 1 }
            else { onlyLive.append(live[j]); j += 1 }
        }
        return GrouperDiff(refinedCount: n, liveCount: m, matched: matched, onlyRefined: onlyRefined, onlyLive: onlyLive,
                           hpDiffers: matched.filter { $0.refined.hp != $0.live.hp },
                           ivsDiffers: matched.filter { $0.refined.ivs != $0.live.ivs },
                           flagsDiffer: matched.filter { Set($0.refined.flags) != Set($0.live.flags) })
    }

    private static func ivText(_ v: IVs?) -> String { v.map { "\($0.atk)/\($0.def)/\($0.hp)" } ?? "?" }

    /// The comparison as text: counts, then every difference.
    public func report() -> String {
        var out = ["LiveGrouper vs refined JavaScript: refined \(refinedCount) rows, LiveGrouper \(liveCount) rows",
                   "  both (name + CP): \(matched.count); only refined: \(onlyRefined.count); only LiveGrouper: \(onlyLive.count)",
                   "  of the \(matched.count) shared: HP differs \(hpDiffers.count), IVs differ \(ivsDiffers.count), flags differ \(flagsDiffer.count)"]
        for r in onlyRefined { out.append("  only refined   #\(r.index) \(r.display) CP \(r.cp) HP \(r.hp.map(String.init) ?? "?") \(Self.ivText(r.ivs)) [\(r.flags.joined(separator: " "))]") }
        for l in onlyLive { out.append("  only LiveGrouper #\(l.index) \(l.name) CP \(l.cp.map(String.init) ?? "?") HP \(l.hp.map(String.init) ?? "?") \(Self.ivText(l.ivs)) [\(l.flags.joined(separator: " "))]") }
        for p in hpDiffers { out.append("  HP differs     \(p.refined.display) CP \(p.refined.cp): refined \(p.refined.hp.map(String.init) ?? "?"), live \(p.live.hp.map(String.init) ?? "?")") }
        for p in ivsDiffers { out.append("  IVs differ     \(p.refined.display) CP \(p.refined.cp): refined \(Self.ivText(p.refined.ivs)), live \(Self.ivText(p.live.ivs))") }
        for p in flagsDiffer { out.append("  flags differ   \(p.refined.display) CP \(p.refined.cp): refined [\(p.refined.flags.joined(separator: " "))], live [\(p.live.flags.joined(separator: " "))]") }
        return out.joined(separator: "\n")
    }
}
