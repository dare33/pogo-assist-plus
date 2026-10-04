import SwiftUI
import PogoBox

/// The open questions of the result screen, grouped by `BoxMerge.questionGroups`. A group of part reads is one panel with a row each; every other
/// question is a `QuestionCard`, with a "Yes, all N" button above a group that can be answered together.
struct ReviewQuestionsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let ctx: ReviewContext
    @Binding var folded: Set<String>

    var body: some View {
        ForEach(ctx.groups, id: \.members) { g in
            if g.kind == .partialRead && !g.primary.isEmpty && g.primary.count == g.members.count {
                PartReadGroupView(ctx: ctx, group: g, folded: $folded)
            } else {
                VStack(spacing: Theme.Space.panelGap) {
                    if g.canBulk { BulkButton(ctx: ctx, group: g, kind: .card) }
                    ForEach(g.members, id: \.self) { m in
                        if let q = ctx.question(m) { ReviewCardView(ctx: ctx, q: q) }
                    }
                }
            }
        }
    }

}

/// "Yes, all N" above a group of questions. It answers only the members that have no answer yet (never one the person already gave), says how many that is, and is gone once none
/// is open.
struct BulkButton: View {
    enum Style { case card, partRead }
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let ctx: ReviewContext
    let group: BoxMerge.QuestionGroup
    let kind: Style
    @State private var runner = BulkRunner()

    var body: some View {
        let open = group.members.filter { ctx.resolution($0) == nil && group.primary[$0] != nil }
        let n = open.count
        if n > 0 {
            PillButton(label(n), systemImage: "checkmark", style: group.kind == .megaPair ? .tint : .filled, height: 52) {
                runner.start(model, members: group.members, answers: group.primary, reduceMotion: reduceMotion)
            }
            // The scan kind was switched or the screen is going away: nothing more is written.
            .onChange(of: ctx.review.planToken) { _, _ in runner.cancel() }
            .onDisappear { runner.cancel() }
        }
    }

    private func label(_ n: Int) -> String {
        if kind == .partRead { return "Yes, all \(n) are the saved ones" }
        switch group.kind {
        case .evolved: return "Yes, all \(n) evolved"
        case .poweredUp: return "Yes, all \(n) powered up"
        case .megaPair, .megaToBase: return "Yes, all \(n) are the same Pokémon"
        default: return "Yes, all \(n) are the saved ones"
        }
    }
}

/// Answering a group in bulk. The answers tick one after another, 90 ms apart (at once with Reduce Motion), from ONE task: a second tap while it runs does nothing. It stops (and writes
/// nothing more) when the person answers or takes back any member of the group, when the plan changes (another scan kind) and when its button goes away.
@MainActor
final class BulkRunner {
    private var task: Task<Void, Never>?
    private var generation = 0

