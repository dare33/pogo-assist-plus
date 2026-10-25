import SwiftUI
import PogoBox

// The Raids, Gym, Rocket and Max tabs of the Pokémon page (design pass 3, D21 to D25, CONCEPTS rules 11 to 14). Each is a panel with a heading in the activity's
// colour, then one activity card per member of the copy's reach. Every figure and sentence comes from `PokemonActivities` and `PokemonPage` (PogoBox).

// MARK: shared card pieces

/// The panel every activity tab sits in: the heading in the activity's colour (13/800) and, on the right, a muted note (12/600).
private struct ActivityPanel<Content: View>: View {
    let title: String
    var note: String?
    let ink: Color
    let identifier: String
    @ViewBuilder var content: Content

    var body: some View {
        Panel(padding: 16, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.figtree(13, .heavy, relativeTo: .footnote)).tracking(0.5).foregroundStyle(ink).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let note { Text(note).font(.figtree(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.muted) }
            }
            content
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// An activity card (`surface2`, radius 18, padding 14).
private struct ActivityCard<Content: View>: View {
    var spacing: CGFloat = 10
    let identifier: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifier)
    }
}

/// The card's first line: the name 18/800 with its type icons and, on the right, whatever trails (the tier chip).
private struct CardTitle<Trailing: View>: View {
    let name: String
    let types: [String]
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(name).font(.figtree(18, .heavy, relativeTo: .headline)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            TypeIcons(types: types, size: 16)
            Spacer(minLength: 4)
            trailing
        }
    }
}

/// This copy's plan as a `surface` block: the title ("Planned for this copy"), the work in one line and the cost on the right (or the Full strength tick).
private struct PlanBlock: View {
    let title: String
    let work: String?
    let mark: MyPokemon.BuildMark
    var label: String?
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                if let work { Text(work).font(.figtree(12, .medium, relativeTo: .caption)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 4)
            PlanMark(mark: mark, label: label)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, work].compactMap { $0 }.joined(separator: ". ") + Self.markWords(mark, label))
        .accessibilityIdentifier("plan-block")
    }

    private static func markWords(_ mark: MyPokemon.BuildMark, _ label: String?) -> String {
        switch mark {
        case .fullStrength: return ". Full strength"
        case .upgrade(let cost, _): return ". " + (label ?? "Upgrade available") + (cost.map { ", " + $0.words } ?? "")
        case .none: return ""
        }
    }
}

/// A plan block from a plan on a card.
private func planBlock(_ plan: PokemonActivities.Plan, title: String) -> PlanBlock {
    let m = PokemonPage.planMark(plan.build, built: plan.built)
    return PlanBlock(title: title, work: plan.built ? nil : PokemonPage.workLine(plan.build), mark: m.mark, label: m.label)
}

private func mutedLine(_ text: String, size: CGFloat = 13, weight: Font.Weight = .medium) -> some View {
    Text(text).font(.figtree(size, weight, relativeTo: .footnote)).foregroundStyle(Theme.muted).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
}

