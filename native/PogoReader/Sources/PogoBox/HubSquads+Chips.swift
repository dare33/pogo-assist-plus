import Foundation

/// Pass 2-6, rule 35: the words behind the status chips of a Best row that the row does not carry as fields: how hard the research says a Pokémon is to obtain, and when a Pokémon that
/// is not available now is next on. Pure, so the sentences the chips replace and the chips that stand for them can be tested together.
extension HubSquads {
    /// How hard the research's obtain text ("Medium. T5 raids") says a Pokémon is to get.
    public enum ObtainDifficulty: Int, Equatable {
        case easy = 1, medium, hard

        public var word: String { self == .easy ? "Easy" : self == .medium ? "Medium" : "Hard" }
        /// "▮▯▯" for Easy, "▮▮▯" for Medium, "▮▮▮" for Hard.
        public var meter: String { String(repeating: "▮", count: rawValue) + String(repeating: "▯", count: 3 - rawValue) }
    }

    /// The difficulty word the obtain text opens with (up to its first full stop). A range or a list ("Easy/Medium") reads as its hardest word; nil when the text names none.
    public static func obtainDifficulty(_ obtain: String) -> ObtainDifficulty? {
        let head = obtain.split(separator: ".", maxSplits: 1).first.map(String.init)?.lowercased() ?? ""
        if head.contains("hard") { return .hard }
        if head.contains("medium") { return .medium }
        if head.contains("easy") { return .easy }
        return nil
    }

    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// When a Pokémon that is not available now is next on, for the "Not now" chip: "9 Nov" when the day is within a month of `today` (`yyyy-mm-dd`), else the month alone ("Dec").
    /// `rotationLine` is the schedule's line ("Raids from 9 Nov", "Max Monday 2 Nov"); nil when it has no date (the table's own reason, or no schedule entry).
    public static func notNowWhen(rotationLine: String?, today: String) -> String? {
        guard let line = rotationLine,
              let m = line.range(of: #"(\d{1,2}) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)$"#, options: .regularExpression) else { return nil }
        let parts = line[m].split(separator: " ")
        guard parts.count == 2, let day = Int(parts[0]), let month = monthNames.firstIndex(of: String(parts[1])).map({ $0 + 1 }) else { return nil }
        let t = today.split(separator: "-").compactMap { Int($0) }
        guard t.count == 3 else { return String(parts[1]) }
        // The line has no year: the next such day on or after today.
        let year = (month, day) < (t[1], t[2]) ? t[0] + 1 : t[0]
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let from = cal.date(from: DateComponents(year: t[0], month: t[1], day: t[2])), let to = cal.date(from: DateComponents(year: year, month: month, day: day)),
              let days = cal.dateComponents([.day], from: from, to: to).day else { return String(parts[1]) }
        return days <= 31 ? "\(day) \(parts[1])" : String(parts[1])
    }
}

extension HubSquads.BestRow {
    /// The meter beside "Get now": only for a Pokémon the box lacks that the research's obtain text says is easy, medium or hard to get (a boss on the schedule has none).
    public var difficulty: HubSquads.ObtainDifficulty? {
        status.kind == .canGetNow && rotationLine == nil ? HubSquads.obtainDifficulty(availability) : nil
    }
}
