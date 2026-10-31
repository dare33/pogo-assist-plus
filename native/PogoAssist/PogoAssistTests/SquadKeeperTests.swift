import XCTest
@testable import PogoAssist
@testable import PogoBox
import PogoReader

/// Where the squad screens keep a player's squads (CONCEPTS rule 27): one store per account in the phone's defaults, read back by a later screen, with the keeping
/// rules applied when the box is loaded and left alone when it is not.
@MainActor
final class SquadKeeperTests: XCTestCase {
    private let account = "Squad Keeper Test A", other = "Squad Keeper Test B", renamed = "Squad Keeper Test C"

    override func setUp() { clean() }
    override func tearDown() { clean() }
    private func clean() { for a in [account, other, renamed] { UserDefaults.standard.removeObject(forKey: SquadKeeper.key(a)) } }

    private func row(_ from: String, _ to: String, title: String = "Palkia") -> HubData.RotationRow {
        HubData.RotationRow(from: from, to: to, kind: .fiveStar, title: title, bosses: [], note: "", source: "", tba: nil)
    }

    /// Attaches as the screens do: `ids` are the loaded box's copies, nil a box that is not loaded yet.
    private func attach(_ k: SquadKeeper, _ account: String, ids: [String]?, today: String = "2026-10-26", rotation: [HubData.RotationRow] = []) {
        k.attach(account: account, today: today, rotation: rotation, boxIds: ids.map(Set.init))
    }

    func testWhatOneScreenKeepsAnotherReadsBack() {
        let first = SquadKeeper()
        attach(first, account, ids: ["a", "b"])
        first.update { $0.gym.choose("b", at: 1); $0.setMode(.best, for: .gym) }

        let later = SquadKeeper()
        attach(later, account, ids: ["a", "b"])
        XCTAssertEqual(later.store.gym.slots[1].pick, "b", "a distinct pick survives leaving and re-entering a screen")
        XCTAssertEqual(later.store.mode(for: .gym), .best, "Available | Best is remembered per screen")

        let elsewhere = SquadKeeper()
        attach(elsewhere, other, ids: ["a", "b"])
        XCTAssertNil(elsewhere.store.gym.slots[1].pick, "another account has its own squads")
        XCTAssertEqual(elsewhere.store.mode(for: .gym), .available, "and the default mode")
    }

    func testEveryScreensPicksAreKeptAsChosen() {
        let r = row("2026-10-20", "2026-10-27")
        let k = SquadKeeper()
        attach(k, account, ids: ["a", "b", "c"], rotation: [r])
        k.update { s in
            var raid = s.eventSquad(r, screen: .raids); raid.choose("c", at: 2); s.saveEventSquad(raid, row: r, screen: .raids)
            var max = s.eventSquad(r, screen: .max); max.choose("b", at: 0); max.isSet = true; s.saveEventSquad(max, row: r, screen: .max)
            var rocket = s.rocketSquad(leader: "Giovanni"); rocket.choose("b", at: 2); s.rocket["Giovanni"] = rocket
            var pvp = s.pvpSquad(league: "ul"); pvp.choose("a", at: 1); pvp.changeRole(at: 1, to: "All") { _ in true }; s.pvp["ul"] = pvp
        }
        let later = SquadKeeper()
        attach(later, account, ids: ["a", "b", "c"], rotation: [r])
        XCTAssertEqual(later.store.eventSquad(r, screen: .raids).slots[2].pick, "c")
        XCTAssertEqual(later.store.eventSquad(r, screen: .max).slots[0].pick, "b")
        XCTAssertTrue(later.store.eventSquad(r, screen: .max).isSet)
        XCTAssertEqual(later.store.rocketSquad(leader: "Giovanni").slots[2].pick, "b")
        XCTAssertEqual(later.store.pvpSquad(league: "ul").slots[1].pick, "a")
        XCTAssertEqual(later.store.pvpSquad(league: "ul").slots[1].role, "All")
    }

