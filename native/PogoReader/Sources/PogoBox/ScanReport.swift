import CryptoKit
import Foundation
import PogoReader

/// One scan's files for the "Make scans better" button: a single JSON document, gzip-compressed, that the developer can read to improve
/// the reader. Built by a pure function from what the app knows. It has no account-name field and no device identifier, and no other scan's readings; its review lines can name saved Pokémon kept from Gone, which came from other scans.
public struct ScanReport: Codable, Equatable {
    public struct AppInfo: Codable, Equatable { public var version: String; public var build: String
        public init(version: String, build: String) { self.version = version; self.build = build } }
    /// The kind of phone, not which phone: the hardware model, the system version, the screen in points and the language.
    public struct DeviceInfo: Codable, Equatable {
        public var model: String, os: String, screenWidth: Double, screenHeight: Double, locale: String
        public init(model: String, os: String, screenWidth: Double, screenHeight: Double, locale: String) {
            self.model = model; self.os = os; self.screenWidth = screenWidth; self.screenHeight = screenHeight; self.locale = locale
        }
    }
    public struct ScanInfo: Codable, Equatable {
        public var kind: String, scanDate: Date, rowsRead: Int, storageCount: Int?
        public var pagedByCommand: Bool?, expectedPeriod: Double?, joinExtraSeconds: Double?
        public var measuredPeriod: Double?, measuredRegularity: Double?
    }

    public var schema = 1
    public var app: AppInfo
    public var device: DeviceInfo
    public var scan: ScanInfo
    public var note: String?
    /// The replay log as the extension wrote it (one JSON line per reading, swipe tick and dropped frame).
    public var replayLog: String
    public var result: ScanResult
    /// What `Refine` changed after the JavaScript grouping (twin splits, hidden-CP rows, ...), one line each; empty for a scan saved before they were kept.
    public var refineChanges: [String]
    /// What the person answered at review: unsure rows, rows left out, Pokémon kept although the scan proposed them as gone.
    public var review: [String]
    /// Later hand corrections and removals of Pokémon that first came from this scan, as far as the box versions record them.
    public var afterwards: [String]
    /// What this report could not include, so the reader of it knows.
    public var notIncluded: [String]
}

/// What goes into a report, collected by the app.
public struct ScanReportInput {
    public var replayLog: String
    public var result: ScanResult
    public var kind: BoxStore.Kind
    public var scanDate: Date
    public var storageCount: Int?
    public var paging: StoredPaging?
    public var pace: ScanPace?
    public var refineChanges: [String]
    public var review: [String]
    public var afterwards: [String]
    public var notIncluded: [String]
    public var note: String?
    public var app: ScanReport.AppInfo
    public var device: ScanReport.DeviceInfo

    public init(replayLog: String, result: ScanResult, kind: BoxStore.Kind, scanDate: Date, storageCount: Int? = nil, paging: StoredPaging? = nil, pace: ScanPace? = nil,
                refineChanges: [String] = [], review: [String] = [], afterwards: [String] = [], notIncluded: [String] = [], note: String? = nil, app: ScanReport.AppInfo, device: ScanReport.DeviceInfo) {
        self.replayLog = replayLog; self.result = result; self.kind = kind; self.scanDate = scanDate; self.storageCount = storageCount; self.paging = paging; self.pace = pace
        self.refineChanges = refineChanges; self.review = review; self.afterwards = afterwards; self.notIncluded = notIncluded; self.note = note; self.app = app; self.device = device
    }
}

public enum ScanReportBuilder {
    /// The built upload: the document, its gzip and a hash of the document without the note (so the same scan is not sent twice unchanged).
    public struct Built: Equatable {
        public var gzip: Data
        public var jsonBytes: Int
        public var contentHash: String
    }

