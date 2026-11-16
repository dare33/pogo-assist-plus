import XCTest
import PogoBox
import PogoReader
@testable import PogoAssist

/// P1: what a picker row model gains from `adding`: the CP and IV line, the bar and the words VoiceOver adds.
final class PickerRowFiguresTests: XCTestCase {
    private func entry(cp: Int = 3412, ivs: IVs? = IVs(atk: 15, def: 14, hp: 15)) -> BoxEntry {
        let row = ScanRow(index: 1, name: "Palkia", display: "Palkia", form: "", speciesId: "palkia", dex: 484, cp: cp, hp: 100, ivs: ivs, ivsRead: ivs, ivsGuess: nil,
                          level: 30, levelMax: 30, dust: nil, solveStatus: "exact", flags: [], frames: [])
        return BoxEntry(id: "a", row: row, firstSeen: Date(), lastSeen: Date())
    }
    private func model(spoken: String = "Palkia, Heavy hitter, tier A, upgrade available") -> PickerRowModel { PickerRowModel(id: "a", name: "Palkia", ticked: false, spoken: spoken) }

    func testARowGainsItsCpIvLineAndWordsBeforeInThisSlot() {
        var m = model(spoken: "Palkia, tier A, in this slot")
        m = m.adding(copy: entry(), strength: Strength(kind: .damage, now: 0.62, after: 0.85))
        XCTAssertEqual(m.cpIv, "CP 3,412 · 15/14/15")
        XCTAssertEqual(m.spoken, "Palkia, tier A, CP 3412, IVs 15, 14, 15, estimated damage 62 percent of the best, 85 percent after upgrade, in this slot")
        XCTAssertNotNil(m.strength)
    }

    func testUnreadValuesSayNotRead() {
        let m = model().adding(copy: entry(cp: 0, ivs: nil), strength: Strength(kind: .damage, now: nil, after: nil))
        XCTAssertEqual(m.cpIv, "CP not read · IVs not read")
        XCTAssertNil(m.strength, "no bar when nothing could be worked out")
        XCTAssertTrue(m.spoken.hasSuffix("CP not read, IVs not read, estimated damage not read"), m.spoken)
    }

    func testAPokemonTheBoxLacksHasNoCpLine() {
        let m = model().adding(copy: nil, strength: Strength(kind: .damage, now: 0.7, after: nil, assumed: true))
        XCTAssertNil(m.cpIv)
        XCTAssertTrue(m.spoken.hasSuffix("estimated damage 70 percent of the best, at level 50 with 15, 15, 15"), m.spoken)
    }

    func testPvPShowsIVsAndDoesNotSaySTheScoreTwice() {
        let m = model(spoken: "Zapdos, score 86.4").adding(copy: entry(), strength: .score(86.4), speaksStrength: false)
        XCTAssertEqual(m.cpIv, "CP 3,412 · 15/14/15")
        XCTAssertEqual(m.spoken.components(separatedBy: "score").count - 1, 1, m.spoken)
        XCTAssertEqual(m.strength?.barSolid ?? 0, 0.864, accuracy: 1e-9)
    }

    func testAPvpRowWithNoScoreSaysSoAndHasNoBar() {
        let m = model().adding(copy: nil, strength: .scoreNotKnown)
        XCTAssertNil(m.strength)
        XCTAssertTrue(m.spoken.hasSuffix("score not known"), m.spoken)
    }

    func testSpokenTextUsesCommasNotMiddleDots() {
        let m = model().adding(copy: entry(), strength: Strength(kind: .bulk, now: 0.5, after: 0.7))
        XCTAssertFalse(m.spoken.contains(" · "))
    }
}
