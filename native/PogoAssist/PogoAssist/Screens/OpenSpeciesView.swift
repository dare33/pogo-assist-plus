import SwiftUI
import PogoBox

/// Where a copy goes: its Pokémon page, with a league's view chosen when the copy was tapped under TOP PVP (READBACK 3.4).
struct CopyRoute: Hashable {
    var id: String
    var league: String?
}

/// The words VoiceOver reads for a build mark; the picture is `BuildMarkView`.
enum BuildMarkWords {
    /// A species row: "Upgrade available: 2 builds to do, 12k dust", or "Full strength"; nil without a build.
    static func species(_ mark: MyPokemon.BuildMark) -> String? {
        switch mark {
        case .upgrade(let cost, let n): return "Upgrade available: \(n) \(n == 1 ? "build" : "builds") to do" + (cost.map { ", " + $0.words } ?? "")
        case .fullStrength: return "Full strength"
        case .none: return nil
        }
    }

    /// One copy: the first build with work left, as the Hub words it, with the cost the copy's mark shows (the dust of ALL its builds with work left in total, or
    /// their candy): "Upgrade available: power up Umbreon, 12k dust". "Full strength" when every build is built; nil without a build.
    static func copy(_ builds: [BoxAdvice.Build]) -> String? {
        switch MyPokemon.copyMark(builds: builds) {
        case .none: return nil
        case .fullStrength: return "Full strength"
        case .upgrade(let cost, _):
            let first = builds.first { !HubTeams.isBuilt($0) }
            return "Upgrade available: " + (first.map(HubTeams.todo) ?? "build") + (cost.map { ", " + $0.words } ?? "")
        }
    }
}

