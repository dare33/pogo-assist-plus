import Foundation

/// What the Pokémon page says and does that is not a layout choice (design pass 3, `CONCEPTS.md` rules 8, 16 and 17): the edit each mark and chip makes, the
/// moves a copy shows (stored, else the defaults), the sentences on the activity cards and the one-line notes. Pure functions over the model and the rules
/// in `PokemonActivities` and `AdvancedDetails`, so `swift test` pins them and the app only lays them out.
public enum PokemonPage {
    // MARK: marks (rule 8) and the flag chips

    /// The state a copy carries that the player sets by hand: the flag chips of the advanced details, and Gigantamax beside them while the Dynamax mark is on.
    public enum Flag: String, CaseIterable {
        case lucky = "Lucky", purified = "Purified", bestBuddy = "Best Buddy", weatherBoosted = "Weather-boosted", gigantamax = "Gigantamax"
    }

    /// The chips the MORE section shows: the four of rule 17, and Gigantamax only while the Dynamax mark is on (Gigantamax implies Dynamax, so with the
    /// mark off there is nothing to choose).
    public static func flags(for row: ScanRow) -> [Flag] {
        [.lucky, .purified, .bestBuddy, .weatherBoosted] + (row.dynamax == true ? [.gigantamax] : [])
    }

    public static func isOn(_ flag: Flag, _ row: ScanRow) -> Bool {
        switch flag {
        case .lucky: return row.lucky == true
        case .purified: return row.shadow == 2
        case .bestBuddy: return row.details?.bestBuddy == true
        case .weatherBoosted: return row.details?.weatherBoosted == true
        case .gigantamax: return row.gigantamax == true
        }
    }

    /// The edit that flips a chip. Purified and Shadow clear each other in the model (one field), Gigantamax on marks Dynamax too, and Best Buddy and
    /// Weather-boosted are stored in the details (a cleared one leaves the field absent, so empty details are not stored).
    public static func toggle(_ flag: Flag, _ row: ScanRow) -> BoxMerge.Edit {
        let on = !isOn(flag, row)
        switch flag {
        case .lucky: return BoxMerge.Edit(lucky: on)
        case .purified: return BoxMerge.Edit(shadow: on ? .purified : .neither)
        case .gigantamax: return BoxMerge.Edit(gigantamax: on)
        case .bestBuddy:
            var d = row.details ?? CopyDetails(); d.bestBuddy = on ? true : nil
            return BoxMerge.Edit(details: d)
        case .weatherBoosted:
            var d = row.details ?? CopyDetails(); d.weatherBoosted = on ? true : nil
            return BoxMerge.Edit(details: d)
        }
    }

    /// The Dynamax mark: on or off (off is "not marked"; the model clears Gigantamax with it).
    public static func toggleDynamax(_ row: ScanRow) -> BoxMerge.Edit { BoxMerge.Edit(dynamax: row.dynamax == true ? .off : .on) }

    /// The Shadow mark: on or off; on clears Purified in the model. Off stores "marked neither by hand" (0).
    public static func toggleShadow(_ row: ScanRow) -> BoxMerge.Edit { BoxMerge.Edit(shadow: row.shadow == 1 ? .neither : .shadow) }

    /// Whether an edit would leave the row as it is: a mark already in that state, the chip already stored, "Not unlocked" or a level "–" with nothing stored. Such
    /// an edit saves no box version and re-runs no advice. A default that is shown but not stored is not stored, so tapping it is a change (it saves).
    public static func isNoOp(_ edit: BoxMerge.Edit, _ row: ScanRow) -> Bool {
        if let d = edit.dynamax, d.value != row.dynamax { return false }
        if let g = edit.gigantamax, (g ? true : nil) != row.gigantamax { return false }
        if let l = edit.lucky, (l ? true : nil) != row.lucky { return false }
        if let sh = edit.shadow, sh.value != row.shadow { return false }
        if let d = edit.details {
            let n = d.normalised
            if (n.isEmpty ? nil : n) != row.details { return false }
        }
        return edit.marksOnly
    }

    /// The types of a species; the fallback species' when the game master does not know it (the Mega form the page shows has its own types).
    public static func types(of speciesId: String, fallback: String, gm: GameMaster?) -> [String] {
        gm?.byId[speciesId]?.types ?? gm?.byId[fallback]?.types ?? []
    }

