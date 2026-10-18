import SwiftUI
import PogoBox
import PogoReader

/// How the scan ended, as far as the app really knows. The outcome line says only what is known; anything else is plain "Scan finished".
enum ScanEnding: Equatable {
    case listEnd, longPause, byPerson, unknown

    /// A scan reviewed just after it was made knows from the broadcast's own flags (`Review`); a saved scan read again knows from the end markers its replay log carries.
    static func of(_ r: AppModel.Review) -> ScanEnding {
        if r.endedAtListEnd { return .listEnd }
        if r.stoppedByTimeout { return .longPause }
        if r.stoppedByPerson { return .byPerson }
        guard let plan = r.reread else { return .unknown }
        var ending = ScanEnding.unknown
        for line in ReplayLog.lines(in: plan.replayURL) {
            switch line {
            case .end: if ending == .unknown { ending = .listEnd }
            case .stoppedByPerson: ending = .byPerson
            case .pauseTimedOut: ending = .longPause
            default: break
            }
        }
        return ending
    }

    var headline: String {
        switch self {
        case .listEnd: return "Scan finished at the end of your list"
        case .longPause: return "Scan stopped after a long pause"
        case .byPerson: return "You ended the scan"
        case .unknown: return "Scan finished"
        }
    }
}

enum ReviewFormat {
    /// "34 min", or seconds for a scan under a minute.
    static func readIn(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s < 60 ? "\(s) s" : "\(Int((seconds / 60).rounded())) min"
    }
    static func count(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? "1 \(one)" : "\(n.formatted()) \(many)" }
}

/// A value worked out for one key and kept until the key changes (the answers, say), so a screen's body does not redo it on every evaluation.
private struct Memo<K: Equatable, V> {
    private var key: K?
    private var value: V?
    mutating func get(_ k: K, _ make: () -> V) -> V {
        if let key, key == k, let value { return value }
        let v = make()
        key = k; value = v
        return v
    }
}

/// What the three review screens (result, To check, Not seen) derive from the review, kept for as long as the review's plan is the same (`Review.planToken`):
/// the saved entries by id (up to 15,000), the question groups and how the scan ended (which reads the replay log) once; the lists that follow the answers
/// are kept for the answers they were worked out for. Nothing here changes behaviour: it is the same values, worked out once instead of on every render.
@MainActor
final class ReviewDerived {
    private static var current: ReviewDerived?
    static func of(_ review: AppModel.Review) -> ReviewDerived {
        if let c = current, c.planToken == review.planToken { return c }
        let d = ReviewDerived(review)
        current = d
        return d
    }

    let planToken: UUID
    let saved: [String: BoxEntry]
    let gm: GameMaster?
    let groups: [BoxMerge.QuestionGroup]
    let ending: ScanEnding
    /// Runs of cards that failed the same way (a hidden CP, unread bars), found once per review: the scan does not change.
    let stretches: [TroubleStretch]
    /// The rows with a check before any answer, to count what the answers cleared.
    private let rowsWithoutAnswers: Int
    private let plan: BoxMerge.Plan