/// A species opened in place on My Pokémon (design pass 3, D1 and D12): TOP PVP (the two copies with the best Great or Ultra League card), TOP IVS (the next two by
/// IVs, each with its keep or transfer tag), then "See all N copies" for the species list. Fewer than two copies for a caption shows what there is; a caption with
/// none is left out. The rules are `MyPokemon`'s (pinned by `swift test`); this lays them out.
struct OpenSpeciesView: View {
    let route: SpeciesRoute
    /// The species' copies that pass the search, in the species list's order (best IVs first).
    let copies: [BoxIndex.Item]
    /// The advice, once ready for this box version; nil while it is worked out or has failed.
    let advice: BoxAdvice?
    let adviceState: InsightKey.State
    let pogoAssist: Bool
    let buildsByEntry: [String: [BoxAdvice.Build]]
    @Environment(\.accent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let byId = Dictionary(copies.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let pvp = advice.map { a in MyPokemon.topPvP(copies: copies.map { ($0.id, a.leagues(for: $0.id)) }, pogoAssist: pogoAssist) } ?? []
        let ivs = MyPokemon.topIVs(listed: copies.map { MyPokemon.ListedCopy(id: $0.id, ivSum: $0.ivSum) }, excluding: Set(pvp.map(\.copyId)))
        VStack(alignment: .leading, spacing: 2) {
            if !pvp.isEmpty {
                caption("TOP PVP")
                ForEach(pvp, id: \.copyId) { top in
                    if let it = byId[top.copyId] { pvpRow(it, top.standing) }
                }
            } else if advice == nil && adviceState != .failed {
                // The PvP picks come from the advice: say so rather than show a group that is only missing for now.
                Text("PvP picks: working out advice…").font(.figtree(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 8).padding(.top, 8).accessibilityIdentifier("top-pvp-waiting")
            }
            if !ivs.isEmpty {
                caption("TOP IVS")
                ForEach(ivs, id: \.self) { id in
                    if let it = byId[id] { ivsRow(it) }
                }
            }
            seeAll
        }
        .padding(.horizontal, 10).padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.6).foregroundStyle(Theme.faint)
            .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(text == "TOP PVP" ? "top-pvp-caption" : "top-ivs-caption")
    }

    // MARK: copy rows

    private func pvpRow(_ it: BoxIndex.Item, _ s: MyPokemon.PvPStanding) -> some View {
        let league = League(rawValue: s.league) ?? .gl
        let score = LeaguePanel.oneDecimal(s.score), rank = "IV #\(LeaguePanel.grouped(s.ivRank))"
        let sub = FlowLayout(spacing: 4) {
            Text(s.league.uppercased()).font(.figtree(12, .bold, relativeTo: .caption)).foregroundStyle(league.ink)
            Text("·")
            Text(s.pick)
            GradedNumber(score, s.scoreGrade, size: 12, plain: .medium, relativeTo: .caption)
            Text("·")
            GradedNumber(rank, s.rankGrade, size: 12, plain: .medium, relativeTo: .caption)
        }
        .font(.figtree(12, .medium, relativeTo: .caption)).foregroundStyle(Theme.muted)
        var spoken = "\(LeaguePanel.name(s.league)): \(s.pick) \(score)"
        if !s.scoreGrade.spoken.isEmpty { spoken += ", \(s.scoreGrade.spoken) score" }
        spoken += ". IV rank \(LeaguePanel.grouped(s.ivRank))"
        if !s.rankGrade.spoken.isEmpty { spoken += ", \(s.rankGrade.spoken) rank" }
        return copyRow(it, route: CopyRoute(id: it.id, league: s.league), sub: sub, spokenSub: spoken, identifier: "top-pvp-row")
    }

    private func ivsRow(_ it: BoxIndex.Item) -> some View {
        let tag = advice.flatMap { MyPokemon.keepTag($0.entries(for: it.id)) }
        let sub = Text(tag?.text ?? "").font(.figtree(12, .medium, relativeTo: .caption)).foregroundStyle(Theme.muted)
        return copyRow(it, route: CopyRoute(id: it.id, league: nil), sub: tag == nil ? nil : sub, spokenSub: tag?.text, identifier: "top-ivs-row")
    }

    /// CP, the IVs with their graded %, the sub line and the copy's own build mark, on `surface2` (radius 14). A tap opens the copy's page.
    private func copyRow<Sub: View>(_ it: BoxIndex.Item, route: CopyRoute, sub: Sub?, spokenSub: String?, identifier: String) -> some View {
        let builds = buildsByEntry[it.id] ?? []
        let mark = MyPokemon.copyMark(builds: builds)
        let ivGrade = MyPokemon.ivGrade(sum: it.ivSum)
        var spoken = it.cp > 0 ? "CP \(it.cp)" : "CP not known"
        spoken += ", " + (it.ivs.map { "IVs \($0), \(it.pct ?? 0) percent" } ?? "IVs not read")
        if let spokenSub { spoken += ". " + spokenSub }
        if let words = BuildMarkWords.copy(builds) { spoken += ". " + words }
        return NavigationLink(value: route) {
            let info = VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    if let ivs = it.ivs {
                        Text("\(ivs) ·").font(.figtree(14, .bold, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.ink)
                        GradedNumber("\(it.pct ?? 0)%", ivGrade, size: 14, plain: .bold, relativeTo: .subheadline).foregroundStyle(Theme.ink)
                    } else {
                        Text("IVs not read").font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                    }
                }
                if let sub { sub }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            let markView = BuildMarkView(mark: mark, upgradeLabel: BuildMarkWords.copy(builds) ?? "Upgrade available")
            Group {
                if typeSize.isAccessibilitySize {
                    // The CP, the IVs and the mark no longer fit side by side: they stack, so no figure is broken across lines.
                    VStack(alignment: .leading, spacing: 6) {
                        CPFigure(cp: it.cp).fixedSize(horizontal: true, vertical: false)
                        markView
                        info
                    }
                } else {
                    HStack(spacing: 10) { CPFigure(cp: it.cp); info; markView }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }

    // MARK: see all

    private var seeAll: some View {
        NavigationLink(value: route) {
            HStack(spacing: 4) {
                Text("See all \(copies.count.formatted()) \(copies.count == 1 ? "copy" : "copies")").font(.figtree(14, .bold, relativeTo: .subheadline))
                Image(systemName: "chevron.right").font(.figtree(12, .heavy)).accessibilityHidden(true)
            }
            .foregroundStyle(accent.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(accent.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .padding(.top, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("See all \(copies.count.formatted()) \(route.title)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("see-all")
    }
}