    /// The grades of a family-list row's two figures, by the tiles' bands (rule 9: top 92+ or IV rank 1 to 100, good 90+ or 101 to 500), not the cards' older
    /// 88 and 80th-percentile cut-offs.
    public static func grades(_ row: LeaguePanel.Row) -> (score: MyPokemon.Grade, iv: MyPokemon.Grade) {
        (MyPokemon.scoreGrade(row.option.strength?.score), MyPokemon.rankGrade(row.option.iv?.rank))
    }

    // MARK: moves (rules 17 and 18)

    public enum MoveSlot { case fast, charged, charged2 }

    /// The moves a copy shows: the stored choice where the species can learn it, else the default (rule 18); the second charged move is "Not unlocked"
    /// (nil) unless stored, and never equals the first. A default is shown, not saved, until the player taps.
    public static func moves(_ details: CopyDetails?, speciesId: String, gm: GameMaster) -> AdvancedDetails.Defaults {
        AdvancedDetails.normalised(.init(fast: details?.fastMove, charged1: details?.chargedMove, charged2: details?.chargedMove2), speciesId: speciesId, gm: gm)
    }

    /// The details after the player picks a move. A move the species cannot learn changes nothing; picking the second charged move equal to the first
    /// changes nothing; picking a first charged move equal to the second clears the second back to "Not unlocked". `id` nil on the second slot is
    /// "Not unlocked".
    public static func choosing(_ id: String?, for slot: MoveSlot, details: CopyDetails?, speciesId: String, gm: GameMaster) -> CopyDetails {
        var d = details ?? CopyDetails()
        let now = moves(details, speciesId: speciesId, gm: gm)
        switch slot {
        case .fast:
            guard let id, AdvancedDetails.fastMoves(of: speciesId, gm: gm).contains(where: { $0.id == id }) else { return d }
            d.fastMove = id
        case .charged:
            guard let id, AdvancedDetails.chargedMoves(of: speciesId, gm: gm).contains(where: { $0.id == id }) else { return d }
            d.chargedMove = id
            if now.charged2 == id { d.chargedMove2 = nil }
        case .charged2:
            guard let id else { d.chargedMove2 = nil; return d }
            guard id != now.charged1, AdvancedDetails.chargedMoves(of: speciesId, gm: gm).contains(where: { $0.id == id }) else { return d }
            d.chargedMove2 = id
        }
        return d
    }

    // MARK: Max moves and the Mega level (rule 17)

    public enum MaxMove { case attack, guardMove, spirit }

    /// The level a Max move shows: Max Attack starts at 1 (the game's lowest), Max Guard and Max Spirit at 0, which reads "–" (not unlocked).
    public static func level(of move: MaxMove, _ details: CopyDetails?) -> Int {
        switch move {
        case .attack: return details?.maxAttack ?? AdvancedDetails.maxAttackLevels[0]
        case .guardMove: return details?.maxGuard ?? 0
        case .spirit: return details?.maxSpirit ?? 0
        }
    }

    public static func levels(of move: MaxMove) -> [Int] {
        switch move {
        case .attack: return AdvancedDetails.maxAttackLevels
        case .guardMove: return AdvancedDetails.maxGuardLevels
        case .spirit: return AdvancedDetails.maxSpiritLevels
        }
    }

    /// The details after a Max move level is picked; a level the move does not have changes nothing, "–" (0) stores nothing.
    public static func setting(_ level: Int, of move: MaxMove, _ details: CopyDetails?) -> CopyDetails {
        var d = details ?? CopyDetails()
        guard levels(of: move).contains(level) else { return d }
        switch move {
        case .attack: d.maxAttack = level
        case .guardMove: d.maxGuard = level == 0 ? nil : level
        case .spirit: d.maxSpirit = level == 0 ? nil : level
        }
        return d
    }

    /// The Mega level a copy shows: "Not yet" until one is chosen.
    public static func megaLevel(_ details: CopyDetails?) -> CopyDetails.MegaLevel { details?.megaLevel ?? .notYet }

    /// The details after a Mega level is picked ("Not yet" stores nothing).
    public static func setting(megaLevel level: CopyDetails.MegaLevel, _ details: CopyDetails?) -> CopyDetails {
        var d = details ?? CopyDetails()
        d.megaLevel = level == .notYet ? nil : level
        return d
    }

    // MARK: costs and plans (the cost slot of a row or a card)

    /// A Summary row's mark as the app's shared build mark.
    public static func buildMark(_ mark: PokemonActivities.Mark) -> MyPokemon.BuildMark {
        switch mark {
        case .none: return .none
        case .fullStrength: return .fullStrength
        case .upgrade(_, let cost, _): return .upgrade(cost: myCost(cost), builds: 1)
        }
    }

