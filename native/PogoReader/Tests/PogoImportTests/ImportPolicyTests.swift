import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PogoImport

/// The decisions the app glue makes, as plain values: they can fail here, which the SwiftUI code around them cannot.
final class ImportPolicyTests: XCTestCase {
    func testTheSheetOpensByItselfOnlyWhenNothingElseHasTheScreenAndNoScanIsWaiting() {
        XCTAssertTrue(ImportPolicy.shouldAutoOpenSheet(unseenBatches: 1, sheetOpen: false, canOpenReview: true, scanPendingPickup: false))
        XCTAssertFalse(ImportPolicy.shouldAutoOpenSheet(unseenBatches: 0, sheetOpen: false, canOpenReview: true, scanPendingPickup: false), "nothing new to show")
        XCTAssertFalse(ImportPolicy.shouldAutoOpenSheet(unseenBatches: 2, sheetOpen: true, canOpenReview: true, scanPendingPickup: false), "a sheet is up")
        XCTAssertFalse(ImportPolicy.shouldAutoOpenSheet(unseenBatches: 2, sheetOpen: false, canOpenReview: false, scanPendingPickup: false), "a scan is being reviewed, or waits")
        XCTAssertFalse(ImportPolicy.shouldAutoOpenSheet(unseenBatches: 2, sheetOpen: false, canOpenReview: true, scanPendingPickup: true), "a finished scan is about to be picked up: it comes first")
    }

    func testReadingStopsInTheBackgroundAndOnlyARealReturnStartsItAgain() {
        var gate = ReadingGate()
        XCTAssertTrue(gate.mayRead)
        XCTAssertFalse(gate.scenePhaseChanged(background: false), "active when it already was: nothing to restart")
        gate.scenePhaseChanged(background: true)
        XCTAssertFalse(gate.mayRead)
        // something else looking at the queue while backgrounded (a review ending) has no way to lift it: only the scene phase does
        XCTAssertFalse(gate.mayRead)
        XCTAssertTrue(gate.scenePhaseChanged(background: false), "back in front: start again")
        XCTAssertTrue(gate.mayRead)
        gate.timeExpired()
        XCTAssertFalse(gate.mayRead, "the system took the time away mid-read")
        XCTAssertTrue(gate.scenePhaseChanged(background: false))
    }

    // MARK: a pick that is cancelled

    private func png(_ seed: Int) throws -> Data {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 400, height: 800, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(CGColor(red: Double(seed % 5) / 5, green: 0.4, blue: 0.6, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 800))
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try XCTUnwrap(ctx.makeImage()), nil); XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    private func newQueue() -> ImportQueue {
        ImportQueue(root: FileManager.default.temporaryDirectory.appendingPathComponent("pick-\(UUID().uuidString)/screenshot-imports"))
    }

    func testAPickThatIsCancelledAfterTheLastLoadCommitsNothingAndLeavesNoFolder() async throws {
        let queue = newQueue(); defer { try? FileManager.default.removeItem(at: queue.root.deletingLastPathComponent()) }
        let pics = try (0..<3).map(png)
        var cancelled = false
        let builder = try queue.beginBatch(origin: .photoPicker, account: "Main")
        let result = await PickStager.stage(count: 3, builder: builder,
                                            load: { i in if i == 2 { cancelled = true }; return (pics[i], nil) },   // the person cancels while the last picture loads
                                            isCancelled: { cancelled })
        guard case .cancelled = result else { return XCTFail("\(result)") }
        XCTAssertEqual(try queue.list().manifests.count, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: queue.root.path), [], "no .staging folder either")
    }

    func testAPickThatIsCancelledEarlierStopsLoading() async throws {
        let queue = newQueue(); defer { try? FileManager.default.removeItem(at: queue.root.deletingLastPathComponent()) }
        let pics = try (0..<4).map(png)
        var loaded = 0, cancelled = false
        let result = await PickStager.stage(count: 4, builder: try queue.beginBatch(origin: .photoPicker, account: nil),
                                            load: { i in loaded += 1; if i == 1 { cancelled = true }; return (pics[i], nil) }, isCancelled: { cancelled })
        guard case .cancelled = result else { return XCTFail() }
        XCTAssertEqual(loaded, 2)
        XCTAssertEqual(try queue.list().manifests.count, 0)
    }

    func testAPickThatIsNotCancelledCommitsWhatCouldBeUsed() async throws {
        let queue = newQueue(); defer { try? FileManager.default.removeItem(at: queue.root.deletingLastPathComponent()) }
        let pics = try (0..<3).map(png)
        let result = await PickStager.stage(count: 4, builder: try queue.beginBatch(origin: .photoPicker, account: "Main"),
                                            load: { i in i == 3 ? nil : (i == 2 ? (Data("junk".utf8), nil) : (pics[i], "asset-\(i)")) }, isCancelled: { false })
        guard case .committed(let m, let unusable) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(m.items.count, 2); XCTAssertEqual(unusable, 2)
        XCTAssertEqual(m.items.compactMap(\.assetId), ["asset-0", "asset-1"])
        XCTAssertEqual(try queue.list().manifests.count, 1)
    }
}
