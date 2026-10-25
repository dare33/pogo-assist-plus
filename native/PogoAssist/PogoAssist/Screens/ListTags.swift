import SwiftUI
import PogoBox

// The tiles and tags the Pokémon list, the species list and the Pokémon page share (design handoff of 22 Oct 2026, sections 1 to 3). Every figure and
// sentence comes from `BoxInsight` / `LeaguePanel` / `BoxAdvice.Fit` in PogoBox; this file only draws them.

// MARK: colours

extension BoxInsight.Activity {
    /// The Hub colours of an activity chip: raids, gym, Rocket and Max take their content type's; a league takes its own.
    private var contentType: ContentType? {
        switch self {
        case .raids: return .raids
        case .gym: return .gym
        case .rocket: return .rocket
        case .max: return .max
        case .gl, .ul, .ml: return nil
        }
    }
    var leagueColours: League? { league.flatMap(League.init(rawValue:)) }
    func ink(_ accent: Accent) -> Color { leagueColours?.ink ?? contentType?.ink(accent) ?? accent.ink }
    func tint(_ accent: Accent) -> Color { leagueColours?.tint ?? contentType?.tint(accent) ?? accent.tint }
    /// The short caps label of a tag: "RAIDS", "GL".
    var tagLabel: String { league?.uppercased() ?? title.uppercased() }
}

// MARK: a soft tag

/// A soft chip (radius 8, padding 3 by 8, 11/800): a 10 pt label with .08em tracking, and after a dimmed "·" the words. Used for the league and activity tags.
/// `border` draws a 1 pt line just inside the shape (it adds no size), which is how Good and Weak differ from Top and from each other by shape as well as colour.
struct SoftTag: View {
    let label: String
    var detail: String? = nil
    let ink: Color
    let tint: Color
    var border: Color? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        HStack(spacing: 4) {
            Text(label).font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.08 * 10)
            if let detail {
                Text("·").font(.figtree(11, .heavy, relativeTo: .caption2)).opacity(0.5)
                Text(detail).font(.figtree(11, .heavy, relativeTo: .caption2)).monospacedDigit()
            }
        }
        .foregroundStyle(ink)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(tint, in: shape)
        .overlay { if let border { shape.strokeBorder(border, lineWidth: 1) } }
    }
}

/// The Top / Good / Weak tag for an activity, three shapes: Top is the activity's ink on its tint; Good is the same, lighter: the tint at half strength with a 1 pt border in the ink at 40% (Rocket's old middle rating was
/// graphite on grey, near-identical to Weak); Weak is a plain outline in `Theme.line` with `Theme.muted` text and no fill. `Theme.muted` (6A7085) is 4.9:1 on
/// `Theme.surface` (white) in light mode, over the 4.5:1 the small text needs (computed with `Theme.contrast`; the row it sits on is `Theme.surface`).
/// `worth` nil is a copy the advice has no rating for: "Not rated", muted text with no fill or outline. `best` merges the "best for" tag of the same area into
/// this one ("RAIDS · Good · best as Tyranitar (Shadow)", "GL · Top · best: Flareon 97.2%"; the words come from `BoxInsight.bestText`).
struct WorthTag: View {
    let activity: BoxInsight.Activity
    let worth: LeaguePanel.Worth?
    var best: String? = nil
    /// False on a card that already names its activity: the chip then reads the rating alone ("TOP"), in the same three shapes.
    var showsActivity = true
    @Environment(\.accent) private var accent
    /// The middle rating is a lighter version of the top one everywhere (Greg, 25 Oct 2026): the tint at half strength and a faded ink border, the text still the
    /// full ink (more contrast, not less: a lighter ground under the same text). These are how much of the tint and of the ink it keeps.
    static let fadedTint = 0.5, fadedBorder = 0.4

    /// How much of its tint a rating keeps and whether it carries a faded ink border: Top the full tint, Good the faded one with the border, Weak and unrated
    /// their own fill untouched. The tag here and the league card's chip both read this, so a view that stopped applying it would fail the test that pins it.
    static func style(for worth: LeaguePanel.Worth?) -> (tintOpacity: Double, borderOpacity: Double?) {
        worth == .ok ? (fadedTint, fadedBorder) : (1, nil)
    }

    static func detail(_ worth: LeaguePanel.Worth?, best: String?) -> String {
        (worth?.label ?? "Not rated") + (best.map { " · " + $0 } ?? "")
    }

