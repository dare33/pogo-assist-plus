import Foundation

/// What the Pokémon page's Leagues panel says, worked out from a `BoxAdvice.LeagueRating`, kept out of the view so `swift test` can pin it.
/// Nothing here is rated again: every figure is one the engine already gave (design handoff of 22 Oct 2026, section 3).
public enum LeaguePanel {
    public static let keys = ["gl", "ul", "ml"]
    public static func name(_ key: String) -> String { ["gl": "Great League", "ul": "Ultra League", "ml": "Master League"][key] ?? key }
    public static func shortName(_ key: String) -> String { ["gl": "Great", "ul": "Ultra", "ml": "Master"][key] ?? key }
    /// The CP limit of a league; Master League has none.
    public static func cap(_ key: String) -> Int? { ["gl": 1500, "ul": 2500][key] }
    /// "Under 1,500 CP" / "No CP cap".
    public static func capText(_ key: String) -> String { cap(key).map { "Under \(grouped($0)) CP" } ?? "No CP cap" }

    /// Thousands grouping that does not depend on the phone's region ("1,152").
    public static func grouped(_ n: Int) -> String {
        let f = NumberFormatter(); f.locale = Locale(identifier: "en_US"); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }
    public static func oneDecimal(_ d: Double) -> String { String(format: "%.1f", d) }
    /// "18.5", "32": a whole level has no decimal.
    public static func level(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }
    public static func percent(_ d: Double) -> String { oneDecimal(d) + "%" }

    /// Dust for the option list: 100,000 and over as whole thousands ("489k"), 10,000 and over with one decimal ("56.8k", "14k"), else grouped.
    public static func dustShort(_ d: Int) -> String {
        if d >= 100_000 { return "\(Int((Double(d) / 1000).rounded()))k" }
        if d >= 10_000 {
            let s = String(format: "%.1f", Double(d) / 1000)
            return (s.hasSuffix(".0") ? String(s.dropLast(2)) : s) + "k"
        }
        return grouped(d)
    }

    /// The option the page shows: the experimental member under the Pogo Assist ranking, the Poke Genie-compatible pick otherwise.
    public static func shownIndex(_ r: BoxAdvice.LeagueRating, pogoAssist: Bool) -> Int { pogoAssist ? r.experimentalIndex : r.pickIndex }
    public static func chipText(pogoAssist: Bool) -> String { pogoAssist ? "Pogo Assist pick" : "Pick" }

    // MARK: the pick card

    public struct CostItem: Equatable { public var label: String; public var value: String }
    public struct MoveChip: Equatable { public var text: String; public var missing: Bool }

    public enum Status: Equatable {
        /// The headline member fits under the cap and its IVs are read.
        case fits
        /// Every member of the family is already over the cap.
        case noViable
        /// The headline member fits, but this copy's IVs are not read (or give no rank).
        case ivsNotRead
    }

    public struct Card: Equatable {
        public var status: Status
        public var option: BoxAdvice.LeagueRating.Option
        /// "Gallade, if it is male" for a gender-locked member.
        public var title: String
        /// The stronger species this copy is already over the cap as, when the card headlines a weaker one that fits.
        public var strongerOverCap: BoxAdvice.LeagueRating.Option?
        public var overCapCount: Int
        public var bestAvailableNote: String?
        /// "No viable option" explained.
        public var blockedText: String?
        public var scoreText: String
        public var rankText: String
        public var scoreStrong: Bool
        public var ivText: String
        public var ivRankText: String
        public var ivStrong: Bool
        public var costItems: [CostItem]
        /// A sentence in place of the cost list: not known, at or past its level.
        public var costNote: String?
        public var moves: [MoveChip]
        /// This copy's IV % as the headline member; nil when nothing fits or the IVs are not read (the IVs panel shows "—").
        public var ivPct: Double?
        /// The tag on the card: nil on a "No viable option" card.
        public var worth: Worth? = nil
        /// For a Strong tag whose build is for another member than the one shown (the Wartortle card, the Blastoise build): that build's target.
        public var worthTarget: String? = nil
    }

