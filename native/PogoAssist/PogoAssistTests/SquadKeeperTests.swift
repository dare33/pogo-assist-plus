import XCTest
@testable import PogoAssist
@testable import PogoBox
import PogoReader

/// Where the squad screens keep a player's squads (CONCEPTS rule 27): one store per account in the phone's defaults, read back by a later screen, with the keeping
/// rules applied when the box is known and left alone when it is not.
@MainActor
final class SquadKeeperTests: XCTestCase {
    private let account = "Squad Keeper Test A", other = "Squad Keeper Test B", renamed = "Squad Keeper Test C"

    override func setUp() { clean() }
    override func tearDown() { clean() }
    private func clean() { for a in [account, other, renamed] { UserDefaults.standard.removeObject(forKey: SquadKeeper.key(a)) } }

    private func context(boxIds: [String]) throws -> HubContext {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let entries = boxIds.map { id -> BoxEntry in
            let row = ScanRow(index: 1, name: "Eevee", display: "Eevee", form: "", speciesId: "eevee", dex: nil, cp: 400, hp: 50, ivs: nil, ivsRead: nil, ivsGuess: nil,
                              level: nil, levelMax: nil, dust: nil, solveStatus: "exact", flags: [], frames: [])
            return BoxEntry(id: id, row: row, firstSeen: date, lastSeen: date)
        }
        return HubContext(advice: BoxAdvice(builds: [], gaps: [], duplicates: [], unresolved: []), entries: entries, gm: try GameMaster.bundled(), hub: try HubData.bundled(),
                          table: try TierTable.bundled(), today: "2026-10-26")
    }

    func testWhatOneScreenKeepsAnotherReadsBack() throws {
        let ctx = try context(boxIds: ["a", "b"])
        let first = SquadKeeper()
        first.attach(account: account, ctx: ctx)
        first.update { $0.gym.choose("a", at: 1); $0.setMode(.best, for: .gym) }

        let later = SquadKeeper()
        later.attach(account: account, ctx: ctx)
        XCTAssertEqual(later.store.gym.slots[1].pick, "a", "a pick survives leaving and re-entering a screen")
        XCTAssertEqual(later.store.mode(for: .gym), .best, "Available | Best is remembered per screen")

        let elsewhere = SquadKeeper()
        elsewhere.attach(account: other, ctx: ctx)
        XCTAssertNil(elsewhere.store.gym.slots[1].pick, "another account has its own squads")
        XCTAssertEqual(elsewhere.store.mode(for: .gym), .available, "and the default mode")
    }

    func testAPickWhoseCopyLeftTheBoxEmptiesItsSlot() throws {
        let keeper = SquadKeeper()
        keeper.attach(account: account, ctx: try context(boxIds: ["a", "b"]))
        keeper.update { $0.gym.choose("a", at: 0); $0.gym.choose("b", at: 1) }

        let afterRescan = SquadKeeper()
        afterRescan.attach(account: account, ctx: try context(boxIds: ["b"]))
        XCTAssertNil(afterRescan.store.gym.slots[0].pick, "the copy that left empties the slot, which refills with the suggestion")
        XCTAssertEqual(afterRescan.store.gym.slots[1].pick, "b", "the copy still in the box keeps its slot")
        XCTAssertNil(SquadKeeper.load(account).gym.slots[0].pick, "and the emptied slot is what is kept")
    }

    func testAnUnloadedBoxLeavesThePicksAlone() throws {
        let keeper = SquadKeeper()
        keeper.attach(account: account, ctx: try context(boxIds: ["a"]))
        keeper.update { $0.gym.choose("a", at: 0) }

        let early = SquadKeeper()
        early.attach(account: account, ctx: try context(boxIds: []))
        XCTAssertEqual(early.store.gym.slots[0].pick, "a", "no entries means the box is not loaded yet, not that every copy left")
    }

    func testARenamedAccountTakesItsSquadsWithIt() throws {
        let keeper = SquadKeeper()
        keeper.attach(account: account, ctx: try context(boxIds: ["a"]))
        keeper.update { $0.gym.choose("a", at: 2) }
        AppModel.moveAccountKeys(from: account, to: renamed)
        XCTAssertEqual(SquadKeeper.load(renamed).gym.slots[2].pick, "a")
        XCTAssertNil(UserDefaults.standard.data(forKey: SquadKeeper.key(account)), "the old name keeps nothing")
    }
}
