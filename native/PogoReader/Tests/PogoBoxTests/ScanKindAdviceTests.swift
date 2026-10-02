import XCTest
@testable import PogoBox

final class ScanKindAdviceTests: XCTestCase {
    private func decide(ended: Bool = true, read: Int = 298, count: Int? = 300, truncated: Bool = false, failed: Bool = false, period: Double? = 1.2) -> ScanKindAdvice.Decision {
        ScanKindAdvice.decide(endedAtListEnd: ended, pokemonRead: read, typedCount: count, logTruncated: truncated, logFailed: failed, commandPeriod: period)
    }

    func testAFullScanIsSoundOnlyWhenEverythingAgrees() {
        XCTAssertTrue(decide().fullIsSound)
        XCTAssertNil(decide().reason)
        XCTAssertEqual(ScanKindAdvice.tolerance(300), 6); XCTAssertEqual(ScanKindAdvice.tolerance(25), 3); XCTAssertEqual(ScanKindAdvice.tolerance(5000), 100)
        // the window around the typed count: 300 +- 6
        XCTAssertTrue(decide(read: 294).fullIsSound); XCTAssertFalse(decide(read: 293).fullIsSound)
        XCTAssertTrue(decide(read: 306).fullIsSound); XCTAssertFalse(decide(read: 307).fullIsSound)
    }

    func testAScanCutShortOfTheCountIsNotFull() {
        let d = decide(read: 100)
        XCTAssertFalse(d.fullIsSound); XCTAssertTrue(d.reason!.contains("stopped short of your count"))
        XCTAssertFalse(decide(ended: true, read: 1, count: 25).fullIsSound)
    }

    func testReachMinusOneIsNotSoundForAnyCountThatIsFarFromIt() {
        // "Pogo scan 300" reaches 309; read 308 for a typed 100 is not a full scan of 100 Pokémon (the old advice said yes)
        let reach = VoiceCommandFile.sizing(storageCount: 300, pace: .tapNormal).covers + 1
        XCTAssertFalse(decide(read: reach - 1, count: 200).fullIsSound)
        XCTAssertFalse(decide(read: reach - 1, count: 100).fullIsSound)
        // where the tolerance would pass the command's reach, the reach wins: "Pogo scan 25" pages 25 times (26 Pokémon at most)
        let r25 = VoiceCommandFile.sizing(storageCount: 25, pace: .tapNormal).covers + 1
        XCTAssertTrue(decide(read: r25 - 1, count: 25).fullIsSound)
        let over = decide(read: r25, count: 25)
        XCTAssertFalse(over.fullIsSound); XCTAssertTrue(over.reason!.contains("run out"))
    }

    func testEachRefusalHasItsOwnPlainSentence() {
        let cases: [(ScanKindAdvice.Decision, String)] = [
            (decide(ended: false), "stopped by hand"), (decide(count: 5001, period: 1.2), "above 5,000"), (decide(truncated: true), "incomplete"),
            (decide(failed: true), "incomplete"), (decide(count: nil), "No storage count"), (decide(read: 50), "stopped short"), (decide(read: 400), "more Pokémon than your count"),
        ]
        for (d, text) in cases { XCTAssertFalse(d.fullIsSound); XCTAssertTrue(d.reason!.contains(text), "\(d.reason!) should mention \(text)") }
        XCTAssertEqual(Set(cases.map { $0.0.reason }).count, 7, "seven distinct sentences")
    }

    func testTheLabelNeverClaimsCompletenessUnlessFullIsSound() {
        XCTAssertEqual(ScanKindAdvice.endedLabel(pokemonRead: 298, decision: decide()), "The scan ended by itself after 298 Pokémon. That matches the 300 you gave.")
        XCTAssertEqual(ScanKindAdvice.endedLabel(pokemonRead: 100, decision: decide(read: 100)), "The scan ended by itself after 100 Pokémon.")
    }

    func testTheRecordedPeriodPicksTheSizing() {
        // the swipe set's batch is capped smaller, so its reach can differ; the recorded period (1.6) is used, not the app's current pace
        XCTAssertTrue(decide(period: 1.6).fullIsSound)
        XCTAssertFalse(decide(ended: false, period: nil).fullIsSound)
    }

    func testTheAutoEndPeriodNeedsTheCommandsAndTheChoice() {
        XCTAssertEqual(ScanKindAdvice.autoEndPeriod(wantsCommand: true, commandSetMade: true, pace: .tapNormal), 1.2)
        XCTAssertEqual(ScanKindAdvice.autoEndPeriod(wantsCommand: true, commandSetMade: true, pace: .swipeFast), 1.6)
        XCTAssertNil(ScanKindAdvice.autoEndPeriod(wantsCommand: true, commandSetMade: false, pace: .tapNormal), "no command set was ever made")
        XCTAssertNil(ScanKindAdvice.autoEndPeriod(wantsCommand: false, commandSetMade: true, pace: .tapNormal), "paging by hand")
        XCTAssertTrue(ScanKindAdvice.defaultsToHand(commandSetMade: false)); XCTAssertFalse(ScanKindAdvice.defaultsToHand(commandSetMade: true))
    }
}
