import SwiftUI
import PogoBox
import PogoReader

// The Guide me help level's way through the open questions (design handoff v2 section 1c, prototype "guide"): one question per screen, each with its own
// "Check in game" search. The answers go through the same `AppModel.resolve` as the Standard cards, and the words and the note come from the same
// `ReviewWording` / `BoxMerge.effect`, so a sentence here is the sentence the Standard card shows. Used only on `HelpLevel.guide`.

extension ReviewWording {
    /// The question as the Guide me screen words it. Only a part read matched to one saved Pokémon is worded differently (canvas 1c): the saved CP is in the
    /// question and the answers. Every other kind keeps the Standard card's title, answers and note.
    static func guideQuestion(_ u: BoxMerge.Unsure, plan: BoxMerge.Plan, saved: [String: BoxEntry], gm: GameMaster?) -> ReviewQuestion {
        var q = question(u, plan: plan, saved: saved, gm: gm)
        guard u.kind == .partialRead, q.shape == .single, let c = q.candidates.first, let e = saved[c.id] else { return q }
        let row = plan.scanned[u.scanned]
        q.title = "Is this \(row.title) the CP \(e.row.cp) in your box?"
        q.answers = [
            .init(label: "Yes, it's CP \(e.row.cp)", icon: "checkmark", resolution: .existing(e.id), style: .filled),
            .init(label: "No, it's a new Pokémon!", icon: "plus", resolution: .new, style: .tint),
            .init(label: "Don't include", icon: "minus", resolution: .leaveOut, style: .tint),
        ]
        q.note = partReadNote(effect: c.effect, members: [(row, e.row)], showAddNew: true)
        return q
    }
}

/// The questions in the order the Standard list shows them (group by group), so part reads and other groups stay together.
@MainActor
func guideOrder(_ ctx: ReviewContext) -> [Int] {
    var order = ctx.groups.flatMap(\.members)
    let seen = Set(order)
    order += ctx.plan.unsure.map(\.scanned).filter { !seen.contains($0) }
    return order
}

// MARK: entry card on the result screen

/// On the Guide me level this stands where the question cards are: it starts, carries on or reopens the one-at-a-time screens.
struct GuideEntryCard: View {
    let ctx: ReviewContext
    @Binding var path: [ReviewPage]
    @Environment(\.accent) private var accent

    var body: some View {
        let title = ctx.left == 0 ? "Review your answers" : (ctx.answered > 0 ? "Carry on: \(ctx.left) left" : "Start the \(ReviewFormat.count(ctx.total, "question", "questions"))")
        Button { path.append(.guide) } label: {
            HStack(spacing: 14) {
                Image(systemName: "hand.point.up.left.fill").font(.figtree(22, .bold)).foregroundStyle(accent.onSolid)
                    .frame(width: 48, height: 48).background(Circle().fill(accent.solid)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.figtree(18, .heavy, relativeTo: .headline)).foregroundStyle(Theme.ink)
                    Text("One at a time, with a game search for each").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.figtree(14, .bold)).foregroundStyle(Theme.faint).accessibilityHidden(true)
            }
            .padding(20).frame(minHeight: 88)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)).panelShadow()
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guide-start")
    }
}

// MARK: the screens