    var body: some View {
        let ink = activity.ink(accent), style = Self.style(for: worth)
        let detail = showsActivity ? Self.detail(worth, best: best) : nil
        let label = showsActivity ? activity.tagLabel : (worth?.label ?? "Not rated").uppercased()
        switch worth {
        case .strong?: SoftTag(label: label, detail: detail, ink: ink, tint: activity.tint(accent))
        case .ok?: SoftTag(label: label, detail: detail, ink: ink, tint: activity.tint(accent).opacity(style.tintOpacity), border: ink.opacity(style.borderOpacity ?? 0))
        case .weak?: SoftTag(label: label, detail: detail, ink: Theme.muted, tint: .clear, border: Theme.line)
        case nil: SoftTag(label: label, detail: detail, ink: Theme.muted, tint: .clear)
        }
    }
}

/// A place on the species page: "GL 1", "RAIDS 2", the activity's ink on its tint. A place is not a rating, so it is always the full tint (the rating tag stays the
/// two-shade one); the label is the same caps label as the activity's tags.
struct RankMarker: View {
    let activity: BoxInsight.Activity
    let place: Int
    @Environment(\.accent) private var accent

    var body: some View {
        Text("\(activity.tagLabel) \(place)")
            .font(.figtree(11, .heavy, relativeTo: .caption2)).tracking(0.06 * 11).monospacedDigit()
            .foregroundStyle(activity.ink(accent))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(activity.tint(accent), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// "ADVICE BUILDS IT" as the league cards draw it: an outline chip, so it does not read as a second tag.
struct BuildsChip: View {
    let text: String
    var body: some View {
        Text(text).font(.figtree(11, .bold, relativeTo: .caption2)).tracking(0.06 * 11)
            .foregroundStyle(Theme.muted).padding(.horizontal, 7).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

// MARK: league tiles

/// The three league tiles under a species' name on the Pokémon list: the species' best copy for each league under the ranking, read from the insight
/// (built once per box version, never per row). Three columns; one column from the accessibility text sizes.
struct LeagueTiles: View {
    let title: String
    let insight: BoxInsight?
    /// The advice is still being worked out ("…"); a failed advice is not, and reads "—" like a league with no rating.
    let waiting: Bool
    let pogoAssist: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The second line of a tile and its spoken words: the member, "Over cap", "IVs not read", "—" (no rating), "…" while the advice is being worked out.
    static func line(_ t: BoxInsight.Tile?, waiting: Bool) -> String {
        guard !waiting || t != nil else { return "…" }
        switch t?.status {
        case .fits?: return t?.member ?? "—"
        case .ivsNotRead?: return "IVs not read"
        case .overCap?: return "Over cap"
        case .noData?, nil: return "—"
        }
    }
    /// "97.2%" for a tile that fits.
    static func percent(_ t: BoxInsight.Tile?) -> String? { t?.status == .fits ? t?.pct.map(LeaguePanel.percent) : nil }

    /// The tiles as one sentence for the row's spoken label.
    static func spoken(title: String, insight: BoxInsight?, waiting: Bool, pogoAssist: Bool) -> String {
        LeaguePanel.keys.map { key in
            let t = insight?.tile(title: title, league: key, pogoAssist: pogoAssist)
            let value = percent(t).map { ", " + $0.dropLast() + " percent" } ?? ""
            return "\(LeaguePanel.name(key)): \(line(t, waiting: waiting))\(value)"
        }.joined(separator: ". ")
    }

    /// One column from the accessibility text sizes, three across below them (a test reads this; the tiles are hidden from accessibility, so their frames cannot be read).
    static func stacked(_ size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }

    var body: some View {
        let tiles = LeaguePanel.keys.map { key in (key, insight?.tile(title: title, league: key, pogoAssist: pogoAssist)) }
        Group {
            if Self.stacked(typeSize) {
                VStack(spacing: 6) { ForEach(tiles, id: \.0) { tile($0.0, $0.1) } }
            } else {
                HStack(spacing: 6) { ForEach(tiles, id: \.0) { tile($0.0, $0.1) } }
            }
        }
        .accessibilityHidden(true)
    }

    private func tile(_ key: String, _ t: BoxInsight.Tile?) -> some View {
        let league = League(rawValue: key) ?? .gl
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let line = Self.line(t, waiting: waiting)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(key.uppercased()).font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.08 * 10)
                    .foregroundStyle(league.ink)
                Spacer(minLength: 2)
                if let p = Self.percent(t) { Text(p).font(.figtree(12, .heavy, relativeTo: .caption)).monospacedDigit().foregroundStyle(league.ink) }
            }
            Text(line).font(.figtree(12, .semibold, relativeTo: .caption)).foregroundStyle(t?.status == .fits ? Theme.ink : Theme.muted)
                .lineLimit(1).truncationMode(.tail)
        }
        .padding(.vertical, 6).padding(.trailing, 8).padding(.leading, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(league.tint)
        .overlay(alignment: .leading) { Rectangle().fill(league.dot).frame(width: 3) }
        .clipShape(shape)
    }
}
