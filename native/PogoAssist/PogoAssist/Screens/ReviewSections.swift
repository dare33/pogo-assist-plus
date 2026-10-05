import SwiftUI
import PogoBox
import PogoReader

// MARK: notices under the header

/// What the scan result must say before anything else: how the scan ended and where it stopped, a scan read again, the pace and tap warnings, and why Add and update was chosen.
struct ReviewNotices: View {
    @EnvironmentObject var model: AppModel
    let ctx: ReviewContext

    private var review: AppModel.Review { ctx.review }
    /// The scan ran at a pace unlike the command last made: probably an older command played.
    private var paceWarning: String? {
        guard let pace = review.outcome.pace else { return nil }
        return (review.paging?.pagedByCommand != true || review.reread != nil) ? nil : PaceCheck.check(measured: pace.medianPeriod, chosen: model.pace)
    }
    /// The scan ran at a tap pace on a screen tap paging has not been checked on: the command's taps were placed for another screen.
    private var tapWarning: String? {
        guard review.reread == nil, review.paging?.pagedByCommand == true, !model.tapAvailable, let pace = review.outcome.pace, let ran = PaceCheck.nearestMode(to: pace.medianPeriod), ran.isTap else { return nil }
        return "This scan was paged at a tap pace, but tap paging has not been checked on this screen. A tap command made for another device can press the wrong place in the game. Check your Pokémon in the game."
    }

    var body: some View {
        if let tapWarning { notice(tapWarning, icon: "exclamationmark.octagon.fill", ink: Theme.red, bold: true) }
        if let paceWarning { notice(paceWarning, icon: "exclamationmark.triangle.fill", ink: Theme.orangeInk) }
        if let stop = review.stopSummary { notice(stop, icon: "flag.checkered", ink: Theme.ink, tint: nil) }
        if let note = review.kindNote { notice(note, icon: "info.circle", ink: Theme.muted, tint: nil) }
        if let plan = review.reread {
            notice("Reading the scan from \(Fmt.date(plan.scan.scanDate)) again, against the box as it was before that scan was saved. Nothing changes until you save.", icon: "arrow.clockwise", ink: Theme.muted, tint: nil)
            if plan.hasLaterChanges { notice(laterText(plan), icon: "exclamationmark.triangle.fill", ink: Theme.orangeInk) }
        }
    }