    public static func report(_ input: ScanReportInput) -> ScanReport {
        let note = input.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        var missing = input.notIncluded
        if input.refineChanges.isEmpty { missing.append("No list of refine changes (the scan was saved before they were kept, or none were made).") }
        return ScanReport(app: input.app, device: input.device,
                          scan: .init(kind: input.kind == .full ? "full" : "partial", scanDate: input.scanDate, rowsRead: input.result.rows.count, storageCount: input.storageCount,
                                      pagedByCommand: input.paging?.pagedByCommand, expectedPeriod: input.paging?.expectedPeriod, joinExtraSeconds: input.paging?.joinExtraSeconds,
                                      measuredPeriod: input.pace?.medianPeriod, measuredRegularity: input.pace?.regularity),
                          note: (note?.isEmpty == false) ? note : nil, replayLog: input.replayLog, result: input.result, refineChanges: input.refineChanges,
                          review: input.review, afterwards: input.afterwards, notIncluded: missing)
    }

    public static func build(_ input: ScanReportInput) throws -> Built {
        let doc = report(input)
        let json = try encode(doc)
        var withoutNote = doc; withoutNote.note = nil
        let hash = SHA256.hash(data: try encode(withoutNote)).map { String(format: "%02x", $0) }.joined()
        return Built(gzip: try Gzip.compress(json), jsonBytes: json.count, contentHash: hash)
    }

    /// What the person did at review, one line each: answers to the unsure rows, and the entries the scan did not see (kept: one summary line; removed: one line each).
    public static func reviewLines(plan: BoxMerge.Plan, resolutions: [Int: BoxMerge.Resolution], keepGone: Set<String>, base: [BoxEntry]) -> [String] {
        func brief(_ r: ScanRow) -> String { "\(r.title), CP \(r.cp)" }
        let byId = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var lines = [String]()
        for u in plan.unsure {
            let row = brief(plan.scanned[u.scanned])
            switch resolutions[u.scanned] {
            case .existing(let id)?: lines.append("Unsure (\(u.kind.rawValue)) \(row): said it is the saved \(byId[id].map { brief($0.row) } ?? "Pokémon").")
            case .new?: lines.append("Unsure (\(u.kind.rawValue)) \(row): said it is new.")
            case .leaveOut?: lines.append("Unsure (\(u.kind.rawValue)) \(row): left it out of the box.")
            case nil: lines.append("Unsure (\(u.kind.rawValue)) \(row): no answer.")
            }
        }
        let report = BoxMerge.goneReport(plan, resolutions: resolutions)
        // One line with the count for what was kept (an untouched Full scan keeps every entry it did not see: one line per entry would be 1,500 lines); a line each only for what the
        // person marked for removal.
        let kept = report.gone.filter { keepGone.contains($0) }
        if !kept.isEmpty { lines.append("\(kept.count) saved Pokémon the scan did not see were kept in the box.") }
        for id in report.gone where !keepGone.contains(id) { lines.append("Removed because the scan did not see it, as the person marked: \(byId[id].map { brief($0.row) } ?? id).") }
        for k in report.kept { lines.append("Kept (not seen clearly): \(byId[k.savedId].map { brief($0.row) } ?? k.savedId). \(k.reason)") }
        return lines
    }

    /// The document back from an upload (for tests and for reading one).
    public static func decode(gzip: Data) throws -> ScanReport {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try d.decode(ScanReport.self, from: Gzip.decompress(gzip))
    }

    private static func encode(_ doc: ScanReport) throws -> Data {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]
        return try e.encode(doc)
    }
}

// MARK: - upload

/// Where reports go. The values come from the git-ignored local xcconfig; a missing or placeholder value means no config.
public struct ReportConfig: Equatable {
    public var baseURL: URL
    public var key: String

    public init?(urlText: String?, keyText: String?) {
        guard let u = urlText?.trimmingCharacters(in: .whitespaces), let k = keyText?.trimmingCharacters(in: .whitespaces), !u.isEmpty, !k.isEmpty,
              !Self.isPlaceholder(u), !Self.isPlaceholder(k), let url = URL(string: u), url.scheme == "https", url.host != nil else { return nil }
        baseURL = url; key = k
    }

    /// Unexpanded `$(...)` text (the build setting was not defined) and the example file's `YOUR...` values.
    static func isPlaceholder(_ s: String) -> Bool { s.contains("$(") || s.uppercased().contains("YOUR") || s.uppercased().contains("PLACEHOLDER") }
}

public struct HTTPPost {
    public var url: URL
    public var headers: [String: String]
    public var body: Data
    public var timeout: TimeInterval
}

