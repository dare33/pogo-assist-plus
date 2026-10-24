import Foundation

/// Which Hub screen a count or a build list is for. `pvp` is any of the three leagues; `everything` is every build.
public enum ContentKey: String, CaseIterable, Identifiable {
    case everything, raids, gym, rocket, pvp, max
    public var id: String { rawValue }
    /// The area labels (`BoxAdvice.areaLabel` values, which is what `Build.areas` holds) that put a build on this screen.
    var areaLabels: [String]? {
        switch self {
        case .everything: return nil
        case .raids: return ["Raids"]
        case .gym: return ["Gym"]
        case .rocket: return ["Rocket"]
        case .pvp: return ["GL", "UL", "ML"]
        case .max: return ["Max"]
        }
    }
}

/// The Pogo Hub's derivations from the advice report: counts per screen, which builds fit the stardust on hand, the three headline
/// cards and the short wording of dust and areas. Pure, so the fixture report pins them (`HubModelTests`).
public enum HubModel {
    public static func builds(_ builds: [BoxAdvice.Build], for key: ContentKey) -> [BoxAdvice.Build] {
        guard let labels = key.areaLabels else { return builds }
        return builds.filter { b in b.areas.contains { labels.contains($0) } }
    }

    public static func count(_ builds: [BoxAdvice.Build], for key: ContentKey) -> Int { self.builds(builds, for: key).count }

    /// The builds, in the advisor's order, that the stardust pays for: each dusty build is taken while the running total stays within the
    /// stardust, and the first one that does not fit ends the dust spending (a cheaper build further down does not jump the queue).
    /// A build that needs no dust always fits.
    public static func fitting(_ builds: [BoxAdvice.Build], stardust: Int) -> (fits: [BoxAdvice.Build], used: Int, left: Int) {
        var fits = [BoxAdvice.Build](), used = 0, open = true
        for b in builds {
            if b.dust <= 0 { fits.append(b); continue }
            guard open else { continue }
            if used + b.dust <= stardust { fits.append(b); used += b.dust } else { open = false }
        }
        return (fits, used, max(0, stardust - used))
    }

    /// True when the build has something the player can do (a step other than the Dynamax requirement, which is set on the Pokémon's
    /// page); a build read without `steps` counts as having something to do.
    static func needsSomething(_ b: BoxAdvice.Build) -> Bool {
        guard let steps = b.steps else { return true }
        return steps.contains { $0.kind != "needsDynamaxCopy" }
    }

    /// `doFirst`: the advisor's first build. `cheapWin`: the lowest-dust S or A build (then lowest candy, then advisor order) that still
    /// needs something and is not `doFirst`. `worthSavingFor`: the highest-score build that costs more dust than is on hand (without a
    /// known stardust: the highest-dust S-tier build), and neither of the other two.
    public static func headlines(_ builds: [BoxAdvice.Build], stardust: Int?) -> (doFirst: BoxAdvice.Build?, cheapWin: BoxAdvice.Build?, worthSavingFor: BoxAdvice.Build?) {
        let first = builds.first
        let cheap = builds.filter { ($0.tier == "S" || $0.tier == "A") && $0.id != first?.id && needsSomething($0) }
            .enumerated().min { l, r in (l.element.dust, l.element.candy, l.offset) < (r.element.dust, r.element.candy, r.offset) }?.element
        let rest = builds.filter { $0.id != first?.id && $0.id != cheap?.id }
        let saving: BoxAdvice.Build?
        if let stardust {
            saving = rest.filter { $0.dust > stardust }.enumerated().max { l, r in l.element.score != r.element.score ? l.element.score < r.element.score : l.offset > r.offset }?.element
        } else {
            saving = rest.filter { $0.tier == "S" }.enumerated().max { l, r in l.element.dust != r.element.dust ? l.element.dust < r.element.dust : l.offset > r.offset }?.element
        }
        return (first, cheap, saving)
    }

    /// "6,600" under 10k, "57k", "489k", "1.2M".
    public static func dustShort(_ n: Int) -> String {
        if n < 10_000 { return grouped(n) }
        if n < 999_500 { return "\(Int((Double(n) / 1000).rounded()))k" }
        let m = (Double(n) / 100_000).rounded() / 10
        return m == m.rounded() ? "\(Int(m))M" : "\(m)M"
    }

    private static func grouped(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "en_US"); f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    /// The build's cost in a few words: "10k dust", else "100 candy" when it needs no dust, else "Free".
    public static func costShort(_ b: BoxAdvice.Build) -> String {
        if b.dust > 0 { return "\(dustShort(b.dust)) dust" }
        if b.candy > 0 { return "\(b.candy) candy" }
        return "Free"
    }

    /// The areas as words: Raids, Gym, Rocket and Max as they are, the leagues as "PvP" (the league's own name when it is the only area).
    public static func areaWords(_ b: BoxAdvice.Build) -> String {
        let names = ["GL": "Great League", "UL": "Ultra League", "ML": "Master League"]
        let leagues = b.areas.filter { names[$0] != nil }
        var words = b.areas.filter { names[$0] == nil }
        if leagues.count == 1 && words.isEmpty { return names[leagues[0]] ?? leagues[0] }
        if !leagues.isEmpty { words.append("PvP") }
        return words.joined(separator: ", ")
    }

    /// The design's sub line: "Gym, Max · 10k dust".
    public static func areaLabel(for b: BoxAdvice.Build) -> String {
        let words = areaWords(b)
        return words.isEmpty ? costShort(b) : "\(words) · \(costShort(b))"
    }
}
