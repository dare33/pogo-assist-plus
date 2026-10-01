import XCTest
@testable import PogoReader

final class NamesTests: XCTestCase {
    func testDisplayNamesFollowWhatTheGamePrints() {
        XCTAssertEqual(candidate("Mega Mewtwo Y").speciesIds, ["mewtwo_mega_y"])
        XCTAssertEqual(candidate("Mega Mewtwo Y").form, "Mega Y")
        XCTAssertTrue(candidate("Zamazenta").speciesIds.contains("zamazenta_hero"))
        XCTAssertEqual(candidate("Alolan Raichu").form, "Alola")
        XCTAssertFalse(names.contains { $0.speciesIds.contains { $0.hasSuffix("_shadow") } })
    }

    func testMatchNameSurvivesThePencilIconAStrayTokenAndOneWrongLetter() {
        XCTAssertEqual(matchName("Meltan .", names)?.candidate.display, "Meltan")
        XCTAssertEqual(matchName("be Meltan", names)?.candidate.display, "Meltan")
        XCTAssertEqual(matchName("Xurkitrea", names)?.candidate.display, "Xurkitree")
        XCTAssertEqual(matchName("Mega Mewtwo Y", names)?.candidate.display, "Mega Mewtwo Y")
        XCTAssertNil(matchName("ime COIlouUurrul os", names))
        XCTAssertNil(matchName("", names))
    }

    func testBothNidoranShareOneDisplayNameAndExportUnderPokeGenieNames() {
        XCTAssertEqual(Set(candidate("Nidoran").speciesIds), ["nidoran_female", "nidoran_male"])
        XCTAssertEqual(nameAndForm(table.byId["nidoran_female"]!).name, "Nidoran♀")
        XCTAssertEqual(nameAndForm(table.byId["nidoran_male"]!).name, "Nidoran♂")
    }

    /// Fault 1: Nidoran with its symbol dropped or misread, and Nidorino / Nidorina still told apart.
    func testMatchNameReadsNidoranWithItsSymbolDroppedOrMisread() {
        for text in ["Nidoran", "Nidorano", "Nidoran 9", "Nidoran .", "Nidoran♀", "Nidoran♂", "Nidoran ♀"] {
            let m = matchName(text, names)
            XCTAssertEqual(m?.candidate.display, "Nidoran", text)
            XCTAssertEqual(m?.distance, 0, text)
        }
        XCTAssertEqual(matchName("Nidorino", names)?.candidate.display, "Nidorino")
        XCTAssertEqual(matchName("Nidorina", names)?.candidate.display, "Nidorina")
        XCTAssertEqual(matchName("Nidorano", names)?.attached, true)
        XCTAssertEqual(matchName("Nidoran", names)?.attached, false)
    }

    func testNidoranSexIsTakenOnlyFromTheRealSymbol() {
        XCTAssertEqual(nidoranSex(inRawText: "Nidoran♀"), "nidoran_female")
        XCTAssertEqual(nidoranSex(inRawText: "Nidoran ♂"), "nidoran_male")
        XCTAssertNil(nidoranSex(inRawText: "Nidoran 9"))
        XCTAssertNil(nidoranSex(inRawText: "Nidorano"))
    }

    func testMatchNameSaysWhetherTheWholeTextMatched() {
        XCTAssertEqual(matchName("Rattata", names)?.whole, true)
        XCTAssertEqual(matchName("Rattata .", names)?.whole, true)
        XCTAssertEqual(matchName("Rattata a", names)?.whole, true)
        let lead = matchName("x Rattata", names)!
        XCTAssertFalse(lead.distance == 0 && lead.whole)
        let dropped = matchName("Aloan Rattata", names)!
        XCTAssertFalse(dropped.distance == 0 && dropped.whole)
    }

    func testDistanceAndNormalise() {
        XCTAssertEqual(distance("kitten", "sitting"), 3)
        XCTAssertEqual(normalise("Flabébé!"), "flabebe")
        XCTAssertEqual(normalise("  Mr.  Mime "), "mr mime")
    }
}
