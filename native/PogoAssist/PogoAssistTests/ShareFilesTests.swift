import XCTest
@testable import PogoAssist
@testable import PogoBox
import PogoReader

/// The files the app shares count their times from the scan's first frame. The shifting itself is tested in the package (`ShareTimesTests`); these tests check it on the
/// app's own file shapes (`BroadcastState`, `DeferredResult`) and the temporary files `ShareFiles` writes.
final class ShareFilesTests: XCTestCase {
    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("share-files-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: d) }
        return d
    }
    private func liveRow(_ i: Int, _ first: Double?, _ last: Double?) throws -> LiveRow {
        var o: [String: Any] = ["index": i, "name": "Fidough", "cp": 768, "hp": 80, "frames": 4, "flags": ["check"], "firstFrame": "r\(i)", "lastFrame": "r\(i + 3)"]
        if let first { o["firstTime"] = first }; if let last { o["lastTime"] = last }
        return try JSONDecoder().decode(LiveRow.self, from: JSONSerialization.data(withJSONObject: o))
    }
    private let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }()
    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    func testTheStateFileAndTheSavedCropResultKeepEveryFieldButTheFrameTimes() throws {
        var state = BroadcastState()
        state.rows = [try liveRow(1, 119_757.5, 119_760.1), try liveRow(2, nil, 119_800)]
        state.framesRead = 640; state.commandPeriod = 1.2; state.pauseLimitSeconds = 90; state.scanId = 1_795_000_000
        state.started = Date(timeIntervalSince1970: 1_795_000_000); state.updated = Date(timeIntervalSince1970: 1_795_000_420); state.pausedAt = Date(timeIntervalSince1970: 1_795_000_100)
        state.cpCoveredSince = Date(timeIntervalSince1970: 1_795_000_200); state.finished = true
        let deferred = DeferredResult(rows: [try liveRow(1, 119_750.25, 119_751)], frames: 12, seconds: 3.5, peakFootprintMB: 20.25)
        let log = "{\"k\":\"t\",\"t\":119760}\n{\"k\":\"t\",\"t\":119761.2}\n"

        let r = ShareTimes.diagnostics(state: try encoder.encode(state), deferred: try JSONEncoder().encode(deferred), replayLog: Data(log.utf8))
        XCTAssertEqual(r.unreadable, [])
        XCTAssertEqual(try XCTUnwrap(r.shifts[.state]), 119_757.5, accuracy: 1e-6); XCTAssertEqual(try XCTUnwrap(r.shifts[.deferred]), 119_750.25, accuracy: 1e-6)
        let s = try decoder.decode(BroadcastState.self, from: XCTUnwrap(r.state))
        var expected = state
        expected.rows = [try liveRow(1, 0, 2.6), try liveRow(2, nil, 42.5)]
        XCTAssertEqual(s.rows.map(\.firstTime), expected.rows.map(\.firstTime))
        XCTAssertEqual(s.rows.compactMap(\.lastTime).map { ($0 * 100).rounded() }, expected.rows.compactMap(\.lastTime).map { ($0 * 100).rounded() })
        var sameRest = s; sameRest.rows = state.rows
        XCTAssertEqual(sameRest, state, "every field other than the rows' times is as it was")
        let d = try JSONDecoder().decode(DeferredResult.self, from: XCTUnwrap(r.deferred))
        XCTAssertEqual(d.rows.first?.firstTime ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(d.rows.first?.lastTime ?? -1, 0.75, accuracy: 1e-9)
        XCTAssertEqual(d.seconds, 3.5); XCTAssertEqual(d.frames, 12); XCTAssertEqual(d.peakFootprintMB, 20.25)
    }

    /// A scan saved through the store from the bundled boot-timed sample log; returns the store, the scan's id and its two files.
    private func savedSample() throws -> (store: BoxStore, id: String, result: URL, log: URL, replay: URL) {
        let replay = try XCTUnwrap(Bundle.main.url(forResource: "sample-scan", withExtension: "replay.jsonl"), "the bundled sample log")
        let store = BoxStore(root: tempDir())
        let outcome = try ScanPipeline.process(replay: replay, engine: CoreEngine())
        let summary = try store.save(outcome.scan, account: "T", source: "broadcast", replayLog: Data(contentsOf: replay), refineChanges: [])
        let files = try store.files(account: "T", id: summary.id)
        return (store, summary.id, files.result, try XCTUnwrap(files.replay), replay)
    }
    private func maxLogTime(_ text: String) -> Double? {
        text.split(separator: "\n").compactMap { line in (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["t"] as? Double }.max()
    }
    private func minLogTime(_ text: String) -> Double? {
        text.split(separator: "\n").compactMap { line in (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["t"] as? Double }.min()
    }

    func testASavedScanIsWrittenToTheTemporaryFolderShiftedAndAnUnreadableResultIsLeftOut() throws {
        let s = try savedSample(), tmp = tempDir()
        let ok = ShareFiles.savedScan(store: s.store, account: "T", id: s.id, into: tmp)
        XCTAssertNil(ok.message)
        XCTAssertEqual(ok.urls.map(\.lastPathComponent), ["\(s.id).result.json", "\(s.id).replay.jsonl"])
        let shared = try decoder.decode(BoxStore.StoredScan.self, from: Data(contentsOf: ok.urls[0]))
        XCTAssertLessThan(try XCTUnwrap(shared.rows.flatMap(\.frames).compactMap(\.time).max()), 400)
        XCTAssertLessThan(try XCTUnwrap(maxLogTime(String(contentsOf: ok.urls[1], encoding: .utf8))), 400)
        XCTAssertGreaterThan(try XCTUnwrap(try decoder.decode(BoxStore.StoredScan.self, from: Data(contentsOf: s.result)).rows.flatMap(\.frames).compactMap(\.time).max()), 400, "the stored file is untouched")

        // a damaged result file: not shared as it is, the log still is, and the person is told
        try Data("{ damaged".utf8).write(to: s.result)
        let bad = ShareFiles.savedScan(store: s.store, account: "T", id: s.id, into: tmp)
        XCTAssertEqual(bad.urls.map(\.lastPathComponent), ["\(s.id).replay.jsonl"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("\(s.id).result.json").path), "this scan's earlier copy is gone")
        XCTAssertEqual(bad.message, "The scan's results could not be read, so they were left out.")
        let missing = ShareFiles.savedScan(store: s.store, account: "T", id: "no-such-scan", into: tmp)
        XCTAssertTrue(missing.urls.isEmpty); XCTAssertEqual(missing.message, ShareFiles.scanNotFound)
    }

    func testADamagedReplayLineIsLeftOutAndSaidAndNothingIsSharedWhenTheFolderCannotBeWritten() throws {
        let s = try savedSample(), tmp = tempDir()
        let log = try Data(contentsOf: s.log)
        try (log + Data("{\"k\":\"t\",\"t\":119".utf8)).write(to: s.log)
        let r = ShareFiles.savedScan(store: s.store, account: "T", id: s.id, into: tmp)
        XCTAssertEqual(r.urls.count, 2)
        XCTAssertEqual(r.message, "1 damaged line of the reading log was left out.")
        XCTAssertEqual(try String(contentsOf: r.urls[1], encoding: .utf8).split(separator: "\n").count, String(decoding: log, as: UTF8.self).split(separator: "\n").count)
        // the folder is a file: nothing can be written, so nothing is shared and each file is named as not prepared (never shared as it was)
        let notAFolder = tmp.appendingPathComponent("not-a-folder"); try Data("x".utf8).write(to: notAFolder)
        let blocked = ShareFiles.savedScan(store: s.store, account: "T", id: s.id, into: notAFolder)
        XCTAssertTrue(blocked.urls.isEmpty)
        XCTAssertEqual(blocked.notes.filter { $0.contains("could not be prepared for sharing") }.count, 2)
        let review = ShareFiles.reviewLog(s.replay, into: notAFolder)
        XCTAssertTrue(review.urls.isEmpty); XCTAssertEqual(review.message, "The scan's reading log could not be prepared for sharing, so it was left out.")
    }

    func testTheReviewsOwnLogIsSharedFromZeroWithNoBootBasedNumber() throws {
        let replay = try XCTUnwrap(Bundle.main.url(forResource: "sample-scan", withExtension: "replay.jsonl"))
        let tmp = tempDir()
        let stored = try String(contentsOf: replay, encoding: .utf8)
        XCTAssertGreaterThan(try XCTUnwrap(minLogTime(stored)), 400, "premise: boot-based")
        let review = ShareFiles.reviewLog(replay, into: tmp)
        XCTAssertEqual(review.urls.map(\.lastPathComponent), ["scan-in-review.replay.jsonl"]); XCTAssertNil(review.message)
        let text = try String(contentsOf: review.urls[0], encoding: .utf8)
        XCTAssertEqual(try XCTUnwrap(minLogTime(text)), 0, accuracy: 1e-9)
        XCTAssertLessThan(try XCTUnwrap(maxLogTime(text)), 400)
        let again = ShareFiles.reviewLog(review.urls[0], into: tmp)
        XCTAssertEqual(try String(contentsOf: again.urls[0], encoding: .utf8), text, "shifting it again changes nothing")
        XCTAssertNotNil(ShareFiles.reviewLog(tmp.appendingPathComponent("missing.jsonl"), into: tmp).message)
    }

    /// The Diagnostics files live in the app group (the app's Documents folder in the simulator): the test moves what is there aside and puts it back.
    func testTheDiagnosticsShareWritesShiftedCopiesInAFreshFolderAndSaysWhatWasLeftOut() throws {
        let urls = [SharedStore.stateURL, SharedStore.deferredURL, SharedStore.replayURL].compactMap { $0 }
        guard urls.count == 3 else { throw XCTSkip("no app group folder here") }
        let aside = tempDir()
        for u in urls where FileManager.default.fileExists(atPath: u.path) { try FileManager.default.moveItem(at: u, to: aside.appendingPathComponent(u.lastPathComponent)) }
        addTeardownBlock {
            for u in urls { try? FileManager.default.removeItem(at: u) }
            for u in urls where FileManager.default.fileExists(atPath: aside.appendingPathComponent(u.lastPathComponent).path) { try? FileManager.default.moveItem(at: aside.appendingPathComponent(u.lastPathComponent), to: u) }
        }
        let tmp = tempDir()
        let folder = tmp.appendingPathComponent("diagnostics-share", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: folder.appendingPathComponent("stale.txt"))

        // nothing there: nothing shared, nothing said, and the folder was reset
        let none = ShareFiles.diagnostics(into: tmp)
        XCTAssertTrue(none.urls.isEmpty); XCTAssertNil(none.message)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("stale.txt").path))

        // an old state (boot-timed) beside a current replay log, with no saved-crop result: each file counts from its own first time
        var state = BroadcastState(); state.rows = [try liveRow(1, 119_757.5, 119_760.1)]
        try encoder.encode(state).write(to: urls[0])
        try Data("{\"k\":\"t\",\"t\":0.5}\n{\"k\":\"t\",\"t\":2}\n{\"k\":\"t\",\"t\":9".utf8).write(to: urls[2])
        let r = ShareFiles.diagnostics(into: tmp)
        XCTAssertEqual(r.urls.map(\.lastPathComponent), ["state.json", "replay.jsonl"], "no deferred.json when there is none")
        XCTAssertEqual(r.urls.map { $0.deletingLastPathComponent().lastPathComponent }, ["diagnostics-share", "diagnostics-share"])
        let shared = try decoder.decode(BroadcastState.self, from: Data(contentsOf: r.urls[0]))
        XCTAssertEqual(try XCTUnwrap(shared.rows.first?.firstTime), 0, accuracy: 1e-9)
        let sharedLog = try String(contentsOf: r.urls[1], encoding: .utf8)
        XCTAssertEqual(try XCTUnwrap(minLogTime(sharedLog)), 0, accuracy: 1e-9); XCTAssertEqual(try XCTUnwrap(maxLogTime(sharedLog)), 1.5, accuracy: 1e-9, "the current log counts from its own first line, not the old state's clock")
        XCTAssertEqual(r.message, "1 damaged line of the reading log was left out.")
        XCTAssertGreaterThan(try XCTUnwrap(SharedStore.read()?.rows.first?.firstTime), 400, "the stored state file is untouched")

        // a state file that cannot be read is left out and named
        try Data("{ damaged".utf8).write(to: urls[0])
        let bad = ShareFiles.diagnostics(into: tmp)
        XCTAssertEqual(bad.urls.map(\.lastPathComponent), ["replay.jsonl"])
        XCTAssertTrue(try XCTUnwrap(bad.message).contains("The state file could not be read, so it was left out."))
    }

    @MainActor func testWithNoAccountTheShareSaysTheScanCannotBeFoundAndAReviewWithNoLogSaysSo() async throws {
        let model = AppModel(screenSize: CGSize(width: 440, height: 956), isPad: false)
        let before = model.account
        defer { model.account = before }
        model.account = nil
        let summary = BoxStore.Summary(id: "x", scanDate: Date(), savedAt: Date(), source: "broadcast", kind: .full, rows: 0, flagged: 0, unmatched: 0, lastReread: nil, reportSentAt: nil, sourceSignature: nil, pass: nil)
        let r = await model.shareFiles(for: summary)
        XCTAssertTrue(r.urls.isEmpty); XCTAssertEqual(r.message, ShareFiles.scanNotFound)
        let review = await model.reportShareFiles(.review)
        XCTAssertTrue(review.urls.isEmpty); XCTAssertNotNil(review.message)
    }
}

