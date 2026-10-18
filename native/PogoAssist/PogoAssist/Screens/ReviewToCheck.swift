import SwiftUI
import PogoBox
import PogoReader

/// "To check" (design v2 section 1d): the rows that still need a look in the game, by reason, each opening the Find sheet.
/// The scan is not saved yet, so there is no stored Pokémon to mark as checked or correct: the sheet is read-only here (see `FindSheet`).
struct ToCheckScreen: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 30
    let close: () -> Void
    @State private var showInfo = false
    @State private var find: FindTarget?

    struct FindTarget: Identifiable { var index: Int; var reason: ReviewCheckGroup.Reason; var id: Int { index } }

    var body: some View {
        if case .review(let review) = model.flow {
            content(ReviewContext(review))
        } else { Color.clear }
    }

    private func content(_ ctx: ReviewContext) -> some View {
        let plan = ctx.plan
        let groups = ctx.checkGroups
        let rows = groups.flatMap(\.rows)
        let parts = rows.map { GameSearch.part(row: plan.scanned[$0]) }
        let search = GameSearch.text(parts)
        let notCovered = parts.count - GameSearch.covered(parts)
        return VStack(spacing: 0) {
            ReviewTopBar(title: "To check", onBack: close)
            ScrollView {
                LazyVStack(spacing: Theme.Space.panelGap) {
                    Panel(padding: 20, spacing: 14) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(rows.count.formatted()).paText(.heroFigure).foregroundStyle(Theme.ink)
                            Text("to look at in the game").font(.figtree(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                            if notCovered > 0 { Text("\(notCovered) not in the search: no CP or HP to look for.").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted) }
                        }
                        .accessibilityElement(children: .combine)
                        HStack(spacing: 12) {
                            step("1")
                            Text("Copy one search for all").paText(.rowTitle).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
                            Button { withAnimation(reduceMotion ? nil : .snappy) { showInfo.toggle() } } label: {
                                Image(systemName: "info.circle").font(.figtree(18, .semibold)).foregroundStyle(Theme.muted).frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel("About this search")
                            if let search { CopyPill(text: search) }
                        }
                        if showInfo {
                            Text("The game will show these, plus a few others with the same names and CPs.").font(.figtree(13, .semibold, relativeTo: .footnote))
                                .foregroundStyle(Theme.bg).padding(.horizontal, 14).padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        HStack(spacing: 12) {
                            step("2")
                            Text("Paste it in the game's storage").paText(.rowTitle).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    ForEach(groups) { g in
                        VStack(spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(g.reason.title).font(.figtree(18, .heavy, relativeTo: .title3)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                                Spacer()
                                Text(g.rows.count.formatted()).font(.figtree(14, .bold, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.muted)
                            }
                            .padding(.horizontal, 6).padding(.top, 4)
                            Panel(padding: 0, spacing: 0) {
                                ForEach(Array(g.rows.enumerated()), id: \.element) { n, i in
                                    let r = plan.scanned[i]
                                    Button { find = FindTarget(index: i, reason: g.reason) } label: {
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text("\(r.title) · \(ReviewWording.cpText(r.cp))").paText(.rowTitle).foregroundStyle(Theme.ink)
                                                Text(ReviewCheckGroup.sub(g.reason, r)).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            Image(systemName: "magnifyingglass").font(.figtree(17, .bold)).foregroundStyle(Theme.orangeInk)
                                                .frame(width: 38, height: 38).background(Circle().fill(Theme.orangeTint)).accessibilityHidden(true)
                                        }
                                        .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 56).contentShape(Rectangle())
                                        .overlay(alignment: .top) { if n > 0 { Rectangle().fill(Theme.line).frame(height: 1) } }
                                    }
                                    .buttonStyle(PressStyle())
                                    .accessibilityLabel("\(r.title), \(ReviewWording.cpText(r.cp)). \(ReviewCheckGroup.sub(g.reason, r))")
                                    .accessibilityHint("Opens the search and the values read")
                                }
                            }
                        }
                    }
                    if rows.isEmpty {
                        Text("Nothing needs a check.").paText(.secondary).foregroundStyle(Theme.muted).padding(24)
                    }
                }
                .padding(.horizontal, Theme.Space.screen).padding(.top, 6).padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.bg.ignoresSafeArea())
        .sheet(item: $find) { t in
            let r = plan.scanned[t.index]
            FindSheet(row: r, reason: t.reason, fate: ctx.fate(of: t.index), flags: ReviewCheckGroup.remainingFlags(r, cleared: BoxMerge.clearedChecks(plan, resolutions: ctx.review.resolutions).contains(t.index)))
                .presentationDetents([.medium, .large]).presentationCornerRadius(Theme.Radius.sheet).presentationDragIndicator(.visible)
                .themeRoot()
        }
    }

    private func step(_ n: String) -> some View {
        Text(n).font(.figtree(14, .heavy)).foregroundStyle(Theme.orangeInk)
            .frame(width: circle, height: circle).background(Circle().fill(Theme.orangeTint)).accessibilityHidden(true)
    }
}

/// The small orange Copy pill (header steps).
struct CopyPill: View {
    let text: String
    @Environment(\.showToast) private var showToast
    var body: some View {
        Button { UIPasteboard.general.string = text; showToast("Copied") } label: {
            HStack(spacing: 6) { Image(systemName: "doc.on.doc"); Text("Copy") }
                .font(.figtree(14, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.orangeInk)
                .padding(.horizontal, 14).frame(minHeight: 36).background(Theme.orangeTint, in: Capsule())
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Copy search").accessibilityValue(text)
    }
}

/// The Find sheet: the Pokémon, the search for it, and the values the scan read. Read-only: the scanned Pokémon is not in the box yet, so there is nothing to mark as
/// checked or to correct until the scan is saved (then the Box page offers both).
struct FindSheet: View {
    let row: ScanRow
    let reason: ReviewCheckGroup.Reason
    let fate: SaveFate
    let flags: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).font(.figtree(26, .heavy, relativeTo: .title)).foregroundStyle(Theme.ink)
                        Text("\(ReviewWording.cpText(row.cp)) · \(ReviewWording.hpText(row.hp))").font(.figtree(17, .semibold, relativeTo: .body)).monospacedDigit().foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 8)
                    Chip(text: reason.tag, tone: .orange)
                    IconButton(systemImage: "xmark", kind: .neutral, label: "Close") { dismiss() }
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(flags, id: \.self) { Text(FlagInfo.explain($0)).font(.figtree(15, .regular, relativeTo: .subheadline)).foregroundStyle(Theme.muted) }
                }
                if let s = GameSearch.text([GameSearch.part(row: row)]) { SearchStrip(text: s, prominent: true) }
                VStack(alignment: .leading, spacing: 10) {
                    Text("IVS AS READ").font(.figtree(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.muted)
                    if let ivs = row.ivsRead ?? row.ivs { BarsView(ivs.atk, ivs.def, ivs.hp) } else { Text("IVs not read").paText(.secondary).foregroundStyle(Theme.muted) }
                }
                .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                if let note = fateNote { Text(note).paText(.secondary).foregroundStyle(Theme.muted) }
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 24)
        }
        .background(Theme.surface.ignoresSafeArea())
    }

    /// What Save does with this row, from `BoxMerge.apply`'s own decision for it (`ReviewContext.fate`).
    private var fateNote: String? {
        switch fate {
        case .values: return "After you save, you can mark this one as checked or fix a value from its page in the box."
        case .notSaved: return "This one is not saved to the box as read: its values are not written, so there is nothing to confirm there."
        case .undecided: return "What is saved for this one depends on your answer to its question."
        case .unknown: return nil
        }
    }
}
