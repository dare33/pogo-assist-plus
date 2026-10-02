import Foundation
import XCTest
@testable import PogoBox
import PogoReader

private final class FakeTransport: ReportTransport {
    var posts = [HTTPPost](), status = 200, body = Data("{\"Key\":\"scan-reports/x\"}".utf8), failure: Error?
    func send(_ post: HTTPPost) async throws -> (status: Int, body: Data) {
        posts.append(post)
        if let failure { throw failure }
        return (status, body)
    }
}

final class ScanReportTests: XCTestCase {
    private func fixtureResult() throws -> ScanResult {
        struct F: Decodable { var rows: [ScanRow]; var review: [ReviewEntry]; var unmatched: [Unmatched] }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "run8-tap-300.result", withExtension: "json", subdirectory: "Fixtures"))
        let f = try JSONDecoder().decode(F.self, from: Data(contentsOf: url))
        return ScanResult(rows: f.rows, review: f.review, unmatched: f.unmatched)
    }
    private let app = ScanReport.AppInfo(version: "0.1", build: "7")
    private let device = ScanReport.DeviceInfo(model: "iPhone17,2", os: "26.5", screenWidth: 440, screenHeight: 956, locale: "en_AU")
    private func input(note: String? = nil, replay: String = "{\"k\":\"t\",\"t\":1}\n") throws -> ScanReportInput {
        ScanReportInput(replayLog: replay, result: try fixtureResult(), kind: .full, scanDate: Date(timeIntervalSince1970: 1_790_000_000), storageCount: 313,
                        paging: StoredPaging(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: 0.8), pace: nil, refineChanges: ["twinSplit: Staraptor"], review: ["Unsure Staraptor: left out"],
                        afterwards: ["Corrected by hand: Moltres: CP 99 to 1990."], notIncluded: ["Corrections made to Pokémon from earlier scans."], note: note, app: app, device: device)
    }

    func testGzipRoundTripAndAKnownVector() throws {
        let text = Data(String(repeating: "pogo assist ", count: 500).utf8)
        let z = try Gzip.compress(text)
        XCTAssertLessThan(z.count, text.count / 5)
        XCTAssertEqual(try Gzip.decompress(z), text)
        XCTAssertEqual(Gzip.crc32(Data("123456789".utf8)), 0xCBF43926, "the standard CRC-32 check value")
        XCTAssertThrowsError(try Gzip.decompress(Data("not gzip at all, really".utf8)))
        var bad = z; bad[bad.count - 6] ^= 0xff
        XCTAssertThrowsError(try Gzip.decompress(bad))
        // an empty document
        XCTAssertEqual(try Gzip.decompress(try Gzip.compress(Data())), Data())
    }

    func testTheReportRoundTripsAndNeverNamesTheAccountOrAnotherScan() throws {
        let built = try ScanReportBuilder.build(try input(note: "Moltres looked wrong"))
        if let out = ProcessInfo.processInfo.environment["POGO_WRITE_REPORT"] { try built.gzip.write(to: URL(fileURLWithPath: out)) }   // to check with the system gzip
        let back = try ScanReportBuilder.decode(gzip: built.gzip)
        XCTAssertEqual(back.schema, 1); XCTAssertEqual(back.note, "Moltres looked wrong")
        XCTAssertEqual(back.result.rows.count, 313); XCTAssertEqual(back.scan.rowsRead, 313); XCTAssertEqual(back.scan.kind, "full"); XCTAssertEqual(back.scan.storageCount, 313)
        XCTAssertEqual(back.scan.pagedByCommand, true); XCTAssertEqual(back.scan.expectedPeriod, 1.2)
        XCTAssertEqual(back.device.model, "iPhone17,2"); XCTAssertEqual(back.app.build, "7")
        XCTAssertEqual(back.review, ["Unsure Staraptor: left out"]); XCTAssertEqual(back.afterwards.count, 1)
        XCTAssertTrue(back.notIncluded.contains("Corrections made to Pokémon from earlier scans."))
        // the keys that make the document, and no others
        let json = try JSONSerialization.jsonObject(with: Gzip.decompress(built.gzip)) as! [String: Any]
        XCTAssertEqual(Set(json.keys), ["schema", "app", "device", "scan", "note", "replayLog", "result", "refineChanges", "review", "afterwards", "notIncluded"])
        let text = String(decoding: try Gzip.decompress(built.gzip), as: UTF8.self).lowercased()
        for forbidden in ["account", "zorblax", "identifierforvendor", "udid", "serial"] { XCTAssertFalse(text.contains(forbidden), forbidden) }
    }

    func testTheNoteDoesNotChangeTheContentHashButTheScanDoes() throws {
        let a = try ScanReportBuilder.build(try input(note: "one")), b = try ScanReportBuilder.build(try input(note: "two")), c = try ScanReportBuilder.build(try input(replay: "{\"k\":\"t\",\"t\":2}\n"))
        XCTAssertEqual(a.contentHash, b.contentHash); XCTAssertNotEqual(a.contentHash, c.contentHash)
        XCTAssertNil(try ScanReportBuilder.decode(gzip: ScanReportBuilder.build(try input(note: "  ")).gzip).note, "a blank note is not sent")
        print("REPORT 313-row fixture with a one-line log: json \(a.jsonBytes) bytes, gzip \(a.gzip.count) bytes")
    }

    func testTheReviewLinesSayWhatThePersonDid() throws {
        let gm = try GameMaster.bundled()
        func row(_ id: String, cp: Int, hp: Int = 100, flags: [String] = []) -> ScanRow {
            ScanRow(index: 1, name: gm.byId[id]!.name, display: gm.byId[id]!.name, form: "", speciesId: id, dex: nil, cp: cp, hp: hp, ivs: nil, ivsRead: nil, ivsGuess: nil, level: nil, levelMax: nil, dust: nil, solveStatus: "none", flags: flags, frames: [])
        }
        let saved = [BoxEntry(id: "s", row: row("staraptor", cp: 1982, hp: 142), firstSeen: Date(), lastSeen: Date()), BoxEntry(id: "g", row: row("pidgey", cp: 100), firstSeen: Date(), lastSeen: Date())]
        let plan = BoxMerge.plan(scanned: [row("staraptor", cp: 182, hp: 142, flags: ["no-level-fits"])], into: saved, kind: .full, scanDate: Date(), gameMaster: gm)
        let lines = ScanReportBuilder.reviewLines(plan: plan, resolutions: [0: .leaveOut], keepGone: [], base: saved)
        XCTAssertTrue(lines.contains { $0.contains("left it out of the box") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("Removed because the scan did not see it: Pidgey") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("Kept (not seen clearly): Staraptor") })
        XCTAssertTrue(ScanReportBuilder.reviewLines(plan: plan, resolutions: [0: .new], keepGone: ["s", "g"], base: saved).contains { $0.hasPrefix("Kept in the box although") })
    }

    func testConfigIsAbsentForMissingOrPlaceholderValues() {
        XCTAssertNil(ReportConfig(urlText: nil, keyText: "k")); XCTAssertNil(ReportConfig(urlText: "", keyText: "k")); XCTAssertNil(ReportConfig(urlText: "https://x.supabase.co", keyText: ""))
        XCTAssertNil(ReportConfig(urlText: "$(SCAN_REPORT_URL)", keyText: "$(SCAN_REPORT_KEY)"))
        XCTAssertNil(ReportConfig(urlText: "https://YOUR-PROJECT.supabase.co", keyText: "YOUR-PUBLISHABLE-KEY"))
        XCTAssertNil(ReportConfig(urlText: "http://insecure.example", keyText: "k"))
        XCTAssertNotNil(ReportConfig(urlText: "https://abc.supabase.co", keyText: "sb_publishable_abc"))
    }

    private func uploader(_ t: FakeTransport, _ ledger: MemoryLedger = MemoryLedger(), at: Date = Date(timeIntervalSince1970: 1_790_000_000)) -> ScanReportUploader {
        ScanReportUploader(config: ReportConfig(urlText: "https://abc.supabase.co/", keyText: "KEY123")!, transport: t, ledger: ledger, now: { at }, uuid: { UUID(uuidString: "11111111-2222-3333-4444-555555555555")! })
    }

    func testUploadBuildsTheRequestAndAUniquePath() async throws {
        let t = FakeTransport(), ledger = MemoryLedger()
        let built = try ScanReportBuilder.build(try input())
        let receipt = try await uploader(t, ledger).send(built, previousHash: nil, previousSentAt: nil)
        let post = try XCTUnwrap(t.posts.first)
        XCTAssertEqual(post.url.absoluteString, "https://abc.supabase.co/storage/v1/object/scan-reports/\(receipt.path)")
        XCTAssertTrue(receipt.path.hasPrefix("2026-09/20260921T"), receipt.path); XCTAssertTrue(receipt.path.hasSuffix("-11111111-2222-3333-4444-555555555555.json.gz"))
        XCTAssertEqual(post.headers["apikey"], "KEY123"); XCTAssertEqual(post.headers["Authorization"], "Bearer KEY123"); XCTAssertEqual(post.timeout, 30)
        XCTAssertEqual(post.body, built.gzip); XCTAssertEqual(receipt.key, "scan-reports/x"); XCTAssertEqual(ledger.sentTimes.count, 1)
        XCTAssertEqual(t.posts.count, 1, "one attempt")
        // two paths never collide: a fresh uuid each time
        let u = ScanReportUploader(config: ReportConfig(urlText: "https://abc.supabase.co", keyText: "k")!, transport: t, ledger: MemoryLedger())
        XCTAssertNotEqual(u.path(at: Date()), u.path(at: Date()))
    }

    func testTheClientSideLimits() async throws {
        let built = try ScanReportBuilder.build(try input())
        // the same scan unchanged
        let t = FakeTransport()
        do { _ = try await uploader(t).send(built, previousHash: built.contentHash, previousSentAt: Date(timeIntervalSince1970: 1_789_000_000)); XCTFail() } catch { XCTAssertEqual(error as? ScanReportUploader.Failure, .alreadySent(Date(timeIntervalSince1970: 1_789_000_000))) }
        XCTAssertTrue(t.posts.isEmpty)
        // a changed scan is allowed
        _ = try await uploader(t).send(built, previousHash: "something else", previousSentAt: Date())
        // 10 in the last day
        let ledger = MemoryLedger(); for i in 0..<10 { ledger.record(Date(timeIntervalSince1970: 1_790_000_000 - Double(i) * 3600)) }
        do { _ = try await uploader(FakeTransport(), ledger).send(built, previousHash: nil, previousSentAt: nil); XCTFail() } catch { XCTAssertEqual(error as? ScanReportUploader.Failure, .dailyLimit) }
        // older than a day does not count
        let old = MemoryLedger(); for i in 0..<10 { old.record(Date(timeIntervalSince1970: 1_790_000_000 - 90_000 - Double(i))) }
        _ = try await uploader(FakeTransport(), old).send(built, previousHash: nil, previousSentAt: nil)
        // too large: refused before any request
        let big = ScanReportBuilder.Built(gzip: Data(count: ScanReportUploader.maximumBytes + 1), jsonBytes: 1, contentHash: "h")
        let t2 = FakeTransport()
        do { _ = try await uploader(t2).send(big, previousHash: nil, previousSentAt: nil); XCTFail() } catch { XCTAssertEqual(error as? ScanReportUploader.Failure, .tooLarge(3_500_001)) }
        XCTAssertTrue(t2.posts.isEmpty)
        XCTAssertTrue(ScanReportUploader.Failure.tooLarge(3_500_001).errorDescription!.contains("Share the files instead"))
    }

    func testFailuresArePlainAndNothingIsRecorded() async throws {
        let built = try ScanReportBuilder.build(try input())
        let rejected = FakeTransport(); rejected.status = 403
        let ledger = MemoryLedger()
        do { _ = try await uploader(rejected, ledger).send(built, previousHash: nil, previousSentAt: nil); XCTFail() } catch {
            XCTAssertEqual(error as? ScanReportUploader.Failure, .rejected(status: 403)); XCTAssertTrue(error.localizedDescription.contains("403"))
        }
        let down = FakeTransport(); down.failure = URLError(.notConnectedToInternet)
        do { _ = try await uploader(down, ledger).send(built, previousHash: nil, previousSentAt: nil); XCTFail() } catch {
            guard case ScanReportUploader.Failure.network = error else { return XCTFail("\(error)") }
            XCTAssertTrue(error.localizedDescription.contains("share the files instead"))
        }
        XCTAssertTrue(ledger.sentTimes.isEmpty, "a failed send does not count against the limit")
        XCTAssertEqual(rejected.posts.count + down.posts.count, 2, "no retry")
    }

    func testWhatHappenedAfterTheScanComesFromTheBoxVersions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-rep-\(UUID().uuidString)"); defer { try? FileManager.default.removeItem(at: dir) }
        let lib = BoxLibrary(root: dir)
        let d = Date(timeIntervalSince1970: 1_790_000_000)
        func e(_ id: String, cp: Int, first: Date) -> BoxEntry {
            BoxEntry(id: id, row: ScanRow(index: 1, name: "Pidgey", display: "Pidgey", form: "", speciesId: "pidgey", dex: 16, cp: cp, hp: 40, ivs: nil, ivsRead: nil, ivsGuess: nil, level: 5, levelMax: 5, dust: 1,
                                          solveStatus: "exact", flags: [], frames: []), firstSeen: first, lastSeen: first)
        }
        let old = e("old", cp: 50, first: d.addingTimeInterval(-86_400)), a = e("a", cp: 100, first: d), b = e("b", cp: 200, first: d)
        let s = try lib.store.save(ScanResult(rows: [], review: [], unmatched: []), account: "Zorblax", scanDate: d, source: "broadcast", replayLog: Data("x\n".utf8))
        try lib.commit(account: "Zorblax", entries: [old, a, b], reason: .scan, note: "scan", scanId: s.id, scanKind: .full, scanDate: d)
        var a2 = a; a2.row.cp = 1990; var old2 = old; old2.row.cp = 60
        try lib.commit(account: "Zorblax", entries: [old2, a2, b], reason: .edit, note: "Corrected", now: d.addingTimeInterval(10))
        try lib.commit(account: "Zorblax", entries: [old2, a2], reason: .edit, note: "Removed", now: d.addingTimeInterval(20))
        let lines = try lib.editsAfter(account: "Zorblax", scanId: s.id)
        XCTAssertEqual(lines, ["Corrected by hand: Pidgey: CP 100 to 1990.", "Removed from the box: Pidgey, CP 200."], "only Pokémon first seen at this scan; the earlier scan's correction is not included")
    }
}
