import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// The "CP covered from here" line (kind "c") is not a `ReplayLine` case: the box engine's loader must read the same readings with or without it.
final class CpCoveredNoteTests: XCTestCase {
    func testTheLoaderReadsTheSameReadingsWithAndWithoutTheNoteAndCountsItAsASkippedLine() throws {
        func rline(_ t: Double) -> String { "{\"k\":\"r\",\"t\":\(t),\"cp\":1000,\"cpText\":\"CP1000\",\"name\":\"Zapdos\",\"nameText\":\"Zapdos\",\"hpText\":\"\",\"ivConfidence\":0,\"ms\":5,\"flags\":[]}" }
        let note = String(decoding: ReplayLog.encode(CpCoveredNote(t: 1.1, first: "Smoliv", lastGood: "Snorlax", lastGoodCp: 133)), as: UTF8.self)
        let plain = try ReplayReadings.parse(Data([rline(1.0), "{\"k\":\"t\",\"t\":1.3}", rline(1.6)].joined(separator: "\n").utf8))
        let noted = try ReplayReadings.parse(Data([rline(1.0), note, "{\"k\":\"t\",\"t\":1.3}", rline(1.6)].joined(separator: "\n").utf8))
        XCTAssertEqual(noted.readings.map(\.time), plain.readings.map(\.time))
        XCTAssertEqual(noted.ticks, plain.ticks)
        XCTAssertEqual(noted.skippedLines, plain.skippedLines + 1)
        XCTAssertEqual(noted.malformedLines, 0)
    }
}