    /// What VoiceOver reads for an upgrade mark ("Upgrade available: power up to level 30"); nil for the other marks.
    public static func upgradeLabel(_ mark: PokemonActivities.Mark) -> String? {
        if case .upgrade(_, _, let label) = mark { return label }
        return nil
    }

    private static func myCost(_ c: HubSquads.Cost) -> MyPokemon.Cost? {
        guard let v = c.value, c.currency != .free else { return nil }
        return MyPokemon.Cost(value: v, currency: c.currency == .candy ? .candy : .dust)
    }

    /// The mark of a plan on a card or of one Advice build: Full strength when built, the upgrade arrow with its cost when work is left, nothing when the only
    /// thing left is the Dynamax mark.
    public static func planMark(_ build: BoxAdvice.Build, built: Bool) -> (mark: MyPokemon.BuildMark, label: String?) {
        if built { return (.fullStrength, nil) }
        guard let label = HubSquads.upgradeLabel(build) else { return (.none, nil) }
        return (.upgrade(cost: myCost(HubSquads.cost(of: build)), builds: 1), label)
    }

    /// The work a build still has, in one line: "Evolve, power up to level 35". The Dynamax requirement reads "needs a Dynamax copy". Nothing left reads
    /// "Already built".
    public static func workLine(_ b: BoxAdvice.Build) -> String {
        guard let steps = b.steps else { return b.action }
        func level(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }
        let parts: [String] = steps.map { s in
            switch s.kind {
            case "evolve": return "Evolve"
            case "formChange": return "Form change"
            case "megaEvolve": return "Mega evolve"
            case "powerUp": return s.toLevel.map { "Power up to level \(level($0))" } ?? "Power up"
            case "secondMove": return "Second move"
            case "eliteTM": return (s.count ?? 1) == 1 ? "1 Elite TM" : "\(s.count ?? 1) Elite TMs"
            case "cdMove": return "Community Day move"
            case "needsDynamaxCopy": return "Needs a Dynamax copy"
            default: return "More to do"
            }
        }
        guard !parts.isEmpty else { return "Already built" }
        return parts.enumerated().map { $0.offset == 0 ? $0.element : $0.element.prefix(1).lowercased() + $0.element.dropFirst() }.joined(separator: ", ")
    }

    /// The heading of a plan block: "Planned for this copy" or "This copy, full strength".
    public static func planTitle(_ plan: PokemonActivities.Plan) -> String { plan.built ? "This copy, full strength" : "Planned for this copy" }

    /// The Gym tab's plan block: "Planned as a defender" or "Defender, full strength".
    public static func gymPlanTitle(_ plan: PokemonActivities.Plan) -> String { plan.built ? "Defender, full strength" : "Planned as a defender" }

    // MARK: the Raids card's one muted line

    /// What a Raids card says when this copy has no plan for the member: another copy is planned as it, or the box's best attacker of the type, or nothing.
    /// "Another copy (CP 782) is planned as your Glaceon.", "Your best Ice attacker is Mamoswine (S), still to build.".
    public static func raidsOtherLine(_ card: PokemonActivities.RaidCard) -> String {
        let type = card.type.prefix(1).uppercased() + card.type.dropFirst()
        switch card.plan {
        case .mine: return ""
        case .none:
            let article = "AEIOU".contains(type.first ?? "X") ? "an" : "a"
            return "Nothing in your box is planned as \(article) \(type) attacker yet."
        case .best(let plan, let tier):
            let b = plan.build
            let end = plan.built ? ", at full strength." : ", still to build."
            if b.targetId == card.member.id { return "Another copy (CP \(b.cp)) is planned as your \(card.member.name)" + (plan.built ? ", at full strength." : ".") }
            return "Your best \(type) attacker is \(b.targetName) (\(tier))" + end
        }
    }

    // MARK: the Rocket card

    /// "Giovanni slot 2, 3 · Sierra slot 2": the leader slots a member beats, one leader after another.
    public static func leaderSlotsText(_ slots: [PokemonActivities.LeaderSlotBeat]) -> String {
        var order = [String](), by = [String: [Int]]()
        for s in slots { if by[s.leader] == nil { order.append(s.leader) }; by[s.leader, default: []].append(s.slot) }
        return order.map { "\($0) slot\(by[$0]!.count > 1 ? "s" : "") " + by[$0]!.map(String.init).joined(separator: ", ") }.joined(separator: " · ")
    }

