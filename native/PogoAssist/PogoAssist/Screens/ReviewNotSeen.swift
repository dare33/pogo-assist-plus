import SwiftUI
import PogoBox
import PogoReader

/// "Not seen in this scan" (design v2 section 1e): the saved Pokémon a full scan did not see. Every one is kept unless tapped to be marked for removal.
struct NotSeenScreen: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accent) private var accent
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grid = false
    @State private var sort = Sort.az

    enum Sort: String, CaseIterable { case az = "A–Z", cp = "CP", iv = "IV" }

    var body: some View {
        if case .review(let review) = model.flow {
            content(ReviewContext(review))
        } else { Color.clear }
    }

    private func content(_ ctx: ReviewContext) -> some View {
        let review = ctx.review
        let report = ctx.goneReport
        let entries = sorted(report.gone.compactMap { ctx.saved[$0] })
        let marked = report.gone.filter { review.markedForRemoval.contains($0) }.count
        let markable = markableIds(report, ctx)
        let parts = entries.map { GameSearch.part(saved: $0) }
        let search = GameSearch.text(parts)
        let uncovered = parts.count - GameSearch.covered(parts)
        return VStack(spacing: 0) {
            ReviewTopBar(title: "Not seen", onBack: close)
            ScrollView {
                LazyVStack(spacing: Theme.Space.panelGap) {
                    header(count: entries.count, marked: marked, search: search, uncovered: uncovered)
                    // Items on screen that could not be read, and rows the person left out: some of the entries below may be those Pokémon.
                    if let line = BoxMerge.unreadLine(ctx.plan) { Text(line).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.orangeInk).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6) }
                    if let line = BoxMerge.leftOutLine(ctx.plan, resolutions: review.resolutions) { Text(line).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.orangeInk).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6) }
                    HStack {
                        Text("Tap the ones you no longer have").font(.figtree(18, .heavy, relativeTo: .title3)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        viewToggle
                    }
                    .padding(.horizontal, 6).padding(.top, 4)
                    sortBar
                    if grid { gridView(entries, review) } else { listView(entries, review) }
                }
                .padding(.horizontal, Theme.Space.screen).padding(.top, 6).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(marked: marked, markable: markable, ctx: ctx) }
    }

    // MARK: header

    private func header(count: Int, marked: Int, search: String?, uncovered: Int) -> some View {
        HStack(spacing: 12) {
            Text(count.formatted()).font(.figtree(30, .heavy, relativeTo: .largeTitle)).monospacedDigit().foregroundStyle(Theme.ink)
            Text((marked == 0 ? "not in this scan, all kept. Search the game: if one shows up, you still have it."
                 : "not in this scan. \(marked.formatted()) marked for removal, the rest kept. Search the game: if one shows up, you still have it.")
                 + " The search can also show other Pokémon with the same name and one of the other CPs, so check the CP."
                 + (uncovered > 0 ? " \(uncovered.formatted()) of these \(uncovered == 1 ? "has" : "have") no usable CP, so the search does not cover \(uncovered == 1 ? "it" : "them")." : ""))
                .font(.figtree(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
            if let search { CopyCircle(text: search) }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous)).panelShadow()
    }

    private var viewToggle: some View {
        HStack(spacing: 0) {
            ForEach([(false, "list.bullet", "List"), (true, "square.grid.2x2", "Grid")], id: \.1) { isGrid, icon, label in
                Button { grid = isGrid } label: {
                    Image(systemName: icon).font(.figtree(16, .bold)).foregroundStyle(grid == isGrid ? accent.ink : Theme.muted)
                        .frame(width: 44, height: 32).background(Capsule().fill(grid == isGrid ? Theme.surface : .clear))
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(label).accessibilityAddTraits(grid == isGrid ? .isSelected : [])
            }
        }
        .padding(3).background(Capsule().fill(Theme.off))
    }

    private var sortBar: some View {
        HStack(spacing: 8) {
            Text("Sort").font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(Theme.muted)
            HStack(spacing: 4) {
                ForEach(Sort.allCases, id: \.self) { s in
                    Button { sort = s } label: {
                        Text(s.rawValue).font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(sort == s ? accent.ink : Theme.muted)
                            .padding(.horizontal, 12).frame(minHeight: 32).background(Capsule().fill(sort == s ? Theme.surface : .clear))
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(sort == s ? .isSelected : [])
                }
            }
            .padding(3).background(Capsule().fill(Theme.off))
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func sorted(_ e: [BoxEntry]) -> [BoxEntry] {
        func total(_ x: BoxEntry) -> Int { x.row.ivs.map { $0.atk + $0.def + $0.hp } ?? -1 }
        switch sort {
        case .az: return e.sorted { ($0.row.title, $1.row.cp) < ($1.row.title, $0.row.cp) }
        case .cp: return e.sorted { $0.row.cp > $1.row.cp }
        case .iv: return e.sorted { total($0) > total($1) }
        }
    }

    // MARK: list and grid

    private func listView(_ entries: [BoxEntry], _ review: AppModel.Review) -> some View {
        Panel(padding: 0, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { n, e in
                let on = review.markedForRemoval.contains(e.id)
                Button { model.setRemove(e.id, !on) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark").font(.figtree(13, .bold)).foregroundStyle(on ? .white : Theme.faint)
                            .frame(width: 26, height: 26).background(Circle().fill(on ? Theme.red : Theme.off)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(e.row.title) · \(ReviewWording.cpText(e.row.cp))").paText(.rowTitle).foregroundStyle(Theme.ink)
                            Text(on ? "Removed when you save" : "Kept").font(.figtree(13, .semibold, relativeTo: .footnote)).foregroundStyle(on ? Theme.red : Theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 56)
                    .background(on ? Theme.red.opacity(0.1) : Color.clear)
                    .overlay(alignment: .top) { if n > 0 { Rectangle().fill(Theme.line).frame(height: 1) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(e.row.title), \(ReviewWording.cpText(e.row.cp)), \(on ? "marked for removal" : "kept")")
                .accessibilityHint(on ? "Keeps it" : "Marks it for removal when you save")
            }
        }
    }

    private func gridView(_ entries: [BoxEntry], _ review: AppModel.Review) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(entries, id: \.id) { e in
                let on = review.markedForRemoval.contains(e.id)
                Button { model.setRemove(e.id, !on) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        (Text("CP ").font(.figtree(10, .bold)).foregroundStyle(Theme.muted) + Text(e.row.cp > 0 ? "\(e.row.cp)" : "?").font(.figtree(18, .heavy, relativeTo: .headline)).foregroundStyle(Theme.ink)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        Text(e.row.name).font(.figtree(11, .bold, relativeTo: .caption)).foregroundStyle(Theme.muted).lineLimit(1)
                        if let i = e.row.ivs { BarsView(i.atk, i.def, i.hp, mini: true) } else { Text("No IVs").font(.figtree(10, .semibold)).foregroundStyle(Theme.faint) }
                    }
                    .padding(.horizontal, 9).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(on ? Theme.red.opacity(0.1) : Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay { if on { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.red, lineWidth: 2) } }
                    .overlay(alignment: .topTrailing) {
                        if on { Image(systemName: "checkmark").font(.figtree(11, .bold)).foregroundStyle(.white).frame(width: 20, height: 20).background(Circle().fill(Theme.red)).offset(x: 5, y: -5) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(e.row.title), \(ReviewWording.cpText(e.row.cp)), \(ReviewWording.ivsText(e.row.ivs)), \(on ? "marked for removal" : "kept")")
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: review.markedForRemoval)
    }

    // MARK: Mark all

    /// "Mark all" is for a scan that reached the end of the list and was not ended early. The not-seen list (`goneReport`) already leaves out the entries that were on screen unread
    /// ("On screen but not read"); on top of that, an entry whose CP is the CP of a card the scan read without a name is left out too, as the design says.
    private func markableIds(_ report: BoxMerge.GoneReport, _ ctx: ReviewContext) -> [String] {
        let unreadCPs = Set(ctx.review.outcome.scan.unmatched.compactMap(\.cp) + ctx.plan.unmatchedItems.compactMap(\.cp))
        return report.gone.filter { id in ctx.saved[id].map { !unreadCPs.contains($0.row.cp) } ?? false }
    }

    private func bottomBar(marked: Int, markable: [String], ctx: ReviewContext) -> some View {
        let report = ctx.goneReport
        let allMarked = !markable.isEmpty && markable.allSatisfy { ctx.review.markedForRemoval.contains($0) }
        return HStack(spacing: 8) {
            // A Full scan the person chose against the app's advice cannot say which Pokémon are gone, so it offers no bulk mark (tapping single entries still works).
            if ctx.ending == .listEnd && ctx.review.advice?.fullIsSound == true && !markable.isEmpty {
                PillButton(allMarked ? "Keep all" : "Mark all \(markable.count.formatted())", style: .plain, height: 54, fullWidth: false, isDestructive: !allMarked) {
                    if allMarked { model.keepAllNotSeen() } else {
                        model.removeAllNotSeen()
                        // The ones that may be a card the scan could not name stay kept.
                        for id in report.gone where !markable.contains(id) { model.setRemove(id, false) }
                    }
                }
                .panelShadow()
            }
            if marked > 0 {
                // Removing is destructive: red text and outline on the surface, never the filled accent style. It only closes the page; the marks are applied on Save.
                Button(action: close) {
                    Text("Remove \(marked.formatted()) when you save").font(.button).multilineTextAlignment(.center).foregroundStyle(Theme.red)
                        .padding(.horizontal, 20).padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: 54)
                        .background(Theme.surface, in: Capsule()).overlay(Capsule().stroke(Theme.red, lineWidth: 2))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("notseen-done")
            } else {
                PillButton("Done", style: .filled, height: 54) { close() }.accessibilityIdentifier("notseen-done")
            }
        }
        .padding(.horizontal, Theme.Space.screen).padding(.top, 14).padding(.bottom, 8)
        .background(LinearGradient(stops: [.init(color: Theme.bg.opacity(0), location: 0), .init(color: Theme.bg, location: 0.3)], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom))
    }
}

/// The 40 pt orange circle that copies a search.
struct CopyCircle: View {
    let text: String
    @Environment(\.showToast) private var showToast
    var body: some View {
        Button { UIPasteboard.general.string = text; showToast("Copied") } label: {
            Image(systemName: "doc.on.doc").font(.figtree(17, .semibold)).foregroundStyle(Theme.orangeInk)
                .frame(width: 40, height: 40).background(Circle().fill(Theme.orangeTint)).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Copy a search for all").accessibilityValue(text)
    }
}