    func start(_ model: AppModel, members: [Int], answers: [Int: BoxMerge.Resolution], reduceMotion: Bool) {
        guard task == nil, case .review(let r0) = model.flow else { return }
        // Only members with no answer yet: an answer the person gave is never overwritten.
        let todo = members.filter { r0.resolutions[$0] == nil && answers[$0] != nil }
        guard !todo.isEmpty else { return }
        if reduceMotion { for m in todo { model.resolve(m, answers[m]) }; return }
        let token = r0.planToken
        generation += 1
        let mine = generation
        task = Task { @MainActor [weak self] in
            // What each member's answer should be if nobody but this task has touched it.
            var expected = [Int: BoxMerge.Resolution]()
            for m in members { if let a = r0.resolutions[m] { expected[m] = a } }
            for (i, m) in todo.enumerated() {
                if i > 0 { try? await Task.sleep(nanoseconds: 90_000_000) }
                guard !Task.isCancelled, case .review(let r) = model.flow, r.planToken == token else { break }
                if members.contains(where: { r.resolutions[$0] != expected[$0] }) { break }
                withAnimation(.snappy) { model.resolve(m, answers[m]) }
                expected[m] = answers[m]
            }
            if let self, self.generation == mine { self.task = nil }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
    }
}

// MARK: part-read group

private struct PartReadGroupView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.helpLevel) private var helpLevel
    let ctx: ReviewContext
    let group: BoxMerge.QuestionGroup
    @Binding var folded: Set<String>

    private var members: [PartReadMember] {
        group.members.compactMap { m in
            guard case .existing(let id)? = group.primary[m], let e = ctx.saved[id] else { return nil }
            return PartReadMember(scanned: m, row: ctx.plan.scanned[m], saved: e)
        }
    }
    private var key: String { ctx.groupKey(group) }
    private var allAnswered: Bool { group.members.allSatisfy { ctx.resolution($0) != nil } }
    private var sameHP: Bool { members.allSatisfy { $0.row.hp != nil && $0.row.hp == $0.saved.row.hp } }

    var body: some View {
        let n = members.count
        VStack(spacing: 0) {
            if folded.contains(key) {
                QuestionCard(kind: .match, title: title, short: n == 1 ? "1 part-read CP" : "\(n) part-read CPs", answered: summary, onChange: { withAnimation(reduceMotion ? nil : .snappy) { _ = folded.remove(key) } }) {}
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.98)))
            } else {
                open(n)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        // A group folds 750 ms after its last answer; an answer taken back before then cancels it.
        .task(id: allAnswered) {
            guard allAnswered, !folded.contains(key) else { return }
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .snappy) { _ = folded.insert(key) }
        }
    }

    private var title: String {
        let one = members.count == 1
        return sameHP ? (one ? "Is this the saved one with the same HP?" : "Are these the saved ones with the same HP?") : (one ? "Is this the saved one?" : "Are these the saved ones?")
    }

    private func open(_ n: Int) -> some View {
        Panel(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: QuestionKind.match.icon).font(.figtree(20, .bold)).foregroundStyle(Theme.matchInk)
                    .frame(width: 40, height: 40).background(Theme.matchTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous)).accessibilityHidden(true)
                Text(title).paText(.questionTitle).foregroundStyle(Theme.ink).padding(.top, 7)
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 6) { ForEach(members) { PartReadRow(ctx: ctx, member: $0) } }
            if helpLevel != .essentials { legend }
            if group.canBulk { BulkButton(ctx: ctx, group: group, kind: .partRead) }
            if let s = search { SearchStrip(text: s) }
            Text(note).paText(.secondary).foregroundStyle(Theme.muted)
        }
    }

    private var search: String? {
        GameSearch.text(members.map { GameSearch.part(for: ctx.unsure($0.scanned)!, row: $0.row, saved: ctx.saved) })
    }

    private var note: String {
        ReviewWording.partReadNote(effect: group.effect, members: members.map { ($0.row, $0.saved.row) }, showAddNew: helpLevel != .essentials)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach([("checkmark", "The saved one", Theme.greenInk), ("plus", "Add new", Theme.matchInk), ("minus", "Don't include", Theme.muted)], id: \.1) { icon, text, ink in
                HStack(spacing: 4) { Image(systemName: icon).foregroundStyle(ink); Text(text) }
            }
        }
        .font(.figtree(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.muted)
        .accessibilityHidden(true)
    }

    private var summary: String {
        var saved = 0, new = 0, out = 0
        for m in group.members {
            switch ctx.resolution(m) { case .existing?: saved += 1; case .new?: new += 1; case .leaveOut?: out += 1; case nil: break }
        }
        let n = group.members.count
        if saved == n { return n == 1 ? "The saved one" : "All \(n) are the saved ones" }
        return [saved > 0 ? "\(saved) saved" : nil, new > 0 ? "\(new) added" : nil, out > 0 ? "\(out) not included" : nil].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct PartReadRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let ctx: ReviewContext
    let member: PartReadMember

    var body: some View {
        let res = ctx.resolution(member.scanned)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(member.row.title).paText(.rowTitle).foregroundStyle(Theme.ink)
                sub
            }
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let res { answered(res) } else { icons }
        }
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 6)
        .frame(minHeight: 56)
        .background(tint(res), in: RoundedRectangle(cornerRadius: Theme.Radius.insetRow, style: .continuous))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: res)
    }

    private var sub: some View {
        let r = member.row, e = member.saved.row
        let sameHP = r.hp != nil && r.hp == e.hp
        let read = r.cp > 0
        let tail: String
        if read { tail = sameHP ? " read · saved \(e.cp) · HP \(e.hp ?? 0)" : "\(r.hp.map { ", HP \($0)" } ?? "") read · saved \(e.cp)\(e.hp.map { ", HP \($0)" } ?? "")" }
        else { tail = sameHP ? " · saved \(e.cp) · HP \(e.hp ?? 0)" : "\(r.hp.map { " · HP \($0) read" } ?? "") · saved \(e.cp)\(e.hp.map { ", HP \($0)" } ?? "")" }
        return (Text(read ? "\(r.cp)" : "CP not read").font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(Theme.orangeInk) + Text(tail).font(.figtree(13, .regular, relativeTo: .footnote)).foregroundStyle(Theme.muted)).monospacedDigit()
    }

    private var icons: some View {
        HStack(spacing: 0) {
            IconButton(systemImage: "checkmark", kind: .done, label: "It's the saved one") { answer(.existing(member.saved.id)) }
            IconButton(systemImage: "plus", kind: .add, label: "Add new") { answer(.new) }
            IconButton(systemImage: "minus", kind: .neutral, label: "Don't include") { answer(.leaveOut) }
        }
    }

    private func answered(_ res: BoxMerge.Resolution) -> some View {
        let (icon, label, ink): (String, String, Color) = {
            switch res {
            case .existing: return ("checkmark", "Saved one", Theme.greenInk)
            case .new: return ("plus", "Added", Theme.matchInk)
            case .leaveOut: return ("minus", "Not included", Theme.muted)
            }
        }()
        return Button { withAnimation(reduceMotion ? nil : .snappy) { model.resolve(member.scanned, nil) } } label: {
            HStack(spacing: 6) { Image(systemName: icon); Text(label) }
                .font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(ink)
                .padding(.horizontal, 10).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(label) for \(member.row.title)")
        .accessibilityHint("Takes the answer back")
    }

    private func tint(_ res: BoxMerge.Resolution?) -> Color {
        switch res {
        case .existing?: return Theme.greenTint
        case .new?: return accent.tint
        case .leaveOut?: return Theme.off
        case nil: return Theme.surface2
        }
    }
    @Environment(\.accent) private var accent

    private func answer(_ r: BoxMerge.Resolution) { withAnimation(reduceMotion ? nil : .snappy) { model.resolve(member.scanned, r) } }
}

