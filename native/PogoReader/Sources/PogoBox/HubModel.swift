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

    /// The gaps (top-tier Pokémon nothing in the box can become) for a screen, by the area label the report gives them.
    public static func gaps(_ gaps: [BoxAdvice.Gap], for key: ContentKey) -> [BoxAdvice.Gap] {
        guard let labels = key.areaLabels else { return gaps }
        return gaps.filter { labels.contains($0.area) }
    }

    public static func count(_ builds: [BoxAdvice.Build], for key: ContentKey) -> Int { self.builds(builds, for: key).count }

    /// The builds, in the advisor's order, that the stardust pays for: each dusty build is taken while the running total stays within the
    /// stardust, and the first one that does not fit ends the dust spending (a cheaper build further down does not jump the queue).
    /// A build that needs no dust still fits (an evolve paid in candy), but a build with nothing left to do is not listed at all.
    public static func fitting(_ builds: [BoxAdvice.Build], stardust: Int) -> (fits: [BoxAdvice.Build], used: Int, left: Int) {
        var fits = [BoxAdvice.Build](), used = 0, open = true
        for b in builds where needsSomething(b) {
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

    /// `doFirst`: the advisor's first build that has something to do. `cheapWin`: the lowest-dust S or A build (then lowest candy, then advisor order) that still
    /// needs something and is not `doFirst`. `worthSavingFor`: the highest-score build that costs more dust than is on hand (without a
    /// known stardust: the highest-dust S-tier build), and neither of the other two.
    public static func headlines(_ builds: [BoxAdvice.Build], stardust: Int?) -> (doFirst: BoxAdvice.Build?, cheapWin: BoxAdvice.Build?, worthSavingFor: BoxAdvice.Build?) {
        let first = builds.first(where: needsSomething)
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

    /// 612400 as "612,400".
    public static func grouped(_ n: Int) -> String {
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

    /// A headline card's title: what to do first, then the Pokémon. "Evolve Eevee → Flareon", "Mega evolve Lucario", "Power up Xerneas";
    /// the Pokémon's name alone when nothing is left to do.
    public static func headline(for b: BoxAdvice.Build) -> String {
        switch b.steps?.first?.kind {
        case "evolve": return "Evolve \(b.title) → \(b.steps?.first?.to ?? b.targetName)"
        case "formChange": return "Form change \(b.title) → \(b.steps?.first?.to ?? b.targetName)"
        case "megaEvolve": return "Mega evolve \(b.title)"
        case "powerUp": return "Power up \(b.title)"
        case "secondMove": return "Second move for \(b.title)"
        case "eliteTM": return "Elite TM for \(b.title)"
        case "cdMove": return "Community Day move for \(b.title)"
        default: return b.title
        }
    }

    /// A headline card's line: the cost, then the first area ("75k dust · Raids").
    public static func cardLine(for b: BoxAdvice.Build) -> String {
        let first = areaWords(b).components(separatedBy: ", ").first ?? ""
        return first.isEmpty ? costShort(b) : "\(costShort(b)) · \(first)"
    }

    /// The design's sub line: "Gym, Max · 10k dust".
    public static func areaLabel(for b: BoxAdvice.Build) -> String {
        let words = areaWords(b)
        return words.isEmpty ? costShort(b) : "\(words) · \(costShort(b))"
    }
}

// MARK: the events strip

extension HubModel {
    /// The local calendar day as `yyyy-mm-dd`, the form the rotation and events carry.
    /// The dates in `hub.json` are Gregorian, so the day is read with a Gregorian calendar in the device's time zone, whatever calendar
    /// the device uses (a Japanese or Buddhist year would otherwise give "0008-10-25").
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The events whose last day is `today` or later, by first day (events starting the same day keep their order in the file).
    public static func upcoming(_ events: [HubData.Event], today: String) -> [HubData.Event] {
        events.enumerated().filter { $0.element.to >= today }
            .sorted { ($0.element.from, $0.offset) < ($1.element.from, $1.offset) }.map(\.element)
    }

    private static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    private static func day(_ key: String) -> (d: Int, m: String)? {
        let p = key.split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]), (1...12).contains(m) else { return nil }
        return (d, months[m - 1])
    }

    /// An event's dates: `kicker` is the card's small caps line ("1 – 5 NOV", "28 OCT – 3 NOV", "21 NOV", "NOW TO 1 DEC" once it has begun),
    /// `spoken` the same for VoiceOver ("1 to 5 November", "now to 1 December").
    public static func span(from: String, to: String, today: String) -> (kicker: String, spoken: String) {
        guard let f = day(from), let t = day(to) else { return ("", "") }
        func short(_ x: (d: Int, m: String)) -> String { "\(x.d) \(x.m.prefix(3).uppercased())" }
        func long(_ x: (d: Int, m: String)) -> String { "\(x.d) \(x.m)" }
        if from < today { return ("NOW TO \(short(t))", "now to \(long(t))") }
        if from == to { return (short(f), long(f)) }
        if f.m == t.m { return ("\(f.d) – \(short(t))", "\(f.d) to \(long(t))") }
        return ("\(short(f)) – \(short(t))", "\(long(f)) to \(long(t))")
    }
}