public protocol ReportTransport { func send(_ post: HTTPPost) async throws -> (status: Int, body: Data) }

/// Remembers when reports were sent, for the daily limit. The app keeps it in UserDefaults; tests in memory.
public protocol UploadLedger: AnyObject {
    var sentTimes: [Date] { get }
    func record(_ date: Date)
}

public final class MemoryLedger: UploadLedger {
    public private(set) var sentTimes: [Date] = []
    public init() {}
    public func record(_ date: Date) { sentTimes.append(date) }
}

public struct ScanReportUploader {
    public static let maximumBytes = 3_500_000
    public static let dailyLimit = 10
    public static let timeout: TimeInterval = 30
    public static let bucket = "scan-reports"

    public enum Failure: Error, LocalizedError, Equatable {
        case notConfigured
        case tooLarge(Int)
        case alreadySent(Date)
        case dailyLimit
        case rejected(status: Int)
        case network(String)
        public var errorDescription: String? {
            switch self {
            case .notConfigured: return "Sending is not set up in this build."
            case .tooLarge(let n): return "This scan's report is \(String(format: "%.1f", Double(n) / 1_000_000)) MB, which is more than can be sent (3.5 MB). Share the files instead."
            case .alreadySent(let d): return "This scan was already sent on \(d.formatted(date: .abbreviated, time: .omitted)) and has not changed."
            case .dailyLimit: return "You have already sent \(ScanReportUploader.dailyLimit) reports in the last day. Try again tomorrow, or share the files instead."
            case .rejected(let s): return "The server did not accept the report (code \(s)). Nothing was sent twice. You can try again later or share the files instead."
            case .network(let m): return "The report could not be sent: \(m) You can try again or share the files instead."
            }
        }
    }

    public struct Receipt: Equatable { public var path: String; public var key: String? }

    public var config: ReportConfig
    public var transport: ReportTransport
    public var ledger: UploadLedger
    public var now: () -> Date = Date.init
    public var uuid: () -> UUID = UUID.init

    public init(config: ReportConfig, transport: ReportTransport, ledger: UploadLedger, now: @escaping () -> Date = Date.init, uuid: @escaping () -> UUID = UUID.init) {
        self.config = config; self.transport = transport; self.ledger = ledger; self.now = now; self.uuid = uuid
    }

    /// A unique path, so nothing is ever overwritten: `yyyy-mm/yyyymmddThhmmssZ-<uuid>.json.gz` in UTC.
    public func path(at date: Date) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d/%04d%02d%02dT%02d%02d%02dZ-%@.json.gz", c.year!, c.month!, c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!, uuid().uuidString.lowercased())
    }

    /// One attempt, 30 s, no retry. `previousHash` and `previousSentAt` are the scan's record of an earlier send.
    public func send(_ built: ScanReportBuilder.Built, previousHash: String?, previousSentAt: Date?) async throws -> Receipt {
        if let h = previousHash, h == built.contentHash, let at = previousSentAt { throw Failure.alreadySent(at) }
        guard built.gzip.count <= Self.maximumBytes else { throw Failure.tooLarge(built.gzip.count) }
        let date = now()
        guard ledger.sentTimes.filter({ date.timeIntervalSince($0) < 86_400 && date.timeIntervalSince($0) >= 0 }).count < Self.dailyLimit else { throw Failure.dailyLimit }
        let p = path(at: date)
        guard let url = URL(string: config.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/storage/v1/object/\(Self.bucket)/\(p)") else { throw Failure.notConfigured }
        let post = HTTPPost(url: url, headers: ["apikey": config.key, "Authorization": "Bearer \(config.key)", "Content-Type": "application/gzip"], body: built.gzip, timeout: Self.timeout)
        let result: (status: Int, body: Data)
        do { result = try await transport.send(post) } catch { throw Failure.network((error as? LocalizedError)?.errorDescription ?? error.localizedDescription) }
        guard result.status == 200 else { throw Failure.rejected(status: result.status) }
        ledger.record(date)
        let key = (try? JSONSerialization.jsonObject(with: result.body) as? [String: Any])?["Key"] as? String
        return Receipt(path: p, key: key)
    }
}