    // MARK: the worth tag

    /// How worth building the shown member is for this copy in a league: Strong when one of the copy's OWN Advice builds covers the league (the same
    /// source as the Advice panel, so they never disagree; a build another copy carries does not count), else OK from `okScore`, else Weak.
    public enum Worth: Equatable {
        case strong, ok, weak
        public var label: String { self == .strong ? "Strong" : self == .ok ? "OK" : "Weak" }
    }

    /// The PvPoke score from which a member that no build covers still reads OK. A display threshold of this screen, not the advisor's bar.
    public static let okScore = 80.0

    /// The target of the covering build when none of the covering builds is for the shown member (names compared without a "(Shadow)" suffix).
    public static func worthTarget(_ o: BoxAdvice.LeagueRating.Option, key: String, builds: [BoxAdvice.Build]) -> String? {
        let label = BoxAdvice.areaLabel[key] ?? key
        func plain(_ s: String) -> String { s.replacingOccurrences(of: " (Shadow)", with: "") }
        let covering = builds.filter { $0.areas.contains(label) }
        guard let first = covering.first, !covering.contains(where: { plain($0.targetName) == plain(o.name) }) else { return nil }
        return first.targetName
    }

    public static func worth(_ o: BoxAdvice.LeagueRating.Option, key: String, builds: [BoxAdvice.Build]) -> Worth {
        let label = BoxAdvice.areaLabel[key] ?? key
        if builds.contains(where: { $0.areas.contains(label) }) { return .strong }
        return (o.strength?.score ?? -1) >= okScore ? .ok : .weak
    }

    /// The line a tap on the tag opens.
    /// "Better kept for trading or transferring" is only said when the Advice panel says the same: the copy has no build and hygiene would transfer it
    /// (`transfers`); a Weak tag under other advice says only that it is not a strong pick.
    public static func worthSentence(_ w: Worth, key: String, transfers: Bool = false, target: String? = nil) -> String {
        switch w {
        case .strong: return target.map { "Worth building for \(name(key)) as \($0)." } ?? "Worth building for \(name(key))."
        case .ok: return "A solid choice for \(name(key)), though stronger options exist."
        case .weak: return transfers ? "Better kept for trading or transferring than for \(name(key))." : "Not a strong pick for \(name(key))."
        }
    }

    /// "Gallade, if it is male".
    public static func title(_ o: BoxAdvice.LeagueRating.Option) -> String { o.genderLocked.map { "\(o.name), if it is \($0)" } ?? o.name }

    /// The member the card headlines: the shown one when this copy fits it, else the best-ranked member that does fit; nil when none does.
    public static func headlineIndex(_ r: BoxAdvice.LeagueRating, shown: Int) -> Int? {
        if r.options.indices.contains(shown), !r.options[shown].overCap { return shown }
        return r.options.firstIndex { !$0.overCap }
    }

    /// "Past its best Ultra League level; 100 candy", "Already at level 51; 100 candy", "Level not known, so no cost", or nil when the cost list stands.
    public static func costNote(_ o: BoxAdvice.LeagueRating.Option, key: String, level now: Double?) -> String? {
        guard let c = o.cost else { return now == nil && !o.overCap ? "Level not known, so no cost" : nil }
        let candy = c.evolveCandy > 0 ? "; \(grouped(c.evolveCandy)) candy" : ""
        if let now, c.toLevel < now { return "Past its best \(name(key)) level" + candy }
        if c.dust == 0 && c.candy == 0 && c.xl == 0 { return "Already at level \(level(c.toLevel))" + candy }
        return nil
    }

