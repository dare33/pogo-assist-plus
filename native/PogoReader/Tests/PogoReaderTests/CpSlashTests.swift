import XCTest
@testable import PogoReader

/// Vision reads a leading 7 of the CP as "/": 'CP/68' for 768, 'CP/60' for 760 (device run 8). Every real string seen in the
/// device logs and the _out readings is here; the negatives are the shapes a slash must not turn into a digit.
final class CpSlashTests: XCTestCase {
    func testASlashRightAfterTheLabelIsASeven() {
        let real: [(String, Int)] = [("CP/68", 768), ("CP/60", 760), ("CP/72", 772), ("CP/17", 717), ("CP/19", 719), ("CP/64", 764), ("CP/66", 766),
                                     ("CP/10", 710), ("CP/21", 721), ("CP/23", 723), ("CP/29", 729), ("CP/39", 739), ("CP/42", 742)]
        for (text, cp) in real {
            XCTAssertEqual(parseCp(text), cp, text)
            XCTAssertTrue(cpReadHasValidShape(text), text)
        }
        XCTAssertEqual(parseCp("CP /68"), 768)
        XCTAssertEqual(parseCp("cP/68"), 768)
        XCTAssertEqual(parseCp("Cp / 68"), 768)
        XCTAssertEqual(parseCp("CP/683"), 7683)
        XCTAssertEqual(parseCp("CP/6"), 76)
        XCTAssertEqual(parseCp(" CP/68 "), 768)
    }

    func testOnlyWithTheLabelAndOnlyUpToFourDigits() {
        XCTAssertEqual(parseCp("CP/6832"), 6832, "five digits with a 7: not a 7, the slash is dropped as before")
        XCTAssertEqual(parseCp("/68"), 68, "no label: not a 7, the slash is dropped as before")
        XCTAssertEqual(parseCp("68"), 68)
        XCTAssertNil(parseCp("12/34"), "an HP-like read")
        XCTAssertNil(parseCp("CP 12/34"), "an HP-like read with a label before it")
        XCTAssertNil(parseCp("CP12/34"))
        XCTAssertNil(parseCp("CP1/86"), "a slash inside the figure is not a leading 7")
        XCTAssertNil(parseCp("CP1/01"))
        XCTAssertNil(parseCp("CP19/"), "a slash at the end")
        XCTAssertNil(parseCp("CP /"), "no digits")
        XCTAssertNil(parseCp("CP/"), "no digits")
        XCTAssertNil(parseCp("CP/68/"))
        XCTAssertNil(parseCp("CP1 66/"))
        XCTAssertEqual(parseCp("CPX/68"), 68, "another letter between the label and the slash")
        XCTAssertEqual(parseCp("CI/68"), 68, "the label must read CP")
        XCTAssertFalse(cpReadHasValidShape("CP/68 HP"), "letters after the figure")
    }

    func testReadsThatWereAlreadyFineAreUntouched() {
        for (text, cp) in [("CP1986", 1986), ("CP 768", 768), ("1986", 1986), ("CI 1986", 1986), ("c| 1601", 1601), ("CP! 685", 685), ("CP199 9", nil), ("5p86", 86)] as [(String, Int?)] {
            XCTAssertEqual(parseCp(text), cp, text)
        }
    }
}
