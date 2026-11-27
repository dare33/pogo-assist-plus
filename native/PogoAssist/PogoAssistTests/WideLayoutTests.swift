import XCTest
import SwiftUI
@testable import PogoAssist

final class WideLayoutTests: XCTestCase {
    func testThresholdSeparatesTheTargetWindows() {
        XCTAssertFalse(WideLayout.isWide(382))   // Duo folded
        XCTAssertFalse(WideLayout.isWide(440))   // iPhone 17
        XCTAssertFalse(WideLayout.isWide(669))   // Duo open, turned tall
        XCTAssertFalse(WideLayout.isWide(799.5))
        XCTAssertTrue(WideLayout.isWide(800))
        XCTAssertTrue(WideLayout.isWide(834))    // iPad 11-inch portrait
        XCTAssertTrue(WideLayout.isWide(867))    // Duo open, wide
    }

    func testColumnCapIsWideOnlyWhenWide() {
        XCTAssertEqual(WideLayout.column(wide: false), 640)
        XCTAssertEqual(WideLayout.column(wide: true), 1040)
        XCTAssertGreaterThan(WideLayout.columnMax, WideLayout.minWidth)
    }

    func testAccessibilitySizesNeverLayOutWide() {
        XCTAssertTrue(WideLayout.lays(wide: true, typeSize: .large))
        XCTAssertTrue(WideLayout.lays(wide: true, typeSize: .xxxLarge))
        XCTAssertFalse(WideLayout.lays(wide: true, typeSize: .accessibility1))
        XCTAssertFalse(WideLayout.lays(wide: true, typeSize: .accessibility5))
        XCTAssertFalse(WideLayout.lays(wide: false, typeSize: .large))
        // so the column stays 640 at those sizes however wide the window is
        XCTAssertEqual(WideLayout.column(wide: WideLayout.lays(wide: true, typeSize: .accessibility1)), 640)
    }

    func testHubTilesPerRow() {
        XCTAssertEqual(WideLayout.hubTilesPerRow(wide: false, typeSize: .large), 2)
        XCTAssertEqual(WideLayout.hubTilesPerRow(wide: true, typeSize: .large), 3)
        XCTAssertEqual(WideLayout.hubTilesPerRow(wide: true, typeSize: .xxxLarge), 3)
        XCTAssertEqual(WideLayout.hubTilesPerRow(wide: true, typeSize: .accessibility1), 1)
        XCTAssertEqual(WideLayout.hubTilesPerRow(wide: false, typeSize: .accessibility1), 1)
        XCTAssertEqual(WideLayout.hubTilesPerRow(wide: false, typeSize: .xxxLarge), 2)
    }

    func testSlotsPerRow() {
        XCTAssertEqual(WideLayout.slotsPerRow(wide: false, typeSize: .large, count: 6), 3)
        XCTAssertEqual(WideLayout.slotsPerRow(wide: true, typeSize: .large, count: 6), 6)
        XCTAssertEqual(WideLayout.slotsPerRow(wide: true, typeSize: .accessibility3, count: 6), 1)
        XCTAssertEqual(WideLayout.slotsPerRow(wide: false, typeSize: .accessibility3, count: 6), 1)
        // a squad of three (Max, Rocket, PvP) keeps three to a row, so its cards fill the row and no column is left blank
        XCTAssertEqual(WideLayout.slotsPerRow(wide: true, typeSize: .large, count: 3), 3)
        XCTAssertEqual(WideLayout.slotsPerRow(wide: false, typeSize: .large, count: 3), 3)
        XCTAssertEqual(WideLayout.slotsPerRow(wide: true, typeSize: .large, count: 4), 6)
        XCTAssertEqual(WideLayout.slotsPerRow(wide: true, typeSize: .accessibility3, count: 3), 1)
    }

    func testCollectionColumns() {
        XCTAssertEqual(WideLayout.collectionColumns(wide: false, typeSize: .large), 1)
        XCTAssertEqual(WideLayout.collectionColumns(wide: true, typeSize: .large), 2)
        XCTAssertEqual(WideLayout.collectionColumns(wide: true, typeSize: .accessibility2), 1)
        XCTAssertEqual(WideLayout.collectionColumns(wide: false, typeSize: .accessibility2), 1)
    }

    func testRowsKeepOrderAndAllowAShortLastRow() {
        XCTAssertEqual(WideLayout.rows([1, 2, 3, 4, 5], per: 2), [[1, 2], [3, 4], [5]])
        XCTAssertEqual(WideLayout.rows([1, 2, 3, 4, 5, 6], per: 3), [[1, 2, 3], [4, 5, 6]])
        XCTAssertEqual(WideLayout.rows([Int](), per: 2), [])
        XCTAssertEqual(WideLayout.rows([1, 2], per: 0), [[1, 2]])
    }
}