    func testAPickWhoseCopyLeftTheBoxEmptiesItsSlot() {
        let keeper = SquadKeeper()
        attach(keeper, account, ids: ["a", "b"])
        keeper.update { $0.gym.choose("a", at: 0); $0.gym.choose("b", at: 1) }

        let afterRescan = SquadKeeper()
        attach(afterRescan, account, ids: ["b"])
        XCTAssertNil(afterRescan.store.gym.slots[0].pick, "the copy that left empties the slot, which refills with the suggestion")
        XCTAssertEqual(afterRescan.store.gym.slots[1].pick, "b", "the copy still in the box keeps its slot")
        XCTAssertNil(SquadKeeper.load(account).gym.slots[0].pick, "and the emptied slot is what is kept")
    }

    func testABoxNotLoadedYetLeavesThePicksAloneButALoadedEmptyBoxDropsThem() {
        let keeper = SquadKeeper()
        attach(keeper, account, ids: ["a"])
        keeper.update { $0.gym.choose("a", at: 0) }

        let early = SquadKeeper()
        attach(early, account, ids: nil)
        XCTAssertEqual(early.store.gym.slots[0].pick, "a", "a box that is not loaded yet says nothing about the copies")
        XCTAssertEqual(SquadKeeper.load(account).gym.slots[0].pick, "a", "and nothing is written")

        let emptied = SquadKeeper()
        attach(emptied, account, ids: [])
        XCTAssertNil(emptied.store.gym.slots[0].pick, "a loaded box whose last copy was deleted empties the slot")
        XCTAssertNil(SquadKeeper.load(account).gym.slots[0].pick)
    }

    func testAnEndedEventSquadIsDroppedAndOneWhoseEndMovedIsKept() {
        let moved = row("2026-10-20", "2026-10-25", title: "Moved"), ended = row("2026-10-18", "2026-10-25", title: "Ended"), later = row("2026-10-28", "2026-11-04", title: "Later")
        let k = SquadKeeper()
        attach(k, account, ids: ["a"], today: "2026-10-24", rotation: [moved, ended, later])
        k.update { s in
            for r in [moved, ended, later] {
                var sq = s.eventSquad(r, screen: .raids); sq.choose("a", at: 0); s.saveEventSquad(sq, row: r, screen: .raids)
                var mx = s.eventSquad(r, screen: .max); mx.isSet = true; s.saveEventSquad(mx, row: r, screen: .max)
            }
        }
        // Two days on: "Ended" is gone from the rotation (its stored last day, the 25th, has passed); "Moved" was extended to the 30th in the rotation.
        let extended = row("2026-10-20", "2026-10-30", title: "Moved")
        let reopened = SquadKeeper()
        attach(reopened, account, ids: ["a"], today: "2026-10-27", rotation: [extended, later])
        XCTAssertNil(reopened.store.raids[SquadStore.eventKey(ended)], "a raid squad whose event has ended is dropped")
        XCTAssertNil(reopened.store.max[SquadStore.eventKey(ended)], "and a Max squad")
        XCTAssertEqual(reopened.store.raids[SquadStore.eventKey(extended)]?.squad.slots[0].pick, "a", "an event whose last day moved is judged by the new day")
        XCTAssertEqual(reopened.store.raids[SquadStore.eventKey(extended)]?.endsOn, "2026-10-30")
        XCTAssertTrue(reopened.store.max[SquadStore.eventKey(later)]?.squad.isSet == true, "an event still to come is kept")
    }

    func testARenamedAccountTakesItsSquadsWithIt() {
        let keeper = SquadKeeper()
        attach(keeper, account, ids: ["a"])
        keeper.update { $0.gym.choose("a", at: 2) }
        AppModel.moveAccountKeys(from: account, to: renamed)
        XCTAssertEqual(SquadKeeper.load(renamed).gym.slots[2].pick, "a")
        XCTAssertNil(UserDefaults.standard.data(forKey: SquadKeeper.key(account)), "the old name keeps nothing")
    }
}
