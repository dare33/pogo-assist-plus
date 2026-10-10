import Foundation

/// The sentences of the Pokémon page's Leagues section, kept out of the view so `swift test` can pin them.
public enum LeagueText {
    public static let keys = ["gl", "ul", "ml"]
    public static func name(_ key: String) -> String { ["gl": "Great League", "ul": "Ultra League", "ml": "Master League"][key] ?? key }
    /// The CP limit of a league; Master League has none.
    public static func cap(_ key: String) -> Int? { ["gl": 1500, "ul": 2500][key] }

    /// Thousands grouping that does not depend on the phone's region ("1,152").
    public static func grouped(_ n: Int) -> String {
        let f = NumberFormatter(); f.locale = Locale(identifier: "en_US"); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }
    public static func ordinal(_ n: Int) -> String {
        let tens = n % 100, suffix = (11...13).contains(tens) ? "th" : ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
        return grouped(n) + suffix
    }
    private static func oneDecimal(_ d: Double) -> String { String(format: "%.1f", d) }
    private static func level(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }

    /// "As Toxapex": only when the best pick is not the Pokémon itself.
    public static func pick(_ r: BoxAdvice.LeagueRating) -> String? { r.pick.isSelf ? nil : "As \(r.pick.name)" }

    public static func strength(_ r: BoxAdvice.LeagueRating, key: String) -> String {
        guard let s = r.strength else { return "Not ranked in \(name(key)) by PvPoke" }
        return "PvPoke ranks \(r.pick.name) \(ordinal(s.rank)) of \(grouped(s.of)) in \(name(key)), score \(oneDecimal(s.score))"
    }

    public static func ivs(_ r: BoxAdvice.LeagueRating, key: String) -> String {
        guard let iv = r.iv else { return "IVs not read, so no rank" }
        if r.overCap, let cap = cap(key) { return "Already above \(grouped(cap)) CP, so it cannot be used in \(name(key))" }
        return "IVs rank #\(grouped(iv.rank)) of 4,096 · \(oneDecimal(iv.pct))% of best"
    }

    public static func moves(_ r: BoxAdvice.LeagueRating) -> String? {
        guard let m = r.moves else { return nil }
        return "Moves: " + ([m.fast] + m.charged.prefix(2)).joined(separator: ", ")
    }

    /// "Needs A and B", "Needs A"; nil when nothing is missing or the moves are not known (scanned entries carry none).
    public static func needs(_ r: BoxAdvice.LeagueRating) -> String? {
        guard let n = r.needs, !n.isEmpty else { return nil }
        return "Needs " + (n.count == 1 ? n[0] : n.dropLast().joined(separator: ", ") + " and " + n[n.count - 1])
    }

    /// `levelKnown` is whether the Pokémon's own level is known; a missing cost with a known level is explained by the IV line instead.
    public static func cost(_ r: BoxAdvice.LeagueRating, levelKnown: Bool) -> String? {
        guard let c = r.cost else { return levelKnown || r.overCap ? nil : "Level not known, so no cost" }
        if c.dust == 0 && c.candy == 0 && c.xl == 0 && c.evolveCandy == 0 { return "Already at level \(level(c.toLevel))" }
        var s = "To level \(level(c.toLevel)): \(grouped(c.dust)) dust, \(grouped(c.candy)) candy"
        if c.xl > 0 { s += ", \(grouped(c.xl)) XL candy" }
        if c.evolveCandy > 0 { s += " (\(grouped(c.evolveCandy)) to evolve)" }
        return s
    }

    public static let footnote = "A scan cannot tell a Shadow Pokémon, so a Shadow is rated as its normal form here."
}