    private init(_ review: AppModel.Review) {
        planToken = review.planToken
        plan = review.plan
        saved = Dictionary(review.base.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let gm = try? GameMaster.bundled()
        self.gm = gm
        groups = BoxMerge.questionGroups(review.plan, saved: review.base, gameMaster: gm)
        ending = ScanEnding.of(review)
        stretches = TroubleStretches.find(review.outcome.scan)
        rowsWithoutAnswers = BoxMerge.rowsToCheck(review.plan, resolutions: [:]).count
    }

    private var checkMemo = Memo<[Int: BoxMerge.Resolution], (rows: [Int], cleared: Int, groups: [ReviewCheckGroup])>()
    private var goneMemo = Memo<[Int: BoxMerge.Resolution], BoxMerge.GoneReport>()
    private struct PreviewKey: Equatable { var resolutions: [Int: BoxMerge.Resolution]; var marked: Set<String> }
    private var previewMemo = Memo<PreviewKey, SavePreview>()

    /// The rows still to check once the answers are counted, those answered "Don't include" left out (they will not be in the box), the number the answers
    /// cleared (`BoxMerge.clearedChecks`), and the rows by reason.
    func check(_ resolutions: [Int: BoxMerge.Resolution]) -> (rows: [Int], cleared: Int, groups: [ReviewCheckGroup]) {
        checkMemo.get(resolutions) {
            let engine = BoxMerge.rowsToCheck(plan, resolutions: resolutions)
            let cleared = BoxMerge.clearedChecks(plan, resolutions: resolutions)
            let leftOut = Set(plan.unsure.filter { resolutions[$0.scanned] == .leaveOut }.map(\.scanned))
            let rows = engine.filter { !leftOut.contains($0) }
            return (rows, max(0, rowsWithoutAnswers - engine.count), ReviewCheckGroup.groups(plan, rows: rows, cleared: cleared))
        }
    }

    func goneReport(_ resolutions: [Int: BoxMerge.Resolution]) -> BoxMerge.GoneReport {
        goneMemo.get(resolutions) { BoxMerge.goneReport(plan, resolutions: resolutions) }
    }

    func preview(_ resolutions: [Int: BoxMerge.Resolution], marked: Set<String>) -> SavePreview {
        previewMemo.get(PreviewKey(resolutions: resolutions, marked: marked)) {
            SavePreview.make(plan, resolutions: resolutions, saved: saved, gone: goneReport(resolutions).gone, marked: marked, gm: gm)
        }
    }
}

/// What Save will do with the scan's Pokémon, given the answers and marks so far. It follows the engine's own decisions: `plan.new`, `plan.updated` and `plan.same`, and for
/// each answered question `BoxMerge.effect` (the function `apply` follows), so what the panel counts is what `apply` writes. A question not answered yet counts for nothing.
struct SavePreview {
    struct Change { var scanned: Int; var savedId: String; var reason: BoxMerge.UpdateReason }
    struct Match { var scanned: Int; var savedId: String; var mega: Bool; var effect: BoxMerge.Effect? }
    /// Positions in `plan.scanned` that Save adds.
    var newRows: [Int]
    var updated: [Change]
    var same: [Match]
    /// Saved entries Save removes: the Not seen entries that are marked, and the Mega entries a "Same Pokémon" answer joins into their base entry.
    var removed: Set<String>
    var markedRemoved: Int
    var joined: Int
    /// Questions with no answer yet.
    var open: Int

    static func make(_ plan: BoxMerge.Plan, resolutions: [Int: BoxMerge.Resolution], saved: [String: BoxEntry], gone: [String], marked: Set<String>, gm: GameMaster?) -> SavePreview {
        var new = plan.new
        var updated = plan.updated.map { Change(scanned: $0.scanned, savedId: $0.savedId, reason: $0.reason) }
        var same = plan.same.map { Match(scanned: $0.scanned, savedId: $0.savedId, mega: $0.mega, effect: nil) }
        var joins = Set<String>(), open = 0
        for u in plan.unsure {
            guard let answer = resolutions[u.scanned] else { open += 1; continue }
            switch answer {
            case .leaveOut: break
            case .new: if u.kind != .megaPair { new.append(u.scanned) }
            case .existing(let id):
                guard let e = saved[id] else { break }
                if u.kind == .megaPair {
                    // `apply`: only "this one" on the base entry joins, and only when the Mega entry is there.
                    if id == u.candidates.first, u.candidates.count == 2, saved[u.candidates[1]] != nil { joins.insert(u.candidates[1]) }
                    break
                }
                let fx = BoxMerge.effect(plan, u, candidate: e, gameMaster: gm)
                switch fx {
                case .joinsMegaPair: break
                case .replacesValues, .replacesIVs: updated.append(Change(scanned: u.scanned, savedId: id, reason: reason(of: u.kind)))
                case .seenOnly, .seenAsMega, .keepsIVsAndFlags: same.append(Match(scanned: u.scanned, savedId: id, mega: fx == .seenAsMega, effect: fx))
                }
            }
        }
        let markedGone = Set(gone).intersection(marked)
        return SavePreview(newRows: new.sorted(), updated: updated, same: same, removed: markedGone.union(joins), markedRemoved: markedGone.count, joined: joins.count, open: open)
    }

    private static func reason(of kind: BoxMerge.Unsure.Kind) -> BoxMerge.UpdateReason {
        switch kind {
        case .poweredUp: return .poweredUp
        case .evolved: return .evolved
        case .megaToBase: return .megaToBase
        default: return .chosen
        }
    }
}

/// What the Review screen works out from the review: the merge's plan, the saved entries by id, the question groups and the counts. The costly parts
/// (`ReviewDerived`) are kept per review and per set of answers, not rebuilt on every render.
@MainActor
struct ReviewContext {
    let review: AppModel.Review
    let plan: BoxMerge.Plan
    private let derived: ReviewDerived

