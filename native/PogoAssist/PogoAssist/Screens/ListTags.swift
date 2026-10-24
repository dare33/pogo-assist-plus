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
struct SoftTag: View {
    let label: String
    var detail: String? = nil
    let ink: Color
    let tint: Color

    var body: some View {
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
        .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// The Strong / OK / Weak tag for an activity: the activity's colours for Strong and OK, the muted off tone for Weak.
struct WorthTag: View {
    let activity: BoxInsight.Activity
    let worth: LeaguePanel.Worth
    @Environment(\.accent) private var accent

    var body: some View {
        SoftTag(label: activity.tagLabel, detail: worth.label, ink: worth == .weak ? Theme.muted : activity.ink(accent), tint: worth == .weak ? Theme.off : activity.tint(accent))
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
    let pogoAssist: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The second line of a tile and its spoken words: the member, "Over cap", "IVs not read", "—" (no rating), "…" while the advice is being worked out.
    static func line(_ t: BoxInsight.Tile?, ready: Bool) -> String {
        guard ready else { return "…" }
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
    static func spoken(title: String, insight: BoxInsight?, pogoAssist: Bool) -> String {
        LeaguePanel.keys.map { key in
            let t = insight?.tile(title: title, league: key, pogoAssist: pogoAssist)
            let value = percent(t).map { ", " + $0.dropLast() + " percent" } ?? ""
            return "\(LeaguePanel.name(key)): \(line(t, ready: insight != nil))\(value)"
        }.joined(separator: ". ")
    }

    var body: some View {
        let tiles = LeaguePanel.keys.map { key in (key, insight?.tile(title: title, league: key, pogoAssist: pogoAssist)) }
        Group {
            if typeSize.isAccessibilitySize {
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
        let line = Self.line(t, ready: insight != nil)
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
