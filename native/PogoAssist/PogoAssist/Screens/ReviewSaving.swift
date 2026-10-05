import SwiftUI
import PogoBox
import PogoReader

/// The four numbers "What saving does" shows, read from the cached `SavePreview` and nowhere else, so the full segment and the pinned bar can never differ.
struct SavingCounts: Equatable {
    var new: Int, updated: Int, same: Int, removed: Int, open: Int

    init(_ p: SavePreview) { new = p.newRows.count; updated = p.updated.count; same = p.same.count; removed = p.removed.count; open = p.open }

    /// "What saving does: 15 new, 3 updated, 11 same, 1 removed" (Removed only when it is not zero), then the questions still open.
    var spoken: String {
        var parts = ["\(new.formatted()) new", "\(updated.formatted()) updated", "\(same.formatted()) same"]
        if removed > 0 { parts.append("\(removed.formatted()) removed") }
        var s = "What saving does: " + parts.joined(separator: ", ")
        if open > 0 { s += ". " + (open == 1 ? "1 question not answered yet" : "\(open.formatted()) questions not answered yet") }
        return s
    }
}

/// The second segment of the scan result: what Save will do with the scan's Pokémon, given the answers and marks so far.
struct ReviewSavingSection: View {
    let ctx: ReviewContext
    /// Which rows are expanded; kept by the result screen, because the lazy list drops this view's own state when it is scrolled far away.
    @Binding var open: Set<String>

    private var plan: BoxMerge.Plan { ctx.plan }

    var body: some View {
        let p = ctx.savePreview
        VStack(spacing: Theme.Space.panelGap) {
            HStack(alignment: .firstTextBaseline) {
                Text("What saving does").font(.figtree(18, .heavy, relativeTo: .title3)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .padding(.horizontal, 6).padding(.top, 8)
            Panel(padding: 0, spacing: 0) {
                savingRow("new", "New", "plus.circle", p.newRows.count) {
                    ForEach(p.newRows, id: \.self) { i in
                        if let base = plan.megaBases[i] {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(ctx.plan.scanned[i].title), IVs \(Fmt.ivs(ctx.plan.scanned[i].ivs))").paText(.secondary).foregroundStyle(Theme.ink)
                                Text("Mega evolved when scanned. It will be saved as \(ctx.gm?.byId[base]?.name ?? base) with no CP, HP or level, marked to check, because the Mega values are temporary.").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                            }
                        } else { Text(Fmt.brief(plan.scanned[i])).paText(.secondary).foregroundStyle(Theme.ink) }
                    }
                }
                savingRow("updated", "Updated", "arrow.up.circle", p.updated.count) {
                    ForEach(p.updated, id: \.scanned) { u in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ctx.saved[u.savedId]?.row.title ?? "Pokémon").paText(.secondary).foregroundStyle(Theme.ink)
                            Text(change(u)).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                        }
                    }
                }
                savingRow("same", "Same", "equal.circle", p.same.count, last: p.removed.isEmpty) {
                    ForEach(p.same, id: \.scanned) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Fmt.brief(plan.scanned[m.scanned])).paText(.secondary).foregroundStyle(Theme.ink)
                            if m.mega && !GameSearch.noLevelFits(plan.scanned[m.scanned].flags) {
                                // The engine keeps the Mega values only from a CP that was read.
                                let own = "Mega evolved when scanned. The saved \(ctx.saved[m.savedId]?.row.title ?? "Pokémon") keeps its own values"
                                Text(plan.scanned[m.scanned].cp > 0 ? own + " and keeps the Mega values read now as its Mega form." : own + ".").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                            }
                            else if m.effect == .keepsIVsAndFlags { Text("The saved IVs are kept and it is marked to check.").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted) }
                        }
                    }
                }
                if !p.removed.isEmpty {
                    let why = p.markedRemoved > 0 && p.joined > 0 ? "Marked in Not seen, and Mega entries joined" : (p.joined > 0 ? "Mega entries joined into their normal entry" : "Marked in Not seen")
                    InsetRow(title: "Removed", sub: why, icon: "trash", iconBackground: Theme.off, iconInk: Theme.red, value: p.removed.count.formatted(), separator: false)
                }
            }
            if p.open > 0 {
                // Save is locked until every question has an answer: the numbers above are for the answers given so far.
                Text(p.open == 1 ? "1 question not answered yet. It is not counted above." : "\(p.open) questions not answered yet. They are not counted above.")
                    .paText(.secondary).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
            }
        }
    }

    @ViewBuilder private func savingRow<C: View>(_ key: String, _ title: String, _ icon: String, _ count: Int, last: Bool = false, @ViewBuilder content: () -> C) -> some View {
        InsetRow(title: title, icon: icon, value: count.formatted(), showsChevron: count > 0, separator: !last, action: count > 0 ? { toggle(key) } : nil)
        if open.contains(key) { RevealList { content() } }
    }

    private func toggle(_ key: String) {
        if open.contains(key) { open.remove(key) } else { open.insert(key) }
    }

    private func change(_ u: SavePreview.Change) -> String {
        let s = plan.scanned[u.scanned], old = ctx.saved[u.savedId]?.row
        switch u.reason {
        case .poweredUp: return "Powered up: CP \(old?.cp ?? 0) to \(s.cp)"
        case .evolved: return "Evolved from \(old?.name ?? "?"): now \(s.title), CP \(s.cp)"
        case .ivsNowRead: return "IVs now read: \(Fmt.ivs(s.ivs))"
        case .megaToBase:
            var keeps = false
            if let q = ctx.unsure(u.scanned), let e = ctx.saved[u.savedId], let gm = ctx.gm { keeps = BoxMerge.keepsSavedMegaAsMegaForm(plan, q, candidate: e, gameMaster: gm) }
            return "Saved in its Mega form before; now \(s.title), CP \(s.cp)" + (keeps ? ". The Mega values it was saved with are kept as its Mega form." : "")
        case .chosen: return "Matched by you: now CP \(s.cp)"
        }
    }
}