struct PartReadMember: Identifiable { var scanned: Int; var row: ScanRow; var saved: BoxEntry; var id: Int { scanned } }

// MARK: one card

struct ReviewCardView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let ctx: ReviewContext
    let q: ReviewQuestion
    @State private var showAll = false

    var body: some View {
        let res = ctx.resolution(q.scanned)
        QuestionCard(kind: q.kind, title: q.title, short: q.short, compare: q.compare, note: q.note,
                     answered: res.map { ReviewWording.answeredText(q, $0, plan: ctx.plan, saved: ctx.saved, gm: ctx.gm) },
                     onChange: { withAnimation(reduceMotion ? nil : .snappy) { model.resolve(q.scanned, nil) } }) {
            if !q.pair.isEmpty { pairBoxes }
            // A single saved candidate is in the compare pair, not in a list: say here when another row of this scan already paired it.
            if q.shape == .single, q.candidates.first?.alreadySeen == true {
                Text("In your box, already seen in this scan").font(.figtree(12, .medium, relativeTo: .caption)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let line = q.readLine { Text(line).paText(.secondary).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading) }
            ForEach(shown) { candidateRow($0) }
            ForEach(q.answers) { a in
                PillButton(a.label, systemImage: a.icon, style: a.style, height: a.style == .filled ? 52 : 48) { answer(a.resolution) }
            }
            if canShowAll {
                Button { withAnimation(reduceMotion ? nil : .snappy) { showAll = true } } label: {
                    Text("Show all \(allCount) candidates").font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(accentInk).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        } search: {
            if let s = q.search { SearchStrip(text: s) }
        }
    }

    @Environment(\.accent) private var accent
    private var accentInk: Color { accent.ink }

    private func answer(_ r: BoxMerge.Resolution) { withAnimation(reduceMotion ? nil : .snappy) { model.resolve(q.scanned, r) } }

    // Candidates: see `ReviewQuestion.listed` and `shownCandidates`.
    private var listed: [ReviewQuestion.Candidate] { q.listed }
    private var allCount: Int { listed.count }
    private var shown: [ReviewQuestion.Candidate] { q.shownCandidates(showAll: showAll, chosen: ctx.resolution(q.scanned)) }
    private var canShowAll: Bool { q.canShowAll(showAll: showAll, chosen: ctx.resolution(q.scanned)) }

    private func candidateRow(_ c: ReviewQuestion.Candidate) -> some View { CandidateRowView(q: q, c: c) { answer(.existing(c.id)) } }

    private var pairBoxes: some View { PairBoxesView(q: q) }
}

// MARK: pieces shared with the Guide me screen

extension ReviewQuestion {
    /// A single-candidate card shows its one saved Pokémon in the compare pair, so only the several-candidate and twin cards list them.
    var listed: [Candidate] { shape == .single ? [] : candidates }

    /// A row that cannot be identified by its CP has its same-species, same-HP entries ranked first (`Plan.rankedCounts`): the best three, then "Show all". A candidate already
    /// chosen from beyond the top three stays shown, however the list is rebuilt.
    func shownCandidates(showAll: Bool, chosen: BoxMerge.Resolution?) -> [Candidate] {
        guard rankedCount > 0, !showAll else { return listed }
        var top = Array(listed.prefix(min(3, rankedCount)))
        if case .existing(let id)? = chosen, let c = listed.first(where: { $0.id == id }), !top.contains(where: { $0.id == id }) { top.append(c) }
        return top
    }
    func canShowAll(showAll: Bool, chosen: BoxMerge.Resolution?) -> Bool { rankedCount > 0 && !showAll && listed.count > shownCandidates(showAll: showAll, chosen: chosen).count }
}

/// One saved candidate with its "This one" button.
struct CandidateRowView: View {
    let q: ReviewQuestion
    let c: ReviewQuestion.Candidate
    let pick: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.line).font(.figtree(15, .semibold, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.ink)
                if c.alreadySeen { Text("In your box, already seen in this scan").font(.figtree(12, .medium, relativeTo: .caption)).foregroundStyle(Theme.muted) }
                if q.shape == .extraTwin || ReviewWording.perCandidateNotes(q) { Text(c.effectText).font(.figtree(12, .medium, relativeTo: .caption)).foregroundStyle(Theme.muted) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PillButton("This one", style: .tint, height: 46, fullWidth: false, action: pick)
        }
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 6)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.Radius.insetRow, style: .continuous))
    }
}

/// The Mega pair's NORMAL / MEGA boxes.
struct PairBoxesView: View {
    let q: ReviewQuestion

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(q.pair.enumerated()), id: \.offset) { _, p in
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.heading).font(.figtree(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.muted)
                    Text(p.side.line).paText(.rowTitle).fontWeight(.bold).foregroundStyle(Theme.ink)
                    if let ivs = p.side.ivs { Text(ivs).font(.figtree(14, .regular, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.muted) }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.Radius.insetRow, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }
}
