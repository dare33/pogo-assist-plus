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
}