/// The model takes the screen from the window rather than reading shared device state (the foldable iPhone Duo's `UIScreen.main` stays on
/// the outer screen after it is opened). `AppModel.init` writes to defaults, so the class isolates itself:
/// - `setUp` snapshots the app's whole `UserDefaults.standard` domain and the eight app-group `ReaderSettings` keys that `refreshReaderSettings`
///   writes, then clears the stored paging choice and every stored command-set record, so each test starts from controlled state;
/// - `tearDown` puts both back exactly (keys that did not exist are removed again).
/// NOT restored: files the model touches (boxes, pending-scan folder, stray temporary copies) and the shared broadcast state. These tests
/// do not change those on purpose, but an `AppModel` does read and tidy them as it starts.
final class ScreenInjectionTests: XCTestCase {
    private var savedDomain: [String: Any]?
    private var savedGroup: [String: Any] = [:]
    // The keys `ReaderSettings` writes (Shared/ReaderSettings.swift); the suite is private there, so the literals are repeated here.
    private let groupKeys = ["storageCount", "eggCount", "scanIsFull", "scanAccount", "scanKind", "scanPass", "commandSizes", "autoEndPeriod"]
    private var group: UserDefaults? { UserDefaults(suiteName: SharedStore.groupID) }
    private let phone = CGSize(width: 440, height: 956)
    private let duoOuter = CGSize(width: 466, height: 678)

