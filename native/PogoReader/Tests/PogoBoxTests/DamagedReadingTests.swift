import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// A damaged or fainted Pokémon is the same Pokémon: the box identifies it by its MAX HP, so a read
/// of 19 / 190 or 0 / 190 must give the row HP 190, pair as Same with the saved 190 / 190 entry, and
/// raise no question and no flag. (The reader fix is what makes such a card readable at all; these
/// pin the downstream half, including a current HP of 0.)
final class DamagedReadingTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    private func readings(current: Int, max: Int = 190, frames: Int = 4) -> [FrameReading] {
        (0..<frames).map { i in
            var r = FrameReading(frame: "f\(i)", time: 10 + Double(i) * 0.2)
            r.cp = 4262; r.cpText = "CP4262"; r.cpReads = [4262]
            r.name = "Rayquaza"; r.baseName = "Rayquaza"; r.form = ""; r.speciesIds = ["rayquaza"]; r.nameText = "Rayquaza"; r.nameConfidence = 100
            r.nameWeak = false; r.nameDistance = 0
            r.hp = HP(current: current, max: max); r.hpText = "\(current) / \(max) HP"
            r.ivs = IVs(atk: 13, def: 12, hp: 14); r.ivConfidence = 0.85; r.fills = [0.864, 0.795, 0.933]
            return r
        }
    }
    private func rows(_ current: Int) throws -> [ScanRow] { try sharedEngine.finish(readings: readings(current: current)).rows }

    func testADamagedOrFaintedReadIsOneRowWithTheMaxHpAndNoFlag() throws {
        for current in [190, 19, 1, 0] {
            let r = try rows(current)
            XCTAssertEqual(r.count, 1, "current \(current)")
            XCTAssertEqual(r.first?.hp, 190, "current \(current): the row carries the MAX")
            XCTAssertEqual(r.first?.cp, 4262)
            XCTAssertEqual(r.first?.flags, [], "current \(current)")
        }
    }

    func testADamagedOrFaintedReadOfASavedPokemonIsSameWithNoQuestion() throws {
        let full = try rows(190)
        let saved = [BoxEntry(id: "r", row: full[0], firstSeen: date, lastSeen: date)]
        for current in [19, 0] {
            for kind in [BoxStore.Kind.full, .partial] {
                let p = BoxMerge.plan(scanned: try rows(current), into: saved, kind: kind, scanDate: date.addingTimeInterval(86_400), gameMaster: gm)
                XCTAssertEqual(p.same, [BoxMerge.Pair(scanned: 0, savedId: "r", mega: false)], "current \(current) \(kind)")
                XCTAssertTrue(p.new.isEmpty && p.updated.isEmpty && p.gone.isEmpty && p.unsure.isEmpty, "current \(current) \(kind)")
            }
        }
    }

    /// The same Pokémon read healthy, then damaged, in one stretch of frames stays one row.
    func testHealthAndDamageOfOnePokemonInOneRunIsOneRow() throws {
        let both = readings(current: 190, frames: 3) + readings(current: 19, frames: 3).map { var r = $0; r.time! += 5; return r }
        XCTAssertEqual(try sharedEngine.finish(readings: both).rows.count, 1)
    }
}