/// The slim bar pinned under the top bar once the full segment has scrolled out of view: the same four icons and numbers, one VoiceOver element, a tap scrolls back.
struct SavingBar: View {
    let counts: SavingCounts
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private var items: [(icon: String, value: Int, red: Bool)] {
        var a: [(String, Int, Bool)] = [("plus.circle", counts.new, false), ("arrow.up.circle", counts.updated, false), ("equal.circle", counts.same, false)]
        if counts.removed > 0 { a.append(("trash", counts.removed, true)) }
        return a
    }

    var body: some View {
        Button(action: action) {
            // Four items on one line; at accessibility sizes they wrap to two lines instead of clipping.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { ForEach(0..<items.count, id: \.self) { item(items[$0]) } }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 18) { ForEach(0..<min(2, items.count), id: \.self) { item(items[$0]) } }
                    if items.count > 2 { HStack(spacing: 18) { ForEach(2..<items.count, id: \.self) { item(items[$0]) } } }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 44)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(scheme == .dark ? Theme.line : .clear, lineWidth: 1))
            .panelShadow()
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .padding(.horizontal, Theme.Space.screen).padding(.top, 4).padding(.bottom, 8)
        // The screen background behind it, fading out below, so the cards scrolling under the top edge do not show around the capsule.
        .background(LinearGradient(stops: [.init(color: Theme.bg, location: 0), .init(color: Theme.bg, location: 0.8), .init(color: Theme.bg.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(counts.spoken)
        .accessibilityHint("Scrolls up to the full list")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("review-saving-bar")
    }

    private func item(_ i: (icon: String, value: Int, red: Bool)) -> some View {
        HStack(spacing: 6) {
            Image(systemName: i.icon).font(.figtree(17, .semibold, relativeTo: .body)).foregroundStyle(i.red ? Theme.red : Theme.muted)
            Text(i.value.formatted()).font(.figtree(17, .bold, relativeTo: .body)).monospacedDigit().foregroundStyle(i.red ? Theme.red : Theme.ink)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: i.value)
        }
        .fixedSize()
    }
}
