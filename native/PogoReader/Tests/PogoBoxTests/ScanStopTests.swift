import XCTest
@testable import PogoBox
import PogoReader

final class ScanStopTests: XCTestCase {
    private func lines(_ name: String) throws -> [ReplayLine] { ReplayLog.lines(in: try Fixture.url(name)) }

    /// What the log says about the appraisal at the end: closed on the real end of the list (run10) and on the tap that closed it mid-list (stall 1), open on the command that
    /// stopped at a batch boundary (stall 2) and on the 1500 command that ran out (run12).
    func testTheLogSaysWhetherTheAppraisalHadClosed() throws {
        XCTAssertEqual(ScanStop.appraisalClosed(lines: try lines("device-run10-tap-25-autoend.replay.jsonl")), true)
        XCTAssertEqual(ScanStop.appraisalClosed(lines: try lines("stall1-stunfisk-closed-tail.replay.jsonl")), true)
        XCTAssertEqual(ScanStop.appraisalClosed(lines: try lines("stall2-abra-open.replay.jsonl")), false)
        XCTAssertEqual(ScanStop.appraisalClosed(lines: try lines("run12-tail.replay.jsonl")), false)
        XCTAssertNil(ScanStop.appraisalClosed(lines: []), "too few readings to say")
    }

    func testTheCommandSizeIsRecognisedWithATolerance() {
        // the 1500 command: 31 x 50 = 1550 page steps, so a reach of 1551; run12 read 1,552
        XCTAssertTrue(ScanStop.ranOut(read: 1552, typedCount: 1500, full: true, commandPeriod: 1.2))
        XCTAssertTrue(ScanStop.ranOut(read: 26, typedCount: 25, full: true, commandPeriod: 1.2), "Pogo scan 25")
        XCTAssertFalse(ScanStop.ranOut(read: 1000, typedCount: 1500, full: true, commandPeriod: 1.2))
        XCTAssertFalse(ScanStop.ranOut(read: 168, typedCount: 1500, full: true, commandPeriod: 1.2), "the stall at the 168th page")
        // a part scan: any size in the set (the 200 command reaches 205; the swipe set's batch of 10 gives its own reach)
        let r200 = VoiceCommandFile.setSizing(size: 200, kind: .tap).covers + 1
        XCTAssertTrue(ScanStop.ranOut(read: r200, typedCount: nil, full: false, commandPeriod: 1.2))
        XCTAssertFalse(ScanStop.ranOut(read: 77, typedCount: nil, full: false, commandPeriod: 1.2))
        // the tolerance: 1% of the reach, at least 3
        XCTAssertEqual(ScanStop.tolerance(reach: 26), 3); XCTAssertEqual(ScanStop.tolerance(reach: 1551), 16)
    }

    func testTheSummarySaysWhereItStoppedWhatToDoAndNeverWhy() {
        let ranOut = ScanStop.summary(lastName: "Psyduck", lastCP: 68, read: 1552, appraisalClosed: false, ranOut: true)
        XCTAssertTrue(ranOut.contains("after 1,552 Pokémon") && ranOut.contains("Psyduck (CP 68)") && ranOut.contains("The appraisal was still open."))
        XCTAssertTrue(ranOut.contains("This is the size of the command the app named for your count: it ran out. To scan the rest, open Psyduck"))
        let short = ScanStop.summary(lastName: "Abra", lastCP: 799, read: 51, appraisalClosed: false, ranOut: false)
        XCTAssertTrue(short.contains("It stopped after 51, short of the command's size. If that was not the end of your list, open Abra in Pokémon GO with the appraisal showing and scan again from there (Add and update)."))
        XCTAssertTrue(ScanStop.summary(lastName: "Rayquaza", lastCP: 4262, read: 11, appraisalClosed: true, ranOut: false).contains("The appraisal had closed."))
        XCTAssertFalse(short.lowercased().contains("because"), "no claim about why")
        XCTAssertFalse(ScanStop.summary(lastName: nil, lastCP: nil, read: 3, appraisalClosed: nil, ranOut: false).contains("appraisal had"))
        // a sound full scan adds the count comparison to the same line
        let d = ScanKindAdvice.decide(endedAtListEnd: true, pokemonRead: 298, typedCount: 300, logTruncated: false, logFailed: false, commandPeriod: 1.2)
        XCTAssertEqual(ScanKindAdvice.matchSentence(pokemonRead: 298, decision: d), "298 Pokémon read, within 3 of the 300 you gave.")
        XCTAssertEqual(ScanKindAdvice.matchSentence(pokemonRead: 300, decision: ScanKindAdvice.decide(endedAtListEnd: true, pokemonRead: 300, typedCount: 300, logTruncated: false, logFailed: false, commandPeriod: 1.2)), "Exactly the 300 you gave.")
        XCTAssertNil(ScanKindAdvice.matchSentence(pokemonRead: 10, decision: ScanKindAdvice.decide(endedAtListEnd: true, pokemonRead: 10, typedCount: 300, logTruncated: false, logFailed: false, commandPeriod: 1.2)))
    }
}