    override func setUp() {
        super.setUp()
        let standard = UserDefaults.standard
        savedDomain = Bundle.main.bundleIdentifier.flatMap { standard.persistentDomain(forName: $0) }
        for key in groupKeys { if let v = group?.object(forKey: key) { savedGroup[key] = v } }
        // The literals are `Keys.hand` ("pagedByHand") and `Keys.set` ("voiceSet.") in AppModel.swift, which is private there.
        for key in standard.dictionaryRepresentation().keys where key == "pagedByHand" || key.hasPrefix("voiceSet.") { standard.removeObject(forKey: key) }
    }

    override func tearDown() {
        if let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
            if let savedDomain { UserDefaults.standard.setPersistentDomain(savedDomain, forName: id) }
        }
        for key in groupKeys {
            if let v = savedGroup[key] { group?.set(v, forKey: key) } else { group?.removeObject(forKey: key) }
        }
        savedGroup = [:]
        super.tearDown()
    }

    /// A stored TAP command set made for the 440x956 iPhone, for an account name of the test's own.
    private func storeTapSetForPhone() throws {
        let record = AppModel.SetRecord(kind: .tap, date: Date(), screen: "440x956 iPhone")
        UserDefaults.standard.set(try JSONEncoder().encode(record), forKey: "voiceSet.screen-injection-test")
    }

    @MainActor func testAnIPhoneScreenAllowsTapsAndIsLabelled() {
        let model = AppModel(screenSize: phone, isPad: false)
        XCTAssertTrue(model.tapAvailable)
        XCTAssertEqual(model.screenLabel, "440x956 iPhone")
    }

    @MainActor func testTheDuoOuterScreenHasNoTapPosition() {
        let model = AppModel(screenSize: duoOuter, isPad: false)
        XCTAssertFalse(model.tapAvailable)
    }

    @MainActor func testTheScreenGivenToInitDecidesThePagingDefaultInitRestores() throws {
        try storeTapSetForPhone()
        XCTAssertNil(UserDefaults.standard.object(forKey: "pagedByHand"), "no stored paging choice, so the default applies")
        // The launch-order contract: `init` restores the paging from the command set for THIS screen, so the screen must be known before it runs.
        let onPhone = AppModel(screenSize: phone, isPad: false)
        XCTAssertEqual(onPhone.setKind, .tap)
        XCTAssertTrue(onPhone.commandSetMade)
        XCTAssertEqual(onPhone.pagedByHand, ScanKindAdvice.defaultsToHand(commandSetMade: true))
        let onDuo = AppModel(screenSize: duoOuter, isPad: false)
        XCTAssertEqual(onDuo.setKind, .swipe)
        XCTAssertFalse(onDuo.commandSetMade)
        XCTAssertEqual(onDuo.pagedByHand, ScanKindAdvice.defaultsToHand(commandSetMade: false))
        XCTAssertNotEqual(onPhone.pagedByHand, onDuo.pagedByHand, "the two defaults differ, so this test can tell the screens apart")
    }

    @MainActor func testAScreenChangeUpdatesTheScreenAndNeverRestoresThePaging() throws {
        try storeTapSetForPhone()
        // Tap screen to swipe screen: the command set stops counting, and a wrong `restorePaging()` would turn hand paging on.
        let model = AppModel(screenSize: phone, isPad: false)
        XCTAssertFalse(model.pagedByHand)
        model.screenChanged(size: duoOuter, isPad: false)
        XCTAssertEqual(model.screenSize, duoOuter)
        XCTAssertEqual(model.screenLabel, "466x678 iPhone")
        XCTAssertFalse(model.commandSetMade)
        XCTAssertFalse(model.pagedByHand, "a fold must not change how the scan is paged")
        // The other way: a wrong `restorePaging()` would turn hand paging off.
        let other = AppModel(screenSize: duoOuter, isPad: false)
        XCTAssertTrue(other.pagedByHand)
        other.screenChanged(size: phone, isPad: false)
        XCTAssertTrue(other.commandSetMade)
        XCTAssertTrue(other.pagedByHand)
        // A choice flipped after init survives a change too.
        other.pagedByHand = false
        other.screenChanged(size: CGSize(width: 669, height: 951), isPad: false)
        XCTAssertFalse(other.pagedByHand)
        XCTAssertEqual(other.screenLabel, "669x951 iPhone")
    }

    @MainActor func testAnIPadIdiomIsLabelledIPad() {
        let model = AppModel(screenSize: CGSize(width: 1032, height: 1376), isPad: true)
        XCTAssertTrue(model.screenLabel.hasSuffix("iPad"), model.screenLabel)
        model.screenChanged(size: CGSize(width: 1032, height: 1376), isPad: false)
        XCTAssertTrue(model.screenLabel.hasSuffix("iPhone"), model.screenLabel)
    }
}
