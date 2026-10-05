import SwiftUI
import PogoBox
import PogoReader

/// The scan result (design v2 section 1a): header with the three steps, what saving does (with a slim bar pinned once it scrolls away), the open questions, then what the rest of the scan found.
struct ResultScreen: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.showToast) private var showToast
    @Environment(\.accent) private var accent
    @Environment(\.helpLevel) private var helpLevel
    @Binding var path: [ReviewPage]

    @State private var folded: Set<String> = []
    @State private var confirmDiscard = false
    @State private var confirmFull: String?
    @State private var savingPinned = false
    /// The scroll position's top item: one cheap signal, nothing is measured per frame. Rows without an id leave the last answer in place.
    @State private var topItem: String?
    @State private var savingOpen: Set<String> = []
    private static let headerID = "review-header"
    private static let stripID = "review-saving-end"
    private static let savingID = "review-saving"

    var body: some View {
        if case .review(let review) = model.flow {
            content(ReviewContext(review))
        } else {
            Color.clear
        }
    }

    private func content(_ ctx: ReviewContext) -> some View {
        let review = ctx.review
        return VStack(spacing: 0) {
            ReviewTopBar(title: "Scan result", account: review.account)
            Group {
                ScrollView {
                    LazyVStack(spacing: Theme.Space.panelGap) {
                        ReviewHeader(ctx: ctx, path: $path).id(Self.headerID)
                        ReviewSavingSection(ctx: ctx, open: $savingOpen).id(Self.savingID)
                        // An empty strip under the segment: the scroll position reports it as the top item once the segment has scrolled out of view.
                        Color.clear.frame(height: 1).id(Self.stripID)
                        ReviewStretchPanels(ctx: ctx)
                        ReviewNotices(ctx: ctx)
                        if ctx.total > 0 { questions(ctx) }
                        ReviewLowerSections(ctx: ctx, path: $path, confirmFull: $confirmFull)
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, Theme.Space.screen)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                }
                .scrollPosition(id: $topItem)
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("review-scroll")
                // Once the full segment is above the top, a slim bar with the same numbers is pinned under the top bar (a tap goes back to the segment).
                .overlay(alignment: .top) {
                    // Not while To check, Not seen or a guided question is open on top of this screen.
                    if savingPinned && path.isEmpty {
                        SavingBar(counts: SavingCounts(ctx.savePreview)) {
                            if reduceMotion { topItem = Self.savingID }
                            else { withAnimation(.easeInOut(duration: 0.3)) { topItem = Self.savingID } }
                        }
                        .transition(reduceMotion ? .identity : .move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: savingPinned)
                .onChange(of: topItem) { _, top in
                    switch top {
                    case Self.headerID, Self.savingID: if savingPinned { savingPinned = false }
                    case Self.stripID: if !savingPinned { savingPinned = true }
                    default: if top != nil && !savingPinned { savingPinned = true }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(ctx) }
        .background(Theme.bg.ignoresSafeArea())
        // One buzz for each answer taken (not for one taken back).
        .sensoryFeedback(.success, trigger: ctx.answered) { old, new in new > old }
        .onChange(of: review.kind) { _, _ in folded = [] }
        .sheet(item: $model.reportTarget) { MakeScansBetterSheet(target: $0).environmentObject(model) }
        .confirmationDialog("Use Full scan anyway?", isPresented: Binding(get: { confirmFull != nil }, set: { if !$0 { confirmFull = nil } }), titleVisibility: .visible) {
            Button("Use Full scan", role: .destructive) { Task { await model.setReviewKind(.full) } }
            Button("Keep Add and update", role: .cancel) {}
        } message: { Text("\(confirmFull ?? "") A full scan lists every saved Pokémon this scan did not see, as \"Not seen in this scan\". They are all kept; nothing is removed unless you mark it.") }
        .confirmationDialog("Discard this scan?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard scan", role: .destructive) { model.discardReview() }
        } message: { Text("Nothing will be added to the box.") }
    }

    // MARK: questions

    @ViewBuilder private func questions(_ ctx: ReviewContext) -> some View {
        let open = ctx.openSearch
        HStack(alignment: .firstTextBaseline) {
            Text(ReviewFormat.count(ctx.total, "quick question", "quick questions")).font(.figtree(20, .heavy, relativeTo: .title3)).foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Text(ctx.left > 0 ? "\(ctx.left) left" : "All answered").font(.figtree(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 6).padding(.top, 6)
        if let text = open.text { FindAllBar(count: open.covered, text: text) }
        if open.notCovered > 0 {
            Text("\(open.notCovered) not in this search: no CP or HP to look for.").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
        }
        // Guide me answers one question per screen (GuideFlow); the other levels show the cards here.
        if helpLevel == .guide { GuideEntryCard(ctx: ctx, path: $path) } else { ReviewQuestionsView(ctx: ctx, folded: $folded) }
    }

    // MARK: bottom bar

    private func bottomBar(_ ctx: ReviewContext) -> some View {
        let blocker = model.saveBlocker(ctx.review)
        return VStack(spacing: 8) {
            // With every question answered, a blocker is something else (two answers choosing one saved Pokémon): say so.
            if ctx.left == 0, let blocker { Text(blocker).paText(.secondary).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6) }
            HStack(spacing: 8) {
                PillButton("Discard", style: .plain, height: 54, fullWidth: false, isDestructive: true) { confirmDiscard = true }
                    .panelShadow()
                if blocker != nil {
                    PillButton(ctx.left > 0 ? "\(ctx.left) to go" : "Save to box", systemImage: "lock.fill", style: .filled, height: 54) {}
                        .disabled(true)
                        .accessibilityIdentifier("review-save-locked")
                } else {
                    PillButton("Save to box", systemImage: "tray.and.arrow.down", style: .filled, height: 54) { Task { await model.saveReview() } }
                        .accessibilityIdentifier("review-save")
                }
            }
        }
        .padding(.horizontal, Theme.Space.screen).padding(.top, 14).padding(.bottom, 8)
        .background(LinearGradient(stops: [.init(color: Theme.bg.opacity(0), location: 0), .init(color: Theme.bg, location: 0.3)], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom))
    }
}

// MARK: header

/// The accent panel: how the scan ended, how many Pokémon were read and in how long, the progress of the answers and the three steps.
private struct ReviewHeader: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accent) private var accent
    let ctx: ReviewContext
    @Binding var path: [ReviewPage]
    // The number circles hold text that grows with Dynamic Type, so they grow with it.
    @ScaledMetric(relativeTo: .body) private var bigCircle: CGFloat = 32
    @ScaledMetric(relativeTo: .body) private var smallCircle: CGFloat = 30

    var body: some View {
        let read = ctx.review.outcome.scan.rows.count
        let toCheck = ctx.toCheck.count
        Panel(tint: .accent, padding: 20, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(ctx.ending.headline).font(.figtree(15, .semibold, relativeTo: .subheadline)).foregroundStyle(accent.ink)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) { hero(read); readIn }
                    VStack(alignment: .leading, spacing: 0) { hero(read); readIn }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(read.formatted()) Pokémon read in \(ReviewFormat.readIn(ctx.review.outcome.duration))")
            }
            progress
            VStack(alignment: .leading, spacing: 10) {
                stepOne
                stepTwo(toCheck)
                stepThree
            }
        }
    }

    private func hero(_ n: Int) -> some View { Text(n.formatted()).paText(.heroFigure).foregroundStyle(accent.ink) }
    private var readIn: some View {
        Text("read in \(ReviewFormat.readIn(ctx.review.outcome.duration))").font(.figtree(17, .semibold, relativeTo: .body)).foregroundStyle(Theme.muted)
    }

    private var progress: some View {
        let fraction = ctx.total == 0 ? 1 : Double(ctx.answered) / Double(ctx.total)
        return GeometryReader { g in
            Capsule().fill(Theme.surface)
                .overlay(alignment: .leading) { Capsule().fill(accent.solid).frame(width: g.size.width * fraction) }
                .clipShape(Capsule())
        }
        .frame(height: 8)
        .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.45), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Answered \(ctx.answered) of \(ctx.total)")
    }

    private var stepOne: some View {
        HStack(spacing: 12) {
            Text("1").font(.figtree(15, .heavy)).foregroundStyle(accent.onSolid)
                .frame(width: bigCircle, height: bigCircle).background(Circle().fill(accent.solid)).accessibilityHidden(true)
            Text(ctx.total == 0 ? "No questions to answer" : "Answer \(ReviewFormat.count(ctx.total, "question", "questions"))").paText(.button).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if ctx.total > 0 { Text("\(ctx.answered) of \(ctx.total)").font(.figtree(15, .heavy, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(accent.ink) }
        }
        .padding(.vertical, 8).padding(.leading, 8).padding(.trailing, 10).frame(minHeight: 48)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, -8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func stepTwo(_ toCheck: Int) -> some View {
        let row = HStack(spacing: 12) {
            Text("2").font(.figtree(14, .heavy)).foregroundStyle(Theme.muted)
                .frame(width: smallCircle, height: smallCircle).background(Circle().fill(Theme.surface)).accessibilityHidden(true)
            Text(toCheck == 0 ? "Nothing to check in the game" : "Check \(toCheck.formatted()) in the game").paText(.rowTitle).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if toCheck > 0 {
                Text("optional").font(.figtree(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                Image(systemName: "chevron.right").font(.figtree(14, .bold)).foregroundStyle(Theme.faint).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 2).frame(minHeight: 44).contentShape(Rectangle())
        if toCheck > 0 {
            Button { path.append(.toCheck) } label: { row }.buttonStyle(PressStyle()).accessibilityIdentifier("review-step-check")
        } else {
            row.accessibilityElement(children: .combine)
        }
    }

    private var stepThree: some View {
        HStack(spacing: 12) {
            Image(systemName: ctx.left == 0 && model.saveBlocker(ctx.review) == nil ? "lock.open" : "lock").font(.figtree(15, .semibold)).foregroundStyle(Theme.muted)
                .frame(width: smallCircle, height: smallCircle).background(Circle().fill(Theme.surface)).accessibilityHidden(true)
            Text("Save to box").paText(.rowTitle).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 2).frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

/// The orange strip above the questions: one search for every question still open.
private struct FindAllBar: View {
    @Environment(\.showToast) private var showToast
    let count: Int
    let text: String

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            showToast("Copied")
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.figtree(18, .bold)).foregroundStyle(Theme.orangeInk).accessibilityHidden(true)
                Text("Find all \(count) in the game").font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) { Image(systemName: "doc.on.doc"); Text("Copy") }
                    .font(.figtree(14, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.orangeInk)
                    .padding(.horizontal, 14).frame(minHeight: 36).background(Theme.orangeTint, in: Capsule())
            }
            .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 6).frame(minHeight: 48)
            .background(Theme.surface, in: Capsule()).panelShadow()
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Find all \(count) in the game, copy search")
        .accessibilityValue(text)
    }
}
