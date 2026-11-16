import XCTest
@testable import PogoBox

/// Pass 2-6, rule 35: the difficulty meter and the month of the "Not now" chip.
final class HubSquadsChipsTests: XCTestCase {
    func testTheDifficultyIsTheWordTheObtainTextOpensWith() {
        XCTAssertEqual(HubSquads.obtainDifficulty("Easy. Wild"), .easy)
        XCTAssertEqual(HubSquads.obtainDifficulty("Medium. T5 raids"), .medium)
        XCTAssertEqual(HubSquads.obtainDifficulty("Hard. Mega raids"), .hard)
        XCTAssertEqual(HubSquads.obtainDifficulty("Easy/Medium. Wild"), .medium, "a range reads as its hardest word")
        XCTAssertEqual(HubSquads.obtainDifficulty("Medium to Hard. Raids"), .hard)
        XCTAssertNil(HubSquads.obtainDifficulty("Raids from 9 Nov"))
        XCTAssertNil(HubSquads.obtainDifficulty("T5 raids. Easy once you have the Mega"), "only the part before the first full stop")
        XCTAssertNil(HubSquads.obtainDifficulty(""))
        XCTAssertEqual(HubSquads.ObtainDifficulty.easy.meter, "▮▯▯")
        XCTAssertEqual(HubSquads.ObtainDifficulty.medium.meter, "▮▮▯")
        XCTAssertEqual(HubSquads.ObtainDifficulty.hard.meter, "▮▮▮")
        XCTAssertEqual(HubSquads.ObtainDifficulty.hard.word, "Hard")
    }

    func testTheMonthIsShownWithTheDayOnlyWithinAMonth() {
        XCTAssertEqual(HubSquads.notNowWhen(rotationLine: "Raids from 9 Nov", today: "2026-11-07"), "9 Nov")
        XCTAssertEqual(HubSquads.notNowWhen(rotationLine: "Max Monday 2 Dec", today: "2026-11-07"), "2 Dec", "within a month")
        XCTAssertEqual(HubSquads.notNowWhen(rotationLine: "Raids from 20 Dec", today: "2026-11-07"), "Dec", "further off: the month")
        XCTAssertEqual(HubSquads.notNowWhen(rotationLine: "Raids from 3 Jan", today: "2026-12-20"), "3 Jan", "across the new year")
        XCTAssertEqual(HubSquads.notNowWhen(rotationLine: "Raids from 3 Mar", today: "2026-12-20"), "Mar")
        XCTAssertNil(HubSquads.notNowWhen(rotationLine: "not on the schedule", today: "2026-11-07"))
        XCTAssertNil(HubSquads.notNowWhen(rotationLine: nil, today: "2026-11-07"))
    }

    func testAMeterOnlyForAnObtainTextOfANotOwnedPokemon() {
        var row = HubSquads.BestRow(key: "x", name: "X", speciesId: "x", tier: "B", roles: ["Heavy hitter"], types: [], availability: "Medium. T5 raids")
        row.status = .init(kind: .canGetNow, needsUpgrade: false, detail: "Medium. T5 raids")
        XCTAssertEqual(row.difficulty, .medium)
        row.rotationLine = "Raid boss now"; row.availability = "Raid boss now"
        XCTAssertNil(row.difficulty, "a boss on the schedule has no meter")
        row.rotationLine = nil; row.availability = "Easy. Wild"; row.status = .init(kind: .notAvailableNow, needsUpgrade: false, detail: "not on the schedule")
        XCTAssertNil(row.difficulty, "not a Get now")
    }
}