    init(_ review: AppModel.Review) {
        self.review = review
        plan = review.plan
        derived = ReviewDerived.of(review)
    }

    var saved: [String: BoxEntry] { derived.saved }
    var gm: GameMaster? { derived.gm }
    var groups: [BoxMerge.QuestionGroup] { derived.groups }
    var ending: ScanEnding { derived.ending }
    var stretches: [TroubleStretch] { derived.stretches }

    var total: Int { plan.unsure.count }
    var answered: Int { plan.unsure.filter { review.resolutions[$0.scanned] != nil }.count }
    var left: Int { total - answered }
    func unsure(_ scanned: Int) -> BoxMerge.Unsure? { plan.unsure.first { $0.scanned == scanned } }
    func question(_ scanned: Int) -> ReviewQuestion? { unsure(scanned).map { ReviewWording.question($0, plan: plan, saved: saved, gm: gm) } }
    func resolution(_ scanned: Int) -> BoxMerge.Resolution? { review.resolutions[scanned] }
    func groupKey(_ g: BoxMerge.QuestionGroup) -> String { "\(g.kind.rawValue)-\(g.members.first ?? -1)" }

    /// The rows that still need a look in the game once the answers are counted (rows answered "Don't include" are not in the list: they will not be in the box),
    /// and how many the answers cleared.
    var toCheck: [Int] { derived.check(review.resolutions).rows }
    var clearedByAnswers: Int { derived.check(review.resolutions).cleared }
    var checkGroups: [ReviewCheckGroup] { derived.check(review.resolutions).groups }
    var goneReport: BoxMerge.GoneReport { derived.goneReport(review.resolutions) }
    var savePreview: SavePreview { derived.preview(review.resolutions, marked: review.markedForRemoval) }

    /// One search for every question still open: how many it covers, how many it cannot (no CP or HP to look for), and the text (nil when it covers none).
    var openSearch: (covered: Int, notCovered: Int, text: String?) {
        let open = plan.unsure.filter { review.resolutions[$0.scanned] == nil }
        let parts = open.map { GameSearch.part(for: $0, row: plan.scanned[$0.scanned], saved: saved) }
        let covered = GameSearch.covered(parts)
        return (covered, open.count - covered, GameSearch.text(parts))
    }

    /// What Save does with the row at this position of the scan, for the Find sheet (see `SaveFate`).
    func fate(of scanned: Int) -> SaveFate {
        if plan.new.contains(scanned) || plan.updated.contains(where: { $0.scanned == scanned }) { return .values }
        if plan.same.contains(where: { $0.scanned == scanned }) || plan.partMatches.contains(where: { $0.scanned == scanned }) { return .notSaved }
        guard let u = unsure(scanned) else { return .unknown }
        switch resolution(scanned) {
        case nil: return .undecided
        case .leaveOut?: return .notSaved
        case .new?: return u.kind == .megaPair ? .notSaved : .values
        case .existing(let id)?:
            guard u.kind != .megaPair, let e = saved[id] else { return .notSaved }
            switch BoxMerge.effect(plan, u, candidate: e, gameMaster: gm) {
            case .replacesValues, .replacesIVs: return .values
            default: return .notSaved
            }
        }
    }
}

/// Whether the values a scanned row read reach the box when Save runs (decided from what `BoxMerge.apply` does with the row).
enum SaveFate {
    /// Saved as a new Pokémon, or written onto the saved one it matches.
    case values
    /// Matched to a saved Pokémon that is only marked as seen, joined or left alone; or not included.
    case notSaved
    /// Its question has no answer yet.
    case undecided
    /// The plan has no decision for this row.
    case unknown
}

// MARK: To check groups (design 1d)

/// The reasons a row is in "To check", grouped as the design groups them. A row goes where its first remaining check flag says.
struct ReviewCheckGroup: Identifiable {
    enum Reason: CaseIterable {
        case lookAlike, ivSets, cpWorkedOut, twins, noLevelFits, other
        var title: String {
            switch self {
            case .lookAlike: return "Look-alike pairs"
            case .ivSets: return "More than one IV set fits"
            case .cpWorkedOut: return "CP worked out"
            case .twins: return "Two identical in a row"
            case .noLevelFits: return "No level fits"
            case .other: return "Other"
            }
        }
        /// The Find sheet's tag.
        var tag: String {
            switch self {
            case .lookAlike: return "Tell them apart"
            case .ivSets: return "Check the IVs"
            case .cpWorkedOut: return "Check the CP"
            case .twins: return "Count them"
            case .noLevelFits: return "Check the values"
            case .other: return "Check"
            }
        }
        var sub: String? { self == .lookAlike ? "Same name and CP, bars differ" : nil }
        var flags: [String] {
            switch self {
            case .lookAlike: return ["split-by-bars"]
            case .ivSets: return ["ambiguous-ivs"]
            case .cpWorkedOut: return ["cp-computed", "cp-recovered"]
            case .twins: return ["same-as-previous", "split-by-timing"]
            case .noLevelFits: return ["no-level-fits"]
            case .other: return []
            }
        }
    }
    var reason: Reason
    /// Positions in `plan.scanned`.
    var rows: [Int]
    var id: Reason { reason }

