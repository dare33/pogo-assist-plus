import Foundation

/// A calendar month, for the History and scans screen's month picker. Comparable so months sort newest first.
public struct MonthKey: Hashable, Comparable, Sendable {
    public var year: Int
    public var month: Int
    public init(year: Int, month: Int) { self.year = year; self.month = month }
    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month], from: date)
        self.init(year: c.year ?? 0, month: c.month ?? 0)
    }
    public static func < (a: MonthKey, b: MonthKey) -> Bool { (a.year, a.month) < (b.year, b.month) }

    /// "Oct 2026", in the person's language and calendar.
    public func title(calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let d = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return "\(month)/\(year)" }
        let f = DateFormatter()
        f.calendar = calendar; f.locale = locale
        f.setLocalizedDateFormatFromTemplate("MMM yyyy")
        return f.string(from: d)
    }
}

public enum MonthGroups {
    /// The months that have at least one entry, newest first.
    public static func months<T>(of items: [T], date: (T) -> Date, calendar: Calendar = .current) -> [MonthKey] {
        Array(Set(items.map { MonthKey(date($0), calendar: calendar) })).sorted(by: >)
    }

    /// The items in `month` (all of them when nil), in their given order.
    public static func filter<T>(_ items: [T], to month: MonthKey?, date: (T) -> Date, calendar: Calendar = .current) -> [T] {
        guard let month else { return items }
        return items.filter { MonthKey(date($0), calendar: calendar) == month }
    }
}