    private func notice(_ text: String, icon: String, ink: Color, bold: Bool = false, tint: PanelTint? = .orange) -> some View {
        Panel(tint: tint, padding: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.figtree(17, .bold)).foregroundStyle(ink).frame(width: 24).accessibilityHidden(true)
                Text(text).font(.figtree(14, bold ? .bold : .medium, relativeTo: .subheadline)).foregroundStyle(tint == nil ? Theme.ink : ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func laterText(_ r: RereadPlan) -> String {
        var parts = [String]()
        if r.laterScans > 0 { parts.append("Scans saved after this one are not included; read them again too.") }
        if r.laterEdits > 0 { parts.append("Corrections made after it are not included either.") }
        return parts.joined(separator: " ") + " Saving makes a new box version from the earlier box; every earlier version stays in Settings."
    }
}

// MARK: trouble stretches

/// One orange panel for each run of cards that failed the same way (`TroubleStretches`), under "What saving does": what happened, with the real numbers, and how to read those cards again.
/// Nothing in the counts, To check or the questions changes; the panel only tells the person where to start again.
struct ReviewStretchPanels: View {
    @EnvironmentObject var model: AppModel
    let ctx: ReviewContext

    var body: some View {
        ForEach(Array(ctx.stretches.enumerated()), id: \.offset) { n, t in
            let text = ReviewWording.stretch(t, commandSize: ReviewWording.resumeSize(t, pagedByHand: model.pagedByHand, commandSetMade: model.commandSetMade))
            let search = ReviewWording.stretchSearch(t, scan: ctx.review.outcome.scan)
            Panel(tint: .orange, padding: 16, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.figtree(17, .bold)).foregroundStyle(Theme.orangeInk).accessibilityHidden(true)
                        Text(text.title).font(.figtree(17, .heavy, relativeTo: .headline)).foregroundStyle(Theme.orangeInk)
                            .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
                    }
                    Text(text.what).font(.figtree(15, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
                    Text(text.resume).font(.figtree(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("review-stretch-\(n)")
                if let search {
                    Text("To find the first one in the game:").font(.figtree(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.orangeInk)
                    SearchStrip(text: search)
                }
            }
        }
    }
}

// MARK: below the questions

/// Everything under the questions (second frame of design 1a): what needs a look in the game, notes, not seen, on screen but not read, the scan kind, the scan details ("What saving does" is the second segment, `ReviewSavingSection`).
struct ReviewLowerSections: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accent) private var accent
    let ctx: ReviewContext
    @Binding var path: [ReviewPage]
    @Binding var confirmFull: String?
    @State private var open: Set<String> = []

    private var review: AppModel.Review { ctx.review }
    private var plan: BoxMerge.Plan { ctx.plan }

    var body: some View {
        checkInTheGame
        let report = ctx.goneReport
        let marked = report.gone.filter { review.markedForRemoval.contains($0) }.count
        let rows = listRows(report, marked: marked)
        if !rows.isEmpty { Panel(padding: 0, spacing: 0) { ForEach(rows) { $0 } }.padding(.top, 4) }
        if review.reread == nil { scanKind }
        scanDetails
    }

    // MARK: Check in the game

    @ViewBuilder private var checkInTheGame: some View {
        let toCheck = ctx.toCheck
        let cleared = ctx.clearedByAnswers
        let groups = ctx.checkGroups
        heading("Check in the game", count: toCheck.count)
        if toCheck.isEmpty && cleared == 0 {
            Panel { Text("Nothing needs a check.").paText(.secondary).foregroundStyle(Theme.muted) }
        } else {
            Panel(padding: 0, spacing: 0) {
                ForEach(groups) { g in
                    InsetRow(title: g.reason.title, sub: g.reason == .noLevelFits && cleared > 0 ? "\(cleared) more cleared by your answers" : g.reason.sub,
                             value: g.rows.count.formatted(), showsChevron: true, separator: true) { path.append(.toCheck) }
                }
                // The answers cleared every "no level fits" row: the line still says so.
                if cleared > 0 && !groups.contains(where: { $0.reason == .noLevelFits }) {
                    InsetRow(title: "No level fits", sub: "\(cleared) more cleared by your answers", value: "0", separator: true)
                }
                let parts = toCheck.map { GameSearch.part(row: plan.scanned[$0]) }
                if let text = GameSearch.text(parts) {
                    let left = parts.count - GameSearch.covered(parts)
                    VStack(alignment: .leading, spacing: 8) {
                        CopySearchButton(text: text, style: .tint)
                        Text("Paste the search into the game's storage." + (left > 0 ? " \(left) not in this search: no CP or HP to look for." : "")).paText(.secondary).foregroundStyle(Theme.muted)
                    }
                    .padding(16)
                }
            }
        }
    }

    // MARK: Notes, Not seen, on screen but not read

    private func listRows(_ report: BoxMerge.GoneReport, marked: Int) -> [IdentifiedRow] {
        var rows = [IdentifiedRow]()
        let notes = noteReasons
        if !notes.isEmpty {
            rows.append(IdentifiedRow(id: "notes") {
                reveal("notes", InsetRow(title: "Notes, nothing to do", sub: nil, icon: "note.text", value: notes.reduce(0) { $0 + $1.count }.formatted(), separator: true) { toggle("notes") }) {
                    ForEach(notes, id: \.text) { n in
                        (Text("\(n.count) × ").font(.figtree(14, .bold, relativeTo: .subheadline)) + Text(n.text).font(.figtree(14, .medium, relativeTo: .subheadline))).foregroundStyle(Theme.ink)
                    }
                }
            })
        }
        if review.kind == .full {
            rows.append(IdentifiedRow(id: "notseen") {
                InsetRow(title: "Not seen in this scan", sub: marked == 0 ? "All kept" : "\(marked.formatted()) marked to remove", icon: "eye.slash", value: report.gone.count.formatted(), showsChevron: !report.gone.isEmpty, separator: true,
                         action: report.gone.isEmpty ? nil : { path.append(.notSeen) })
            })
            if !report.onScreenUnread.isEmpty {
                rows.append(IdentifiedRow(id: "unread") {
                    reveal("unread", InsetRow(title: "On screen but not read", sub: "Kept: the scan saw a card it could not read where each would be", icon: "eye.trianglebadge.exclamationmark", value: report.onScreenUnread.count.formatted(), separator: true) { toggle("unread") }) {
                        ForEach(report.onScreenUnread, id: \.self) { id in if let e = ctx.saved[id] { Text(Fmt.brief(e.row)).paText(.secondary).foregroundStyle(Theme.ink) } }
                        Text("These were kept. The scan saw a card it could not read where each of these would be.").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                    }
                    .accessibilityIdentifier("review-on-screen-unread")
                })
            }
        }
        if !plan.stationedSeen.isEmpty {
            rows.append(IdentifiedRow(id: "stationed") {
                reveal("stationed", InsetRow(title: "Stationed, seen but not read", sub: "Their cards show no CP or HP while they are away", icon: "mappin.and.ellipse", value: plan.stationedSeen.count.formatted(), separator: true) { toggle("stationed") }) {
                    ForEach(plan.stationedSeen, id: \.item) { m in if let e = ctx.saved[m.savedId] { Text(Fmt.brief(e.row)).paText(.secondary).foregroundStyle(Theme.ink) } }
                    Text("Their cards show no CP or HP while they are away.").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                }
                .accessibilityIdentifier("review-stationed-seen")
            })
        }
        return rows
    }

    private struct NoteReason { var text: String; var count: Int }
    /// The rows the reader only made a note about (nothing to do), grouped by what the note says.
    private var noteReasons: [NoteReason] {
        var counts = [String: Int](), order = [String]()
        for r in review.outcome.scan.rows { for f in r.noteFlags { let t = FlagInfo.explainNote(f); if counts[t] == nil { order.append(t) }; counts[t, default: 0] += 1 } }
        return order.map { NoteReason(text: $0, count: counts[$0] ?? 0) }.sorted { $0.count > $1.count }
    }

    // MARK: Scan kind

    @ViewBuilder private var scanKind: some View {
        Panel(spacing: 10) {
            Text("Scan kind").paText(.rowTitle).foregroundStyle(Theme.ink)
            Picker("Scan kind", selection: Binding(get: { review.kind }, set: { k in
                // A full scan the advice refused: say why, and ask first.
                if k == .full, let why = review.advice, !why.fullIsSound, let reason = why.reason { confirmFull = reason } else { Task { await model.setReviewKind(k) } }
            })) {
                Text("Full scan").tag(BoxStore.Kind.full)
                Text("Add and update").tag(BoxStore.Kind.partial)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Scan details

    @ViewBuilder private var scanDetails: some View {
        let outcome = review.outcome
        let unmatched = outcome.scan.unmatched
        Panel(padding: 0, spacing: 0) {
            reveal("details", InsetRow(title: "Scan details", sub: "Pace, frames, time", icon: "info.circle", showsChevron: true, separator: false) { toggle("details") }) {
                detail("Scan time", Fmt.duration(outcome.duration))
                detail("Frames read", "\(outcome.readings)")
                if let pace = outcome.pace { detail("Pace", "about \(String(format: "%.1f", pace.medianPeriod)) s per Pokémon") }
                detail("Box", review.account)
                detail("Pokémon read", outcome.scan.rows.count.formatted())
                detail("Cards the scan could not read", "\(BoxMerge.unreadCount(plan))")
                if unmatched.isEmpty { Text("Every Pokémon on screen was read.").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted) }
                ForEach(Array(unmatched.enumerated()), id: \.offset) { _, u in Text(Fmt.unmatched(u)).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.ink) }
                if !plan.partMatches.isEmpty {
                    Text("Part reads matched by HP (\(plan.partMatches.count))").paText(.rowTitle).foregroundStyle(Theme.ink).padding(.top, 6)
                    ForEach(plan.partMatches, id: \.scanned) { m in Text(BoxMerge.partMatchLine(plan, m, saved: ctx.saved[m.savedId])).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.ink) }
                }
                if !outcome.notices.isEmpty {
                    Text("Notes from the reader").paText(.rowTitle).foregroundStyle(Theme.ink).padding(.top, 6)
                    ForEach(outcome.notices, id: \.self) { Text($0).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted) }
                }
                if model.reportsEnabled {
                    PillButton("Make scans better", systemImage: "paperplane", style: .tint) { model.reportTarget = .review }.padding(.top, 6)
                }
            }
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).paText(.secondary).foregroundStyle(Theme.ink)
            Spacer(minLength: 12)
            Text(value).paText(.secondary).foregroundStyle(Theme.muted).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: pieces

    private func heading(_ title: String, count: Int? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.figtree(18, .heavy, relativeTo: .title3)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
            Spacer()
            if let count { Text(count.formatted()).font(.figtree(14, .bold, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.muted) }
        }
        .padding(.horizontal, 6).padding(.top, 8)
    }

    private func toggle(_ key: String) {
        if open.contains(key) { open.remove(key) } else { open.insert(key) }
    }

    /// An InsetRow with its list under it while open.
    @ViewBuilder private func reveal<R: View, C: View>(_ key: String, _ row: R, @ViewBuilder content: () -> C) -> some View {
        row
        if open.contains(key) { RevealList { content() } }
    }
}

/// A row with a stable identity, so a list of rows built conditionally can go in one ForEach.
struct IdentifiedRow: Identifiable, View {
    let id: String
    let build: () -> AnyView
    init<V: View>(id: String, @ViewBuilder _ build: @escaping () -> V) { self.id = id; self.build = { AnyView(build()) } }
    var body: some View { build() }
}
