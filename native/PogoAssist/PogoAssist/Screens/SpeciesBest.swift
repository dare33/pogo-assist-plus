import SwiftUI
import PogoBox

/// The "your best" section at the top of a species page: one card for each use the species has a Top or Good copy for, showing that use's first place. Every figure comes from
/// `BoxInsight` (the places are worked out once per box version), so the card, the species' league tile and the row markers cannot disagree.
struct BestCard: Identifiable, Equatable {
    var activity: BoxInsight.Activity
    var copyId: String
    var cp: Int
    var pct: Int?
    var worth: LeaguePanel.Worth
    /// "as Flareon" for a league or an activity with a table entry; "needs a Dynamax copy" for Max; nil otherwise.
    var detail: String?
    var id: String { activity.rawValue }
    /// What a card is drawn on: the rows' own surface, which is what keeps Top, Good and Weak chips legible there (the colour test reads this).
    static let ground = Theme.surface

    /// "Great League" for a league, "Raids" for an activity.
    var name: String { activity.league.map(LeaguePanel.name) ?? activity.title }

    var spoken: String {
        "\(name), best: " + (cp > 0 ? "CP \(cp)" : "CP not known") + (pct.map { ", \($0) percent" } ?? "") + ", \(worth.label)" + (detail.map { ", " + $0 } ?? "")
    }

    /// The cards for a species title, in chip order; empty when no use has a first place. Each card takes the first id in `top` that is still in the index, so a rebuild that
    /// has dropped a copy (the insight is kept on show until its replacement is built) moves the card on to the next place instead of losing it.
    static func cards(title: String, insight: BoxInsight?, index: BoxIndex, pogoAssist: Bool) -> [BestCard] {
        guard let insight else { return [] }
        let members = index.members(of: title, query: .none, chip: .all)
        return BoxInsight.Activity.allCases.compactMap { a in
            guard let (id, it) = insight.top(title: title, a, pogoAssist: pogoAssist).lazy.compactMap({ id in members.first { index.items[$0].id == id }.map { (id, index.items[$0]) } }).first,
                  let copy = insight.copies[id], let worth = copy.worth(a, pogoAssist: pogoAssist) else { return nil }
            var detail: String?
            if let key = a.league { detail = copy.slot(key, pogoAssist: pogoAssist).map { "as " + $0.member } }
            else if a == .max { detail = "needs a Dynamax copy" }
            else if let i = a.area.flatMap({ BoxInsight.areas.firstIndex(of: $0) }), copy.asNames.indices.contains(i) { detail = copy.asNames[i].map { "as " + $0 } }
            // "as Moltres" under a Moltres page says nothing: the line is for a copy rated as another Pokémon (a Shadow form, or a different evolution).
            if let d = detail, d.hasPrefix("as "), d.dropFirst(3).lowercased() == title.lowercased() { detail = nil }
            return BestCard(activity: a, copyId: id, cp: it.cp, pct: it.pct, worth: worth, detail: detail)
        }
    }
}

struct SpeciesBestSection: View {
    let cards: [BestCard]
    /// Select mode: the cards stay in view, dimmed and not tappable (a tap there means "pick a row").
    let inert: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accent) private var accent

    /// One column from the accessibility text sizes, two across below them (a test reads this).
    static func columns(_ size: DynamicTypeSize) -> Int { size.isAccessibilitySize ? 1 : 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR BEST").font(.figtree(12, .bold, relativeTo: .caption)).tracking(0.08 * 12).foregroundStyle(Theme.muted)
                .padding(.horizontal, 6).accessibilityAddTraits(.isHeader)
            let n = Self.columns(typeSize)
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(Array(stride(from: 0, to: cards.count, by: n)), id: \.self) { start in
                    GridRow {
                        ForEach(Array(cards[start..<min(start + n, cards.count)])) { card($0) }
                        if n == 2, start + 1 >= cards.count { Color.clear.frame(height: 0) }
                    }
                }
            }
            .opacity(inert ? 0.5 : 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("species-best")
    }

    @ViewBuilder private func card(_ c: BestCard) -> some View {
        if inert {
            face(c).accessibilityElement(children: .ignore).accessibilityLabel(c.spoken + ", not available while selecting")
                .accessibilityIdentifier("species-best-\(c.activity.rawValue)")
        } else {
            NavigationLink(value: c.copyId) { face(c) }.buttonStyle(PressStyle())
                .accessibilityElement(children: .ignore).accessibilityLabel(c.spoken)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("species-best-\(c.activity.rawValue)")
        }
    }

    private func face(_ c: BestCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(c.name.uppercased()).font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.08 * 10)
                .foregroundStyle(c.activity.ink(accent)).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                CPFigure(cp: c.cp)
                if let p = c.pct { Text("\(p)%").font(.figtree(13, .semibold, relativeTo: .footnote)).monospacedDigit().foregroundStyle(Theme.muted) }
            }
            WorthTag(activity: c.activity, worth: c.worth, showsActivity: false)
            if let d = c.detail {
                Text(d).font(.figtree(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, 10).padding(.horizontal, 12)
        // The card is the page's surface with a 2 pt outline in the activity's ink, so the chip on it (tint, or tint and border) reads exactly as it does on a row.
        .background(BestCard.ground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(c.activity.ink(accent), lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