    public static func costItems(_ o: BoxAdvice.LeagueRating.Option) -> [CostItem] {
        guard let c = o.cost else { return [] }
        var items = [CostItem(label: "Target level: ", value: level(c.toLevel))]
        if let iv = o.iv { items.append(CostItem(label: "Target CP: ", value: grouped(iv.cp))) }
        items.append(CostItem(label: "", value: "\(grouped(c.dust)) dust"))
        items.append(CostItem(label: "", value: "\(grouped(c.candy + c.evolveCandy)) candy" + (c.xl > 0 ? ", \(grouped(c.xl)) XL" : "")))
        return items
    }

    public static func moveChips(_ o: BoxAdvice.LeagueRating.Option) -> [MoveChip] {
        guard let m = o.moves else { return [] }
        let needs = o.isSelf ? (o.needs ?? []) : []
        return ([m.fast] + m.charged).map { MoveChip(text: needs.contains($0) ? "Needs \($0)" : $0, missing: needs.contains($0)) }
    }

    /// The member to name in the best-available note: the card's member is not the strongest and a stronger one is already over the cap.
    /// The highest-scored ranked member over the cap that outscores the card's member; failing that, when the card's member is unranked (the
    /// engine's "fallback": nothing it may show is ranked), the deepest unranked member over the cap that is listed before it, which is the
    /// final evolution (options list unranked members later evolution first), e.g. Rookidee shows Corvisquire while Corviknight is over the cap.
    public static func strongerOverCap(_ r: BoxAdvice.LeagueRating, than o: BoxAdvice.LeagueRating.Option) -> BoxAdvice.LeagueRating.Option? {
        if let ranked = r.options.first(where: { $0.overCap && ($0.strength?.score ?? -1) > (o.strength?.score ?? -1) && $0.speciesId != o.speciesId && $0.strength != nil }) { return ranked }
        guard o.strength == nil, let at = r.options.firstIndex(where: { $0.speciesId == o.speciesId }) else { return nil }
        return r.options[..<at].first { $0.overCap && $0.strength == nil }
    }

    /// Everything one pick card shows. `level` is the Pokémon's own level (nil when not known).
    /// `builds` are the copy's own Advice builds, which decide the Strong tag.
    public static func card(_ r: BoxAdvice.LeagueRating, shown: Int, key: String, level now: Double?, builds: [BoxAdvice.Build] = []) -> Card {
        let shownOption = r.options[min(max(shown, 0), r.options.count - 1)]
        let overCount = r.options.filter(\.overCap).count
        guard let at = headlineIndex(r, shown: shown) else {
            let cap = cap(key).map(grouped) ?? ""
            return Card(status: .noViable, option: shownOption, title: title(shownOption), strongerOverCap: nil, overCapCount: overCount, bestAvailableNote: nil,
                        blockedText: "This copy is already above \(cap) CP as " + (r.options.count > 1 ? "every member of the family." : "\(shownOption.name)."),
                        scoreText: "—", rankText: "", scoreStrong: false, ivText: "—", ivRankText: "", ivStrong: false,
                        costItems: [], costNote: nil, moves: moveChips(shownOption), ivPct: nil)
        }
        let o = r.options[at]
        let stronger = strongerOverCap(r, than: o)
        // A member only one sex can become is named with its condition: "Gallade (if it is male)".
        let note = stronger.map { s -> String in
            let named = s.genderLocked.map { "\(s.name) (if it is \($0))" } ?? s.name
            return "\(named) is the stronger species, but this copy is already over \(cap(key).map(grouped) ?? "") CP as \(s.name)."
        }
        let read = o.iv != nil
        return Card(status: read ? .fits : .ivsNotRead, option: o, title: title(o), strongerOverCap: stronger, overCapCount: overCount, bestAvailableNote: note, blockedText: nil,
                    scoreText: o.strength.map { oneDecimal($0.score) } ?? "—",
                    rankText: o.strength.map { "#\(grouped($0.rank)) of \(grouped($0.of))" } ?? "",
                    scoreStrong: (o.strength?.score ?? 0) >= 80,
                    ivText: o.iv.map { percent($0.pct) } ?? "—", ivRankText: o.iv.map { "IV #\(grouped($0.rank))" } ?? "not read",
                    ivStrong: (o.iv?.rank ?? Int.max) <= 500,
                    costItems: read && costNote(o, key: key, level: now) == nil ? costItems(o) : [],
                    costNote: read ? costNote(o, key: key, level: now) : (now == nil ? costNote(o, key: key, level: now) : nil),
                    moves: moveChips(o), ivPct: o.iv?.pct, worth: worth(o, key: key, builds: builds), worthTarget: worthTarget(o, key: key, builds: builds))
    }