/// One question per screen. Answering moves to the next; Back goes to the one before; after the last answer the result screen is shown again with the
/// answers in place (Save unlocks there when none is open).
struct GuideScreen: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.showToast) private var showToast
    let close: () -> Void
    /// nil until the person moves: the first question without an answer (or the first, when all are answered).
    @State private var index: Int?
    @State private var forward = true
    /// A second tap while the screen is changing does not answer the question that arrives.
    @State private var locked = false

    var body: some View {
        if case .review(let review) = model.flow {
            content(ReviewContext(review))
        } else {
            Color.clear
        }
    }

    private func content(_ ctx: ReviewContext) -> some View {
        let order = guideOrder(ctx)
        let start = order.firstIndex { ctx.resolution($0) == nil } ?? 0
        let i = order.isEmpty ? 0 : min(max(index ?? start, 0), order.count - 1)
        return VStack(spacing: 0) {
            topBar(i, order.count)
            progress(ctx)
            if order.indices.contains(i) {
                ZStack {
                    GuideQuestionView(ctx: ctx, scanned: order[i], position: i, count: order.count,
                                      next: i + 1 < order.count ? ctx.question(order[i + 1])?.short : nil,
                                      answer: { answer($0, scanned: order[i], at: i, ctx: ctx, order: order) },
                                      back: i > 0 ? { go(i - 1, forward: false) } : nil)
                        .id(order[i])
                        .transition(reduceMotion ? .identity : .push(from: forward ? .trailing : .leading))
                }
                .clipped()
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private func topBar(_ i: Int, _ n: Int) -> some View {
        ZStack {
            Text("Question \(i + 1) of \(n)").paText(.rowTitle).fontWeight(.bold).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center).padding(.horizontal, 56).accessibilityAddTraits(.isHeader)
            HStack { IconButton(systemImage: "xmark", kind: .floating, label: "Back to the result", action: close).accessibilityIdentifier("guide-close"); Spacer() }
        }
        .padding(.horizontal, 18).frame(minHeight: 52)
    }

    private func progress(_ ctx: ReviewContext) -> some View {
        let fraction = ctx.total == 0 ? 1 : Double(ctx.answered) / Double(ctx.total)
        return GeometryReader { g in
            Capsule().fill(Theme.off)
                .overlay(alignment: .leading) { Capsule().fill(Theme.green).frame(width: g.size.width * fraction) }
                .clipShape(Capsule())
        }
        .frame(height: 6)
        .padding(.horizontal, 22).padding(.top, 6)
        .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.45), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Answered \(ctx.answered) of \(ctx.total)")
    }

    private func go(_ i: Int, forward f: Bool) {
        forward = f
        withAnimation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.35)) { index = i }
    }

    private func answer(_ r: BoxMerge.Resolution, scanned: Int, at i: Int, ctx: ReviewContext, order: [Int]) {
        guard !locked else { return }
        locked = true
        Task { try? await Task.sleep(nanoseconds: reduceMotion ? 150_000_000 : 450_000_000); locked = false }
        model.resolve(scanned, r)
        if i + 1 < order.count {
            go(i + 1, forward: true)
        } else if let open = order.firstIndex(where: { $0 != scanned && ctx.resolution($0) == nil }) {
            go(open, forward: false)
        } else {
            showToast("All \(order.count) answered")
            close()
        }
    }
}

