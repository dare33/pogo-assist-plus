import XCTest
@testable import PogoBox

final class ScanKindAdviceTests: XCTestCase {
    private func decide(ended: Bool = true, read: Int = 290, count: Int? = 300, truncated: Bool = false) -> ScanKindAdvice.Decision {
        ScanKindAdvice.decide(endedAtListEnd: ended, pokemonRead: read, typedCount: count, logTruncated: truncated, pace: .tapNormal)
    }

    func testAFullScanIsSoundOnlyWhenTheListEndedBeforeTheCommandRanOut() {
        XCTAssertEqual(decide(), ScanKindAdvice.Decision(fullIsSound: true, reason: nil))
        // "Pogo scan 300" pages sizing(300).covers times: 7 x 44 = 308, so 309 Pokémon is its reach
        let reach = VoiceCommandFile.sizing(storageCount: 300, pace: .tapNormal).covers + 1
        XCTAssertTrue(decide(read: reach - 1).fullIsSound)
        XCTAssertFalse(decide(read: reach).fullIsSound)
        XCTAssertTrue(decide(read: reach).reason!.contains("ran out"))
    }

    func testEachOtherCaseDefaultsToAddAndUpdateWithOneSentence() {
        XCTAssertTrue(decide(ended: false).reason!.contains("stopped by hand"))
        XCTAssertTrue(decide(count: 5001).reason!.contains("above 5,000"))
        XCTAssertTrue(decide(truncated: true).reason!.contains("log filled up"))
        XCTAssertTrue(decide(count: nil).reason!.contains("No storage count"))
        for d in [decide(ended: false), decide(count: 5001), decide(truncated: true), decide(count: nil)] { XCTAssertFalse(d.fullIsSound); XCTAssertEqual(d.reason!.filter { $0 == "." }.count, 2, "a plain sentence or two") }
    }

    func testTheLargestCommandWorks() {
        let reach = VoiceCommandFile.sizing(storageCount: 5000, pace: .tapNormal).covers + 1
        XCTAssertTrue(decide(read: reach - 1, count: 5000).fullIsSound)
        XCTAssertFalse(decide(read: reach, count: 5000).fullIsSound)
    }
}
