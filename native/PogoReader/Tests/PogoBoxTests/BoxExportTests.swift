import Foundation
import XCTest
@testable import PogoBox
import PogoReader

final class BoxExportTests: XCTestCase {
    private var date: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 12))! }
    private func entries() throws -> [BoxEntry] {
        try Fixture.expected().rows.enumerated().map { i, r in BoxEntry(id: "e\(i)", row: r, firstSeen: date, lastSeen: date) }
    }
    private func tableRows(_ md: String) -> [String] { md.split(separator: "\n").map(String.init).filter { $0.hasPrefix("| ") && !$0.hasPrefix("| #") && !$0.hasPrefix("| ---") } }

    func testHeaderAndOneRowPerPokemonWithAdvice() throws {
        let es = try entries()
        let report = try sharedEngine.advise(rows: es.map(\.row))
        let advice = BoxAdvice.make(from: report, entries: es)
        let md = BoxExport.markdown(entries: es, advice: advice, account: "Greg main", date: date)
        XCTAssertTrue(md.hasPrefix("# Pokémon GO box, exported from Pogo Assist+\n"))
        XCTAssertTrue(md.contains("- Account: Greg main"))
        XCTAssertTrue(md.contains("- Box date (the scan this box was last saved from): 2026-10-02"))
        XCTAssertTrue(md.contains("- Pokémon in this file: \(es.count)"))
        XCTAssertTrue(md.contains("- Advice: included"))
        XCTAssertTrue(md.contains("- To check: \"yes\" means the scan could not read"))
        XCTAssertTrue(md.contains("| # | Pokémon | CP | Level | HP | IVs | IV % | Dust | Flags | First seen | Last seen | To check | Mega CP | Advice |"))
        let rows = tableRows(md)
        XCTAssertEqual(rows.count, es.count)
        let first = es[0].row
        let ivs = try XCTUnwrap(first.ivs)
        XCTAssertTrue(rows[0].hasPrefix("| 1 | \(first.title) | \(first.cp) | "), rows[0])
        XCTAssertTrue(rows[0].contains(" | \(ivs.atk)/\(ivs.def)/\(ivs.hp) | "), rows[0])
        XCTAssertTrue(rows[0].contains(" | 2026-10-02 | 2026-10-02 | "), rows[0])
        XCTAssertTrue(md.hasSuffix("|\n"))
        // Every row has as many cells as the header.
        XCTAssertTrue(rows.allSatisfy { $0.components(separatedBy: " | ").count == 14 }, "a row has the wrong number of cells")
        if let b = advice.builds.first, let i = es.firstIndex(where: { $0.id == b.entryId }) {
            XCTAssertTrue(rows[i].contains("[tier \(b.tier)"), rows[i])
        } else { XCTFail("the fixture box has no build") }
    }

    func testWithoutAdviceTheHeaderSaysSoAndThereIsNoAdviceColumn() throws {
        let es = try entries()
        let md = BoxExport.markdown(entries: es, advice: nil, account: "a|b", date: date)
        XCTAssertTrue(md.contains("- Advice: NOT included"))
        XCTAssertFalse(md.contains("| Advice |"))
        XCTAssertEqual(tableRows(md).count, es.count)
        XCTAssertTrue(tableRows(md).allSatisfy { $0.components(separatedBy: " | ").count == 13 })
    }

    func testMegaCpCheckAndFlagsShowInTheirColumns() throws {
        var es = try entries()
        es[0].row.shadow = 1
        es[0].megaForm = MegaForm(row: es[0].row, firstSeen: date, lastSeen: date)
        es[0].megaForm?.cp = 3970
        es[1].row.flags = ["no-level-fits"]
        es[1].corrections = Corrections(cp: Fix(was: 10))
        let rows = tableRows(BoxExport.markdown(entries: es, advice: nil, account: "x", date: date))
        XCTAssertTrue(rows[0].contains("(Shadow)") && rows[0].contains(" | Shadow | ") && rows[0].hasSuffix(" | no | 3970 |"), rows[0])
        XCTAssertTrue(rows[1].contains(" | Hand-corrected | ") && rows[1].contains(" | yes | "), rows[1])
    }

    func testFileName() {
        XCTAssertEqual(BoxExport.fileName(account: "Greg main", date: date), "pogo-box-Gregmain-2026-10-02.md")
        XCTAssertEqual(BoxExport.fileName(account: "??", date: date), "pogo-box-box-2026-10-02.md")
    }
}