/// The question, its game search and its answers.
private struct GuideQuestionView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let ctx: ReviewContext
    let scanned: Int
    let position: Int
    let count: Int
    let next: String?
    let answer: (BoxMerge.Resolution) -> Void
    let back: (() -> Void)?
    @State private var showAll = false

    var body: some View {
        if let u = ctx.unsure(scanned) {
            let q = ReviewWording.guideQuestion(u, plan: ctx.plan, saved: ctx.saved, gm: ctx.gm)
            let res = ctx.resolution(scanned)
            ScrollView {
                VStack(spacing: Theme.Space.panelGap) {
                    panel(q, res)
                    VStack(spacing: 8) {
                        if let res {
                            Text(ReviewWording.answeredText(q, res, plan: ctx.plan, saved: ctx.saved, gm: ctx.gm)).paText(.secondary).foregroundStyle(Theme.greenInk)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                        }
                        ForEach(Array(q.answers.enumerated()), id: \.offset) { n, a in
                            GuideAnswerButton(answer: a, answered: res != nil, selected: res == a.resolution) { answer(a.resolution) }
                                .accessibilityIdentifier("guide-answer-\(n)")
                        }
                    }
                    footer
                }
                .padding(.horizontal, Theme.Space.screen).padding(.top, 18).padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        } else {
            Color.clear
        }
    }

    private func panel(_ q: ReviewQuestion, _ res: BoxMerge.Resolution?) -> some View {
        Panel(padding: 22, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: q.kind.icon).font(.figtree(22, .bold)).foregroundStyle(q.kind.ink)
                    .frame(width: 44, height: 44).background(q.kind.well, in: RoundedRectangle(cornerRadius: 15, style: .continuous)).accessibilityHidden(true)
                Text(q.title).paText(.questionTitleGuide).foregroundStyle(Theme.ink).padding(.top, 6)
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
            }
            if let compare = q.compare { CompareView(compare: compare) }
            if !q.pair.isEmpty { PairBoxesView(q: q) }
            if q.shape == .single, q.candidates.first?.alreadySeen == true {
                Text("In your box, already seen in this scan").font(.figtree(12, .medium, relativeTo: .caption)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let line = q.readLine { Text(line).paText(.secondary).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading) }
            let shown = q.shownCandidates(showAll: showAll, chosen: res)
            if !shown.isEmpty {
                VStack(spacing: 8) {
                    ForEach(shown) { c in CandidateRowView(q: q, c: c) { answer(.existing(c.id)) } }
                    if q.canShowAll(showAll: showAll, chosen: res) {
                        Button { withAnimation(reduceMotion ? nil : .snappy) { showAll = true } } label: {
                            Text("Show all \(q.listed.count) candidates").font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(accent.ink).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let s = q.search { GuideSearch(text: s) }
            if let note = q.note { Text(note).paText(.secondary).foregroundStyle(Theme.muted) }
        }
    }
    @Environment(\.accent) private var accent

    @ViewBuilder private var footer: some View {
        if back != nil || next != nil {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { backButton; Spacer(minLength: 8); nextLine }
                VStack(alignment: .leading, spacing: 4) { backButton; nextLine }
            }
            .padding(.horizontal, 6)
        }
    }

    @ViewBuilder private var backButton: some View {
        if let back {
            Button(action: back) {
                HStack(spacing: 4) { Image(systemName: "chevron.left").font(.figtree(14, .bold)); Text("Back").font(.figtree(15, .bold, relativeTo: .subheadline)) }
                    .foregroundStyle(accent.ink).frame(minWidth: 44, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Back to the previous question")
            .accessibilityIdentifier("guide-back")
        }
    }

    @ViewBuilder private var nextLine: some View {
        if let next { Text("Next: \(next)").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted).multilineTextAlignment(.trailing) }
    }
}

/// A full-size answer: 56 pt, 18 pt text. The first (most likely) answer is the filled one; the answer given shows green with a tick.
private struct GuideAnswerButton: View {
    let answer: ReviewQuestion.Answer
    let answered: Bool
    let selected: Bool
    let action: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if selected { Image(systemName: "checkmark.circle.fill").font(.figtree(18, .bold)).accessibilityHidden(true) }
                else if let icon = answer.icon { Image(systemName: icon).font(.figtree(17, .bold)).accessibilityHidden(true) }
                Text(answer.label).font(.figtree(18, .bold, relativeTo: .body)).multilineTextAlignment(.center)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityValue(selected ? "Your answer" : "")
    }

    private var primary: Bool { answer.style == .filled && !answered }
    private var fill: Color { selected ? Theme.greenTint : (primary ? accent.solid : accent.tint) }
    private var ink: Color { selected ? Theme.greenInk : (primary ? accent.onSolid : accent.ink) }
}

/// "Check in game": the search to paste into the game's storage search, Copy, and the (i) that says how to use it.
private struct GuideSearch: View {
    let text: String
    @Environment(\.showToast) private var showToast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Check in game").font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(Theme.orangeInk).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { withAnimation(reduceMotion ? nil : .snappy) { showInfo.toggle() } } label: {
                    Image(systemName: "info.circle").font(.figtree(18, .semibold)).foregroundStyle(Theme.orangeInk).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .padding(.vertical, -8).padding(.trailing, -10)
                .accessibilityLabel("How to use this search")
                .accessibilityIdentifier("guide-info")
            }
            HStack(spacing: 10) {
                Text(text).font(.figtree(17, .heavy, relativeTo: .body)).foregroundStyle(Theme.orangeInk).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { UIPasteboard.general.string = text; showToast("Copied") } label: {
                    HStack(spacing: 6) { Image(systemName: "doc.on.doc"); Text("Copy") }
                        .font(.figtree(14, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.surface)
                        .padding(.horizontal, 14).frame(minHeight: 36).background(Theme.orangeInk, in: Capsule())
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Copy search").accessibilityValue(text)
                .accessibilityIdentifier("guide-copy")
            }
            if showInfo {
                Text("Paste it into the game's storage search, look at the Pokémon, then come back.").font(.figtree(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Theme.bg).padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.orangeTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