    // MARK: the Max tab

    /// "Marked as Dynamax." or "Dynamax: not marked."
    public static func dynamaxLine(_ row: ScanRow) -> String { row.dynamax == true ? "Marked as Dynamax." : "Dynamax: not marked." }

    /// What follows the Dynamax state on the Max tab: the rule, and, while the mark is off, where to set it.
    public static func dynamaxNote(_ row: ScanRow) -> String {
        row.dynamax == true ? "Only a copy caught as Dynamax can join Max battles."
            : "Only a copy caught as Dynamax can join Max battles; mark it with the Dynamax icon at the top once you have checked in the game."
    }

    // MARK: the PvP tab

    /// The row under the tiles that opens the family and details: "Great League family and details (8 more)". `more` is the other family members the
    /// league lists.
    public static func familyLabel(key: String, more: Int) -> String {
        "\(LeaguePanel.name(key)) family and details" + (more > 0 ? " (\(more) more)" : "")
    }

    /// The one muted line under the tiles for the chosen league: the sentence behind its worth tag, or why nothing fits.
    public static func worthLine(_ card: LeaguePanel.Card, key: String, transfers: Bool) -> String {
        if let b = card.blockedText { return b }
        return LeaguePanel.worthSentence(card, key: key, transfers: transfers) ?? ""
    }

    // MARK: the Advice on the Summary tab

    /// The spare and keep or transfer notes as one line: "Spare: Umbreon, Vaporeon, Glaceon planned · Keep · best IVs of 65". nil when there is neither.
    public static func shortNotes(_ a: BoxAdvice.ForEntry, name: String) -> String? {
        var parts = [String]()
        if !a.spareFor.isEmpty {
            var targets = [String]()
            for b in a.spareFor where b.targetName != name && !targets.contains(b.targetName) { targets.append(b.targetName) }
            parts.append(targets.isEmpty ? "Spare: another \(name) planned" : "Spare: " + targets.joined(separator: ", ") + " planned")
        }
        if let k = MyPokemon.keepTag(a) { parts.append(k.text) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The full sentences behind the "i" beside ADVICE: each build's action and cost, then the spare and keep or transfer sentences (plain text).
    public struct AdviceSentences: Equatable {
        public var builds: [String]
        public var spare: String?
        public var verdict: String?
        public var isEmpty: Bool { builds.isEmpty && spare == nil && verdict == nil }
    }

    public static func adviceSentences(_ a: BoxAdvice.ForEntry, name: String, costLine: (BoxAdvice.Build) -> String) -> AdviceSentences {
        let notes = BoxAdvice.adviceNotes(a, name: a.duplicateOf?.name ?? name)
        let builds = a.builds.map { b -> String in
            let head = b.action + (b.pvp.map { " (\($0))" } ?? "")
            let cost = costLine(b)
            return cost.isEmpty ? head + "." : "\(head): \(cost)."
        }
        return AdviceSentences(builds: builds, spare: notes.spare, verdict: notes.verdict.map { $0.replacingOccurrences(of: "**", with: "") })
    }

    /// The name of an activity on the Summary tab (D13): the Hub's own words.
    public static func name(_ a: PokemonActivities.Activity) -> String {
        switch a {
        case .pvp: return "PvP leagues"
        case .raids: return "Raids"
        case .gym: return "Gym battles"
        case .rocket: return "Team GO Rocket"
        case .max: return "Max battles"
        }
    }

    /// The tab a Summary row opens.
    public static func tab(_ a: PokemonActivities.Activity) -> PokemonActivities.Tab {
        switch a {
        case .pvp: return .pvp
        case .raids: return .raids
        case .gym: return .gym
        case .rocket: return .rocket
        case .max: return .max
        }
    }

    // MARK: the empty states (one muted line each)

    public static func emptyLine(_ tab: PokemonActivities.Tab) -> String {
        switch tab {
        case .raids: return "Nothing this copy can become is in our raid tables."
        case .gym: return "Nothing this copy can become is in our gym table."
        case .rocket: return "Nothing this copy can become has a type advantage on a grunt or a leader."
        case .max: return "Nothing this copy can become is in our Max table."
        case .pvp, .summary: return ""
        }
    }
}

extension CopyDetails.MegaLevel {
    /// "Not yet", "Base", "High", "Max": the design's words (CONCEPTS word check 9 asks to check them against the game's own).
    public var title: String { ["notYet": "Not yet", "base": "Base", "high": "High", "max": "Max"][rawValue] ?? rawValue }
}
