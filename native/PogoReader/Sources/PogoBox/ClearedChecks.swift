import Foundation
import PogoReader

extension BoxMerge {
    /// The scanned rows whose `no-level-fits` check the answers cleared: a part-read question (`partialRead`) on a row carrying that flag, answered "it is the saved one" (the row only
    /// marks the saved entry seen, nothing of the row is written) or "leave it out". Answered "It is new" the row is added with its misread CP, and unanswered it is still open, so
    /// neither clears. Other kinds of question are never cleared here. Only the `no-level-fits` flag is cleared; a row's other check flags stay (`rowsToCheck`).
    public static func clearedChecks(_ plan: Plan, resolutions: [Int: Resolution]) -> Set<Int> {
        var out = Set<Int>()
        for u in plan.unsure where u.kind == .partialRead && plan.scanned.indices.contains(u.scanned) && hasNoLevelFits(plan.scanned[u.scanned]) {
            switch resolutions[u.scanned] {
            case .leaveOut?: out.insert(u.scanned)
            case .existing(let id)?: if u.candidates.contains(id), onlyMarksSeen(plan, u, id) { out.insert(u.scanned) }
            case .new?, nil: break
            }
        }
        return out
    }

    /// The positions in `plan.scanned` that still need a check in the game after the answers: every row with a check flag (`ScanRow.needsCheck`), less those whose only check flag
    /// was the `no-level-fits` one that `clearedChecks` cleared. With no answers this is every `needsCheck` row, so the number the answers cleared is the difference.
    public static func rowsToCheck(_ plan: Plan, resolutions: [Int: Resolution]) -> [Int] {
        let cleared = clearedChecks(plan, resolutions: resolutions)
        return plan.scanned.indices.filter { i in
            let r = plan.scanned[i]
            guard cleared.contains(i) else { return r.needsCheck }
            return r.checkFlags.contains { $0 != "no-level-fits" && !$0.hasPrefix("no-level-fits:") }
        }
    }
}
