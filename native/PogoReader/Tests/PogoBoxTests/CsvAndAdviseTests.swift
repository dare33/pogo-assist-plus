import Foundation
import XCTest
@testable import PogoBox
import PogoReader

final class CsvAndAdviseTests: XCTestCase {
    private func blankScanDates(_ csv: String) -> [[String]] {
        csv.split(separator: "\n", omittingEmptySubsequences: true).map { line in
            var cols = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            // Scan Date, Original Scan Date (no field in the fixture holds a comma or a quote)
            if cols.count > 17 { cols[16] = ""; cols[17] = "" }
            return cols
        }
    }

    func testCsvEqualsTheJavaScriptCliApartFromScanDates() throws {
        let rows = try Fixture.expected().rows
        let csv = try sharedEngine.csv(rows: rows, scanDate: Date())
        XCTAssertEqual(blankScanDates(csv), blankScanDates(try Fixture.expectedCSV()))
        XCTAssertTrue(csv.hasPrefix("Index,Name,Form,Pokemon Number,Gender,CP,HP,Atk IV"))
        XCTAssertTrue(csv.hasSuffix("\n"))
    }

    func testCsvScanDateIsTheOneGiven() throws {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 2; c.hour = 12; c.minute = 0
        let date = try XCTUnwrap(Calendar.current.date(from: c))
        let csv = try sharedEngine.csv(rows: try Fixture.expected().rows, scanDate: date)
        XCTAssertEqual(csv, try Fixture.expectedCSV(), "same local time as the Node-generated fixture (2026-10-02 12:00)")
    }

    func testCsvRoundTripsThroughImportPokeGenie() throws {
        let rows = try sharedEngine.finish(readings: try Fixture.readings()).rows
        let imported = try sharedEngine.importPokeGenie(csv: try sharedEngine.csv(rows: rows))
        let records = try XCTUnwrap(imported.arrayValue)
        XCTAssertEqual(records.count, rows.count)
        for (r, rec) in zip(rows, records) {
            XCTAssertEqual(rec["name"], .string(r.name))
            XCTAssertEqual(rec["form"], .string(r.form))
            XCTAssertEqual(rec["cp"], .number(Double(r.cp)))
            XCTAssertEqual(rec["hp"], r.hp.map { .number(Double($0)) } ?? .null)
            if let ivs = r.ivs { XCTAssertEqual(rec["ivs"], .object(["atk": .number(Double(ivs.atk)), "def": .number(Double(ivs.def)), "hp": .number(Double(ivs.hp))])) } else { XCTAssertEqual(rec["ivs"], .null) }
            // the CSV carries levels to one decimal, which is exact for half levels
            XCTAssertEqual(rec["levelMax"], r.levelMax.map { .number($0) } ?? .null)
            XCTAssertEqual(rec["level"], r.level.map { .number($0) } ?? .null)
            XCTAssertEqual(rec["dust"], r.dust.map { .number(Double($0)) } ?? .null)
        }
    }

    func testAdviseRunsOnTheFixtureBox() throws {
        let report = try sharedEngine.advise(rows: try Fixture.expected().rows)
        XCTAssertNotNil(report["builds"]?.arrayValue)
        XCTAssertNotNil(report["gaps"]?.arrayValue)
        XCTAssertNotNil(report["hygiene"]?.arrayValue)
        XCTAssertFalse(try XCTUnwrap(report["builds"]?.arrayValue).isEmpty, "Lucario 3000 etc. should give builds")
    }

    func testMergeClipsJoinsTwoClipsOnTheirOverlap() throws {
        let rows = try Fixture.expected().rows
        // Clip B restarts on the last Pokémon of clip A, as a recording overlap does.
        let a = ClipInput(name: "a", rows: Array(rows[0..<4]))
        let b = ClipInput(name: "b", rows: Array(rows[3...]))
        let merged = try sharedEngine.mergeClips([a, b])
        XCTAssertEqual(merged["rows"]?.arrayValue?.count, rows.count)
        XCTAssertEqual(merged["boundaries"]?.arrayValue?.count, 1)
    }
}
