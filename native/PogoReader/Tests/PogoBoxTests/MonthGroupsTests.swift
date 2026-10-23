import Foundation
import XCTest
@testable import PogoBox

final class MonthGroupsTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }

    func testMonthsAreDistinctAndNewestFirst() {
        let dates = [day(2026, 9, 30), day(2026, 10, 1), day(2026, 10, 20), day(2025, 12, 31)]
        let months = MonthGroups.months(of: dates, date: { $0 }, calendar: cal)
        XCTAssertEqual(months, [MonthKey(year: 2026, month: 10), MonthKey(year: 2026, month: 9), MonthKey(year: 2025, month: 12)])
    }

    func testNoItemsNoMonths() {
        XCTAssertEqual(MonthGroups.months(of: [Date](), date: { $0 }, calendar: cal), [])
    }

    func testFilterKeepsOrderAndNilKeepsAll() {
        let dates = [day(2026, 10, 20), day(2026, 9, 2), day(2026, 10, 1)]
        XCTAssertEqual(MonthGroups.filter(dates, to: nil, date: { $0 }, calendar: cal), dates)
        XCTAssertEqual(MonthGroups.filter(dates, to: MonthKey(year: 2026, month: 10), date: { $0 }, calendar: cal), [dates[0], dates[2]])
        XCTAssertEqual(MonthGroups.filter(dates, to: MonthKey(year: 2026, month: 8), date: { $0 }, calendar: cal), [])
    }

    func testTitle() {
        XCTAssertEqual(MonthKey(year: 2026, month: 10).title(calendar: cal, locale: Locale(identifier: "en_AU")), "Oct 2026")
    }

    /// 00:30 on 1 November in Sydney is still 31 October in UTC: the month is the one in the zone given.
    func testSydneyMidnightBoundary() {
        let sydney = TimeZone(identifier: "Australia/Sydney")!
        var syd = Calendar(identifier: .gregorian); syd.timeZone = sydney
        let d = syd.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0, minute: 30))!
        XCTAssertEqual(MonthKey(d, timeZone: sydney), MonthKey(year: 2026, month: 11))
        XCTAssertEqual(MonthKey(d, timeZone: TimeZone(identifier: "UTC")!), MonthKey(year: 2026, month: 10))
        XCTAssertEqual(MonthGroups.months(of: [d], date: { $0 }, calendar: MonthKey.grouping(timeZone: sydney)), [MonthKey(year: 2026, month: 11)])
    }

    /// The default grouping calendar is Gregorian in the current zone; a device on the Japanese calendar would read 2026 as Reiwa 8 if `.current` were used.
    func testDefaultGroupingIsGregorianNotTheDeviceCalendar() {
        XCTAssertEqual(MonthKey.grouping().identifier, .gregorian)
        XCTAssertEqual(MonthKey.grouping().timeZone.identifier, TimeZone.current.identifier, "the default is the current zone, not UTC")
        XCTAssertEqual(MonthKey(day(2026, 10, 5)), MonthKey(day(2026, 10, 5), timeZone: .current))
        let japanese = Calendar(identifier: .japanese)
        let d = day(2026, 10, 5)
        XCTAssertEqual(japanese.component(.year, from: d), 8, "the Japanese calendar numbers this year differently")
        XCTAssertEqual(MonthKey(d, calendar: japanese).year, 8, "grouping by the device calendar would change the key")
        XCTAssertEqual(MonthKey(d).year, 2026)
    }
}