    static func reason(of flag: String) -> Reason {
        for r in Reason.allCases where r.flags.contains(where: { flag == $0 || flag.hasPrefix($0 + ":") || flag.hasPrefix($0 + "-") }) { return r }
        return .other
    }

    /// The groups of these rows (the ones that still need a check, `ReviewDerived.check`), in the design's order, with the empty ones left out.
    static func groups(_ plan: BoxMerge.Plan, rows: [Int], cleared: Set<Int>) -> [ReviewCheckGroup] {
        var byReason = [Reason: [Int]]()
        for i in rows {
            let flags = remainingFlags(plan.scanned[i], cleared: cleared.contains(i))
            byReason[flags.first.map(reason(of:)) ?? .other, default: []].append(i)
        }
        return Reason.allCases.compactMap { r in byReason[r].map { ReviewCheckGroup(reason: r, rows: $0) } }
    }

    /// A row's check flags, less the `no-level-fits` one when the answers cleared it.
    static func remainingFlags(_ r: ScanRow, cleared: Bool) -> [String] {
        cleared ? r.checkFlags.filter { $0 != "no-level-fits" && !$0.hasPrefix("no-level-fits:") } : r.checkFlags
    }

    /// The line under a row's name.
    static func sub(_ reason: Reason, _ r: ScanRow) -> String {
        switch reason {
        case .lookAlike: return ReviewWording.ivsText(r.ivs)
        case .ivSets: return "More than one set of IVs fits"
        case .cpWorkedOut: return r.hp.map { "From HP \($0) and the bars" } ?? "From the bars"
        case .twins: return "Check you own two"
        case .noLevelFits: return "Check the CP, HP and IVs"
        case .other: return r.checkFlags.first.map(FlagInfo.explain) ?? "Check it in the game"
        }
    }
}

// MARK: shared pieces

/// A Copy button that puts a search on the pasteboard and shows the "Copied" toast.
struct CopySearchButton: View {
    let text: String
    var label = "Copy search"
    var style: PillStyle = .tint
    @Environment(\.showToast) private var showToast
    var body: some View {
        PillButton(label, systemImage: "doc.on.doc", style: style) {
            UIPasteboard.general.string = text
            showToast("Copied")
        }
        .accessibilityValue(text)
    }
}

/// The 38 pt rounded back button and a centred title, for the pages pushed from the result.
struct ReviewTopBar: View {
    let title: String
    var onBack: (() -> Void)?
    var account: String?
    var body: some View {
        Group {
            if let account {
                // The account on the left and the title on the right, so neither sits on the other at a large text size.
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        AccountMonogram(name: account, size: 28)
                        Text(account).font(.figtree(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.ink).lineLimit(1)
                    }
                    .padding(.leading, 4).padding(.trailing, 12).frame(minHeight: 36)
                    .background(Capsule().fill(Theme.surface)).panelShadow()
                    .accessibilityElement(children: .combine).accessibilityLabel("Account, \(account)")
                    .layoutPriority(0)
                    Spacer(minLength: 0)
                    titleText.layoutPriority(1)
                }
            } else {
                ZStack {
                    titleText
                    HStack { if let onBack { IconButton(systemImage: "chevron.left", kind: .floating, label: "Back", action: onBack) }; Spacer() }
                }
            }
        }
        .padding(.horizontal, 18).frame(minHeight: 52)
    }

    private var titleText: some View {
        Text(title).paText(.rowTitle).fontWeight(.bold).foregroundStyle(Theme.ink).lineLimit(1).accessibilityAddTraits(.isHeader)
    }
}

/// The inline reveal used under an InsetRow: rows in a panel that appear when the row above is tapped.
struct RevealList<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 8) { content }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface2)
    }
}
