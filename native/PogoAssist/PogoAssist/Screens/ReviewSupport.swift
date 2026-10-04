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

/// What the Review screen works out once per render from the review: the merge's plan, the saved entries by id, the question groups and the counts.
struct ReviewContext {
    let review: AppModel.Review
    let plan: BoxMerge.Plan
    let saved: [String: BoxEntry]
    let gm: GameMaster?
    let groups: [BoxMerge.QuestionGroup]
    let ending: ScanEnding

    init(_ review: AppModel.Review) {
        self.review = review
        plan = review.plan
        saved = Dictionary(review.base.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        gm = try? GameMaster.bundled()
        groups = BoxMerge.questionGroups(review.plan, saved: review.base, gameMaster: gm)
        ending = ScanEnding.of(review)
    }

    var total: Int { plan.unsure.count }
    var answered: Int { plan.unsure.filter { review.resolutions[$0.scanned] != nil }.count }
    var left: Int { total - answered }
    func unsure(_ scanned: Int) -> BoxMerge.Unsure? { plan.unsure.first { $0.scanned == scanned } }
    func question(_ scanned: Int) -> ReviewQuestion? { unsure(scanned).map { ReviewWording.question($0, plan: plan, saved: saved, gm: gm) } }
    func resolution(_ scanned: Int) -> BoxMerge.Resolution? { review.resolutions[scanned] }
    func groupKey(_ g: BoxMerge.QuestionGroup) -> String { "\(g.kind.rawValue)-\(g.members.first ?? -1)" }

    /// The rows that still need a look in the game once the answers are counted, and how many the answers cleared.
    var toCheck: [Int] { BoxMerge.rowsToCheck(plan, resolutions: review.resolutions) }
    var clearedByAnswers: Int { max(0, BoxMerge.rowsToCheck(plan, resolutions: [:]).count - toCheck.count) }
    var goneReport: BoxMerge.GoneReport { BoxMerge.goneReport(plan, resolutions: review.resolutions) }

    /// One search for every question still open.
    var openSearch: (count: Int, text: String?) {
        let open = plan.unsure.filter { review.resolutions[$0.scanned] == nil }
        return (open.count, GameSearch.text(open.map { GameSearch.part(for: $0, row: plan.scanned[$0.scanned], saved: saved) }))
    }
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

    /// The groups of the rows that still need a check, in the design's order, with the empty ones left out.
    static func groups(_ plan: BoxMerge.Plan, resolutions: [Int: BoxMerge.Resolution]) -> [ReviewCheckGroup] {
        let cleared = BoxMerge.clearedChecks(plan, resolutions: resolutions)
        var byReason = [Reason: [Int]]()
        for i in BoxMerge.rowsToCheck(plan, resolutions: resolutions) {
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