private func capitalised(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

// MARK: Raids

struct RaidsTab: View {
    let copy: BoxEntry
    let family: String
    let cards: [PokemonActivities.RaidCard]
    @Environment(\.accent) private var accent

    var body: some View {
        ActivityPanel(title: "RAIDS", note: "\(family) family", ink: ContentType.raids.ink(accent), identifier: "raids-tab") {
            if cards.isEmpty { mutedLine(PokemonPage.emptyLine(.raids), size: 14).accessibilityIdentifier("tab-empty") }
            ForEach(Array(cards.enumerated()), id: \.offset) { n, c in card(c, n: n) }
        }
    }

    private func card(_ c: PokemonActivities.RaidCard, n: Int) -> some View {
        ActivityCard(identifier: "raids-card-\(n)") {
            CardTitle(name: c.member.name, types: c.member.types) { TierChip(tier: c.tier, type: .raids) }
            HStack(spacing: 6) {
                TypeIcon(type: c.type, size: 16)
                Text("\(capitalised(c.type)) attacker · \(c.role.rawValue)").font(.figtree(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.orangeInk)
            }
            .padding(.leading, 5).padding(.trailing, 10).padding(.vertical, 4)
            .background(Theme.orangeTint, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(capitalised(c.type)) attacker, \(c.role.rawValue)")
            if case .mine(let plan) = c.plan { planBlock(plan, title: PokemonPage.planTitle(plan)) }
            else { mutedLine(PokemonPage.raidsOtherLine(c)) }
            if !c.counters.isEmpty { counters(c) }
        }
    }

    private func counters(_ c: PokemonActivities.RaidCard) -> some View {
        let rows = c.counters.map(\.entry.row)
        return VStack(alignment: .leading, spacing: 0) {
            CapsCaption("COUNTERS").padding(.bottom, 4)
            ForEach(Array(c.counters.enumerated()), id: \.offset) { _, b in
                let name = PokemonActivities.shortName(b.entry.row, among: rows), chip = HubRaidsModel.kindChip(b.entry.row.kind)
                HStack(spacing: 8) {
                    Text(name).font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
                    if !chip.isEmpty {
                        Text(chip).font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.4).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 7).padding(.vertical, 2).background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    if b.isNow { Text("NOW").font(.figtree(11, .heavy, relativeTo: .caption2)).foregroundStyle(accent.ink).frame(minWidth: 64, alignment: .trailing) }
                    else { Text(b.when).font(.figtree(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.muted).frame(minWidth: 64, alignment: .trailing) }
                }
                .frame(minHeight: 40)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(name), \(chip.isEmpty ? "" : chip + ", ")\(b.isNow ? "now" : b.when)")
                .accessibilityIdentifier("raids-counter")
            }
        }
    }
}

// MARK: Gym

struct GymTab: View {
    let copy: BoxEntry
    let family: String
    let cards: [PokemonActivities.GymCard]
    let top: PokemonActivities.TopDefender?
    @Environment(\.accent) private var accent

    var body: some View {
        ActivityPanel(title: "GYM BATTLES", note: "Defending", ink: ContentType.gym.ink(accent), identifier: "gym-tab") {
            if cards.isEmpty { mutedLine(PokemonPage.emptyLine(.gym), size: 14).accessibilityIdentifier("tab-empty") }
            ForEach(Array(cards.enumerated()), id: \.offset) { n, c in card(c, n: n) }
        }
    }

    private func card(_ c: PokemonActivities.GymCard, n: Int) -> some View {
        ActivityCard(spacing: 12, identifier: "gym-card-\(n)") {
            CardTitle(name: c.member.name, types: c.member.types) { TierChip(tier: c.tier, type: .gym) }
            if let bulk = c.bulk.value {
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        CapsCaption("BULK")
                        Text(PokemonActivities.bulkText(bulk)).font(.figtree(24, .heavy, relativeTo: .title2)).monospacedDigit().foregroundStyle(Theme.ink)
                    }
                    Spacer(minLength: 8)
                    if c.isTop { Text("Your top defender").font(.figtree(15, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.greenInk) }
                    else if let share = c.share { Text("\(share)% of the top").font(.figtree(15, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.greenInk) }
                }
                if let fraction = c.barFraction ?? (c.isTop ? 1 : nil) { bar(fraction, c) }
            } else {
                // Nothing is assumed: an unread level or unread IVs give no figure, and the card says which.
                VStack(alignment: .leading, spacing: 1) {
                    CapsCaption("BULK")
                    Text(PokemonActivities.bulkWording(c.bulk).capitalizedFirst).font(.figtree(17, .heavy, relativeTo: .headline)).foregroundStyle(Theme.muted)
                }
            }
            if let plan = c.plan { planBlock(plan, title: PokemonPage.gymPlanTitle(plan)) }
            else if !c.isTop { mutedLine("Not one of your top defenders", size: 13, weight: .semibold) }
        }
    }

    private func bar(_ fraction: Double, _ c: PokemonActivities.GymCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                Capsule().fill(Theme.off).overlay(alignment: .leading) { Capsule().fill(Theme.green).frame(width: g.size.width * min(max(c.isTop ? 1 : fraction, 0), 1)) }
                    .clipShape(Capsule())
            }
            .frame(height: 8)
            .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline) {
                Text("This copy, level \(Fmt.level(copy.row) ?? "not read")")
                Spacer(minLength: 8)
                if !c.isTop, let top { Text("\(top.name) \(PokemonActivities.bulkText(top.bulk))") }
            }
            .font(.figtree(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.muted)
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: Rocket

struct RocketTab: View {
    let cards: [PokemonActivities.RocketCard]
    @Environment(\.accent) private var accent

    var body: some View {
        ActivityPanel(title: "TEAM GO ROCKET · WHAT IT BEATS", ink: ContentType.rocket.ink(accent), identifier: "rocket-tab") {
            if cards.isEmpty { mutedLine(PokemonPage.emptyLine(.rocket), size: 14).accessibilityIdentifier("tab-empty") }
            ForEach(Array(cards.enumerated()), id: \.offset) { n, c in card(c, n: n) }
            mutedLine("Type advantage from the Pokémon's own types; your export has no moves, so the moves that would do the hitting are not checked.")
                .accessibilityIdentifier("rocket-note")
        }
    }

    private func card(_ c: PokemonActivities.RocketCard, n: Int) -> some View {
        ActivityCard(spacing: 8, identifier: "rocket-card-\(n)") {
            CardTitle(name: c.member.name, types: c.member.types) {
                if let tier = c.tier { TierChip(tier: tier, type: .rocket) }
                if !c.gruntTypes.isEmpty {
                    Text("\(c.gruntTypes.count) grunt\(c.gruntTypes.count == 1 ? "" : "s")").font(.figtree(11, .heavy, relativeTo: .caption2)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(Theme.off, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            if !c.gruntTypes.isEmpty {
                HStack(spacing: 6) {
                    Text("Grunts:").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                    TypeIcons(types: c.gruntTypes, size: 16)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Beats grunt types: " + c.gruntTypes.map(capitalised).joined(separator: ", "))
            }
            if !c.leaderSlots.isEmpty { mutedLine("Leaders: " + PokemonPage.leaderSlotsText(c.leaderSlots)) }
            if let plan = c.plan { planBlock(plan, title: PokemonPage.planTitle(plan)) }
        }
    }
}

// MARK: Max

struct MaxTab: View {
    let copy: BoxEntry
    let family: String
    let cards: [PokemonActivities.MaxCard]
    let battles: [PokemonActivities.MaxBattle]
    @Environment(\.accent) private var accent

    var body: some View {
        ActivityPanel(title: "MAX BATTLES", note: "\(family) family", ink: ContentType.max.ink(accent), identifier: "max-tab") {
            // The Dynamax state comes first: the verdicts below read NEEDS DYNAMAX until the mark is on.
            (Text(PokemonPage.dynamaxLine(copy.row) + " ").bold().foregroundStyle(Theme.ink)
                + Text("Only a copy caught as Dynamax can join Max battles; mark it with the Dynamax icon at the top once you have checked in the game.").foregroundStyle(Theme.muted))
                .font(.figtree(13, .medium, relativeTo: .footnote)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("max-dynamax-line")
            if cards.isEmpty { mutedLine(PokemonPage.emptyLine(.max), size: 14).accessibilityIdentifier("tab-empty") }
            ForEach(Array(cards.enumerated()), id: \.offset) { n, c in card(c, n: n) }
            if !battles.isEmpty { battleList }
        }
    }

    private func card(_ c: PokemonActivities.MaxCard, n: Int) -> some View {
        ActivityCard(spacing: 8, identifier: "max-card-\(n)") {
            CardTitle(name: c.member.name, types: c.member.types) { TierChip(tier: c.tier, type: .max) }
            FlowLayout(spacing: 6) {
                Text(c.roleText.uppercased()).font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.5).foregroundStyle(ContentType.max.ink(accent))
                    .padding(.horizontal, 8).padding(.vertical, 3).background(ContentType.max.tint(accent), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                if c.needsDynamax {
                    Text("NEEDS DYNAMAX").font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.5).foregroundStyle(Theme.orangeInk)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(Theme.orangeTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            if let plan = c.plan { planBlock(plan, title: PokemonPage.planTitle(plan)) }
            else { mutedLine("No Max build is planned for this copy.") }
        }
    }

    private var battleList: some View {
        let rows = battles.map(\.row.entry.row)
        return VStack(alignment: .leading, spacing: 0) {
            CapsCaption("MAX BATTLES ON NOW AND COMING THAT THE FAMILY HITS").padding(.bottom, 6)
            ForEach(Array(battles.enumerated()), id: \.offset) { _, b in
                let name = PokemonActivities.shortName(b.row.entry.row, among: rows), dates = HubRaidsModel.dateColumn(b.row.entry).dates
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(name).font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                    if b.row.isNow {
                        Text("NOW").font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.4).foregroundStyle(accent.ink)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(accent.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    Spacer(minLength: 8)
                    Text("\(b.by.joined(separator: ", ")) · \(dates)").font(.figtree(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.muted).multilineTextAlignment(.trailing)
                }
                .frame(minHeight: 36)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(name), \(b.row.isNow ? "now" : b.row.when), hit by \(b.by.joined(separator: ", "))")
                .accessibilityIdentifier("max-battle")
            }
        }
    }
}