    /// The spoken summary of a pick card, as one element.
    public static func spoken(_ c: Card, key: String, chip: String) -> String {
        var parts = ["\(name(key)), \(capText(key).lowercasedFirst)", "\(chip): \(c.title)"]
        if let w = c.worth { parts.append("\(w.label) for \(name(key))") }
        if c.overCapCount > 0 { parts.append("\(c.overCapCount) over cap") }
        if let n = c.bestAvailableNote { parts.append(n) }
        if c.status == .noViable {
            parts.append("No viable option")
            if let b = c.blockedText { parts.append(b) }
        } else {
            parts.append(c.scoreText == "—" ? "Species not ranked" : "Species \(c.scoreText), rank \(c.rankText.replacingOccurrences(of: "#", with: ""))")
            if let iv = c.option.iv, c.status != .ivsNotRead { parts.append("This copy \(oneDecimal(iv.pct)) percent, IV rank \(grouped(iv.rank))") } else { parts.append("This copy not read") }
            if let n = c.costNote { parts.append(n) } else if !c.costItems.isEmpty { parts.append(c.costItems.enumerated().map { n, item in
                let text = (item.label + item.value).replacingOccurrences(of: ": ", with: " ")
                return n == 0 ? text : text.lowercasedFirst
            }.joined(separator: ", ")) }
        }
        if !c.moves.isEmpty { parts.append("Moves " + c.moves.map(\.text).joined(separator: ", ")) }
        return parts.joined(separator: ". ") + "."
    }

    // MARK: the option list

    /// One row of the option list: the figures under the column header SPECIES, THIS COPY, DUST.
    public struct Row: Equatable {
        public var option: BoxAdvice.LeagueRating.Option
        public var sub: String
        /// Over the cap: the figures are replaced by this sentence ("Over 1,500 CP as Corviknight").
        public var blockedText: String?
        public var score: String, rank: String, scoreStrong: Bool
        public var ivPct: String, ivRank: String, ivStrong: Bool
        public var dust: String, candy: String
        /// Dust is shown muted when XL candy is needed.
        public var dustMuted: Bool
        /// The three sentences of the expanded row.
        public var detailLevel: String
        public var detailCost: String?
        public var detailMoves: String?
    }

    public static func row(_ o: BoxAdvice.LeagueRating.Option, key: String, level now: Double?) -> Row {
        let sub = o.isSelf ? "itself, no evolving" : o.genderLocked.map { "if it is \($0)" }
            ?? (o.iv != nil && !o.overCap ? "L\(level(o.iv!.level)) · CP \(grouped(o.iv!.cp))" : (o.overCap ? "too high already" : ""))
        let dust: String, candy: String
        if let c = o.cost {
            if c.dust != 0 || c.candy != 0 || c.xl != 0 {
                dust = dustShort(c.dust)
                candy = c.xl > 0 ? "\(grouped(c.xl)) XL" : (c.candy + c.evolveCandy > 0 ? "\(grouped(c.candy + c.evolveCandy)) candy" : "no candy")
            } else { dust = "0"; candy = c.evolveCandy > 0 ? "\(grouped(c.evolveCandy)) candy" : "at its level" }
        } else { dust = "—"; candy = now == nil ? "level not known" : "no cost" }
        let detailLevel = o.iv.map { "Best level \(level($0.level))\(cap(key) == nil ? "" : " under the cap"), CP \(grouped($0.cp)). IVs rank #\(grouped($0.rank)) of 4,096, \(String(format: "%.2f", $0.pct))% of best." }
            ?? (o.overCap ? "Already above the cap as \(o.name)." : "IVs not read, so no rank.")
        return Row(option: o, sub: sub,
                   blockedText: o.overCap ? cap(key).map { "Over \(grouped($0)) CP as \(o.name)" } : nil,
                   score: o.strength.map { oneDecimal($0.score) } ?? "—", rank: o.strength.map { "#\(grouped($0.rank))" } ?? "", scoreStrong: (o.strength?.score ?? 0) >= 80,
                   ivPct: o.iv.map { percent($0.pct) } ?? "—", ivRank: o.iv.map { "IV #\(grouped($0.rank))" } ?? "not read", ivStrong: (o.iv?.rank ?? Int.max) <= 500,
                   dust: dust, candy: candy, dustMuted: (o.cost?.xl ?? 0) > 0,
                   detailLevel: detailLevel, detailCost: costSentence(o, key: key, level: now), detailMoves: movesSentence(o))
    }

    /// "To level 26.5: 56,800 dust, 75 candy, 8 XL · CP 1,481", or the note that stands in for it; nil when there is nothing to say.
    public static func costSentence(_ o: BoxAdvice.LeagueRating.Option, key: String, level now: Double?) -> String? {
        guard let c = o.cost else { return now == nil ? "Level not known, so no cost" : (o.overCap ? nil : "No cost") }
        if let n = costNote(o, key: key, level: now) { return n }
        var s = "To level \(level(c.toLevel)): \(grouped(c.dust)) dust"
        if c.candy + c.evolveCandy > 0 { s += ", \(grouped(c.candy + c.evolveCandy)) candy" }
        if c.xl > 0 { s += ", \(grouped(c.xl)) XL" }
        if let iv = o.iv { s += " · CP \(grouped(iv.cp))" }
        return s
    }

    /// "Moves: Ember, Overheat, Flamethrower"; with what the copy lacks ("Needs Overheat") when it is the Pokémon itself. nil for an unranked member.
    public static func movesSentence(_ o: BoxAdvice.LeagueRating.Option) -> String? {
        guard let m = o.moves else { return nil }
        var s = "Moves: " + ([m.fast] + m.charged).joined(separator: ", ")
        if o.isSelf, let n = o.needs, !n.isEmpty { s += ". Needs " + n.joined(separator: ", ") }
        return s
    }

    /// The other members, in the engine's order (the headline member is the card).
    public static func listed(_ r: BoxAdvice.LeagueRating, headline: Int?) -> [BoxAdvice.LeagueRating.Option] {
        r.options.enumerated().filter { $0.offset != headline }.map(\.element)
    }

    /// The spoken summary of an option row.
    public static func spoken(_ row: Row) -> String {
        var parts = [row.option.name]
        if !row.sub.isEmpty { parts.append(row.sub) }
        if let b = row.blockedText { parts.append(b) }
        else {
            parts.append(row.score == "—" ? "Species not ranked" : "Species \(row.score), rank \(row.rank.dropFirst())")
            parts.append(row.ivPct == "—" ? "This copy not read" : "This copy \(row.ivPct.dropLast()) percent, \(row.ivRank)")
            parts.append("Dust \(row.dust), \(row.candy)")
        }
        return parts.joined(separator: ". ")
    }

    // MARK: the IVs panel

    /// The three figures at the IVs panel's trailing edge: this copy's IV % as the shown member, per league; nil is "—".
    public static func ivFigures(_ ratings: [String: BoxAdvice.LeagueRating], pogoAssist: Bool, level now: Double?) -> [(key: String, pct: Double?)] {
        keys.map { key in
            guard let r = ratings[key] else { return (key, nil) }
            return (key, card(r, shown: shownIndex(r, pogoAssist: pogoAssist), key: key, level: now).ivPct)
        }
    }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
