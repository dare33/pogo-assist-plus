import Foundation
import XCTest
@testable import PogoBox
@testable import PogoReader

/// A damaged Pokémon is now read, and its CURRENT HP is the figure most often misread between frames (19 / 190, then 9 / 190,
/// then 0 / 190): a card's identity in the end wait, the pause and the stalled-card anchor is its name and MAX HP only. A real
/// change of the max is still another card.
final class CurrentHpIdentityTests: XCTestCase {
    private func card(_ cp: Int?, current: Int, max: Int = 190, bars: Bool = true) -> FrameReading {
        var f = FrameReading(); f.name = "Rayquaza"; f.hp = HP(current: current, max: max); f.cp = cp
        if bars { f.ivs = IVs(atk: 13, def: 12, hp: 14); f.ivConfidence = 0.9 }
        return f
    }

    func testTheEndDetectorTakesACurrentHpMisreadForTheSameCard() {
        var d = EndOfListDetector(period: 1.2)
        var t = 0.0
        func feed(_ r: FrameReading) { d.feed(r, time: t); t += 0.2 }
        for _ in 0..<5 { feed(card(4262, current: 19)) }
        let before = d.resets
        for c in [9, 19, 0, 19, 9, 0] { feed(card(4262, current: c)) }
        XCTAssertEqual(d.resets, before, "19 / 190, 9 / 190 and 0 / 190 are one card")
        XCTAssertEqual(d.currentCard.hp, "190", "the card's HP identity is the max")
        feed(card(4262, current: 19, max: 150))
        XCTAssertEqual(d.resets, before + 1, "another max HP is another card")
    }

    /// run10 up to its pause, then the paused card read again with another CURRENT HP (a misread, or a battle): not a resume.
    func testAPausedCardWithAnotherCurrentHpDoesNotResumeButAnotherMaxDoes() throws {
        let rs = ReplayLog.lines(in: try Fixture.url("device-run10-tap-25-autoend.replay.jsonl")).compactMap { l -> ReplayReading? in if case .reading(let r) = l { return r } else { return nil } }.sorted { $0.t < $1.t }
        func paused() throws -> (c: ScanEndController, at: Double, card: FrameReading) {
            var c = ScanEndController(period: 1.2, storageCount: 1729)!
            var g = LiveGrouper(species: try? SpeciesTable.bundled())
            for r in rs {
                g.add(r.frameReading)
                if case .pause = c.feed(r.frameReading, time: r.t, read: g.rows.count) {
                    return (c, r.t, rs.last { $0.t <= r.t && $0.frameReading.name != nil && $0.frameReading.hp != nil }!.frameReading)
                }
            }
            throw XCTSkip("run10 did not pause")
        }
        var (c, at, base) = try paused()
        base.ivs = nil
        var t = at
        for i in 0..<20 {
            t += 0.4
            var r = base; r.hp = HP(current: max(0, base.hp!.max - 3 - i), max: base.hp!.max)
            let e = c.feed(r, time: t, read: 11)
            if case .resume = e { XCTFail("a different CURRENT HP resumed the pause at reading \(i)") }
        }
        var (c2, at2, base2) = try paused()
        base2.ivs = nil
        var sawResume = false
        for i in 0..<10 {
            var r = base2; r.hp = HP(current: base2.hp!.max, max: base2.hp!.max + 7)
            if case .resume = c2.feed(r, time: at2 + 0.4 * Double(i + 1), read: 11) { sawResume = true }
        }
        XCTAssertTrue(sawResume, "another MAX HP is another card and resumes")
    }

    func testTheStalledCardAnchorSurvivesACurrentHpMisread() {
        var n = StalledCardNormaliser()
        _ = n.feed(card(4262, current: 19))
        let live = n.feed(card(262, current: 9, bars: false))
        XCTAssertEqual(live.cp, 4262, "the barless reading of the same name and max HP takes the card's CP whatever the current HP")
        XCTAssertEqual(n.feed(card(262, current: 19, max: 150, bars: false)).cp, 262, "another max HP is not the anchor's card")
        // over a whole log
        let stall = [card(4262, current: 19)] + [(262, 9), (4262, 19), (1262, 0), (4262, 9), (262, 19), (4262, 0), (62, 9), (4262, 19)].map { card($0.0, current: $0.1, bars: false) }
        XCTAssertTrue(StalledCardNormaliser.normalise(stall).dropFirst().allSatisfy { $0.cp == 4262 })
        let other = [card(4262, current: 19)] + [(262, 9), (4262, 19), (1262, 0), (4262, 9), (262, 19), (4262, 0), (62, 9), (4262, 19)].map { card($0.0, current: $0.1, max: 150, bars: false) }
        XCTAssertEqual(StalledCardNormaliser.normalise(other).map { $0.cp }, other.map { $0.cp }, "another max HP is left alone")
    }
}
