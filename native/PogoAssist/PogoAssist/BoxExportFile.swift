import Foundation
import PogoBox
import PogoReader

/// The two files the box can be exported as.
enum ExportFormat: String, CaseIterable, Sendable { case csv, markdown }

/// Makes the export files from a saved box, off the screens: the Box screen's export and the Shortcuts action both go through here, so they cannot differ.
/// Nothing here starts a scan or touches the broadcast; it only reads the saved box.
enum BoxExportFile {
    enum Failure: Error, LocalizedError {
        case noAccount, noBox(String), unreadable(String)
        var errorDescription: String? {
            switch self {
            case .noAccount: return "Pogo Assist+ has no account yet. Open the app and scan some Pokémon first."
            case .noBox(let a): return "The box for \(a) is empty. Scan some Pokémon in Pogo Assist+ first."
            case .unreadable(let why): return why
            }
        }
    }

    /// Where `AppModel` keeps the boxes. One place, so the Shortcuts action reads the folder the app writes. nil when Application Support cannot be resolved:
    /// boxes are never kept anywhere else (the temporary folder is emptied by the system without warning), so the callers say there is a problem instead.
    static var boxesRoot: URL? {
        (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))?
            .appendingPathComponent("PogoAssist", isDirectory: true).appendingPathComponent("boxes", isDirectory: true)
    }

    /// Where the one scan left unsaved is kept (`PendingScanStore`), beside the boxes.
    static var pendingDirectory: URL? { boxesRoot?.deletingLastPathComponent().appendingPathComponent("pending-scan", isDirectory: true) }

    /// Said when `boxesRoot` is nil.
    static let storageUnavailableText = "This device would not give Pogo Assist+ a place to keep your boxes, so nothing can be saved. Restart the phone and open the app again. If this stays, free some storage."

    /// The library for the Shortcuts action, or the plain reason there is none.
    static func library() throws -> BoxLibrary {
        guard let root = boxesRoot else { throw Failure.unreadable(storageUnavailableText) }
        return BoxLibrary(root: root)
    }

    /// The account the app has selected (`AppModel`'s key), or the only one there is.
    static func defaultAccount(in library: BoxLibrary) -> String? {
        let accounts = (try? library.accounts()) ?? []
        if let a = UserDefaults.standard.string(forKey: "selectedAccount"), accounts.contains(a) { return a }
        return accounts.count == 1 ? accounts[0] : nil
    }

    /// The advice the Next tab shows for this version of the box: the saved copy, or worked out now (and saved, as the Next tab does). nil when it cannot be worked out.
    static func advice(for snap: BoxSnapshot, library: BoxLibrary, engine: CoreEngine) -> BoxAdvice? {
        if let cached = library.loadAdvice(account: snap.account, seq: snap.seq) { return cached }
        guard let report = try? engine.advise(rows: AppModel.csvRows(snap.entries), scanDate: snap.scanDate ?? snap.createdAt) else { return nil }
        let adv = BoxAdvice.make(from: report, entries: snap.entries)
        try? library.saveAdvice(adv, account: snap.account, seq: snap.seq)
        return adv
    }

    /// Writes the file for `entries` (the whole box, or the ones picked in select mode) of `snap` into the temporary folder. Call on the engine worker's queue.
    static func write(_ format: ExportFormat, snap: BoxSnapshot, only ids: Set<String>? = nil, library: BoxLibrary, engine: CoreEngine) throws -> URL {
        let entries = ids.map { ids in snap.entries.filter { ids.contains($0.id) } } ?? snap.entries
        let date = snap.scanDate ?? snap.createdAt
        let dir = FileManager.default.temporaryDirectory
        switch format {
        case .csv:
            let csv = try engine.csv(rows: AppModel.csvRows(entries), scanDate: date)
            let url = dir.appendingPathComponent(fileName(snap.account, date, "csv"))
            try Data(csv.utf8).write(to: url, options: .atomic)
            return url
        case .markdown:
            let md = BoxExport.markdown(entries: entries, advice: advice(for: snap, library: library, engine: engine), account: snap.account, date: date)
            let url = dir.appendingPathComponent(BoxExport.fileName(account: snap.account, date: date))
            try Data(md.utf8).write(to: url, options: .atomic)
            return url
        }
    }

    private static func fileName(_ account: String, _ date: Date, _ ext: String) -> String {
        BoxExport.fileName(account: account, date: date).replacingOccurrences(of: ".md", with: "." + ext)
    }
}

/// The files a person shares out of the app, written to the temporary folder with their times counted from an origin inside each file (`ShareTimes`: a saved scan's
/// result and log from their common earliest time, each Diagnostics file from its own; for a new build's log that is its first logged line). The stored files, which older
/// builds filled with times since the phone started, are only read. A file that cannot be read, or cannot be written out again, is left out and never shared as it is;
/// `notes` says so in plain words. No UI here; the call sites show `notes` themselves. Safe to call off the main actor, but one preparation at a time per screen: a new
/// preparation replaces the copies of the earlier one, so the call sites ignore a second tap until the first sheet has closed.
enum ShareFiles {
    struct Prepared {
        var urls: [URL] = []
        /// What the person should be told, one sentence each (empty when everything was shared whole).
        var notes: [String] = []
        /// The notes as one message, or nil.
        var message: String? { notes.isEmpty ? nil : notes.joined(separator: " ") }
    }

    static let scanNotFound = "That scan's files could not be found."

    /// The saved scan's result file and replay log. Its notes say "could not be found" when the scan's files cannot be found.
    static func savedScan(store: BoxStore, account: String, id: String, into tmp: URL) -> Prepared {
        guard let f = try? store.files(account: account, id: id) else { return Prepared(notes: [scanNotFound]) }
        var out = Prepared()
        // Earlier copies of this scan's two names are removed first, so a copy an older build wrote (the stored file as it was) is not left where a share could pick it up.
        for name in ["\(id).result.json", "\(id).replay.jsonl"] { try? FileManager.default.removeItem(at: tmp.appendingPathComponent(name)) }
        let resultData = try? Data(contentsOf: f.result)
        var logData: Data?
        var logUnreadable = false
        if let r = f.replay { if let d = try? Data(contentsOf: r) { logData = d } else { logUnreadable = true } }
        guard let resultData else {
            // The result cannot be read: the log goes alone, counted from its own first line.
            out.notes.append(unreadableResult)
            if let d = logData { if let r = ShareTimes.replayLog(d) { if let u = write(r.text, "\(id).replay.jsonl", in: tmp) { out.urls.append(u) } else { out.notes.append(failedLog) }; dropped(r.droppedLines, &out) } else { out.notes.append(unreadableLog) } }
            else if logUnreadable { out.notes.append(unreadableLog) }
            return out
        }
        let shared = ShareTimes.savedScan(result: resultData, replayLog: logData)
        if let d = shared.result { if let u = write(d, "\(id).result.json", in: tmp) { out.urls.append(u) } else { out.notes.append(failedResult) } }
        else if shared.notPrepared.contains(.result) { out.notes.append(failedResult) }
        else { out.notes.append(unreadableResult) }
        if let text = shared.replayLog { if let u = write(text, "\(id).replay.jsonl", in: tmp) { out.urls.append(u) } else { out.notes.append(failedLog) } }
        else if logUnreadable || shared.unreadable.contains(.replayLog) { out.notes.append(unreadableLog) }
        dropped(shared.droppedLines, &out)
        return out
    }

    /// The unsaved scan's own replay log (the review's copy), on its own.
    static func reviewLog(_ url: URL, into tmp: URL) -> Prepared {
        var out = Prepared()
        guard let d = try? Data(contentsOf: url), let r = ShareTimes.replayLog(d) else { out.notes.append(unreadableLog); return out }
        if let u = write(r.text, "scan-in-review.replay.jsonl", in: tmp) { out.urls.append(u) } else { out.notes.append(failedLog) }
        dropped(r.droppedLines, &out)
        return out
    }

    /// The Diagnostics screen's state file, saved-crop result and replay log, each counted from its own first time.
    static func diagnostics(into tmp: URL) -> Prepared {
        var out = Prepared()
        let folder = tmp.appendingPathComponent("diagnostics-share", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        func read(_ url: URL?, _ what: String) -> Data? {
            guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
            if let d = try? Data(contentsOf: url) { return d }
            out.notes.append("The \(what) could not be read, so it was left out."); return nil
        }
        let state = read(SharedStore.stateURL, "state file"), deferred = read(SharedStore.deferredURL, "saved-crop result"), log = read(SharedStore.replayURL, "reading log")
        let shared = ShareTimes.diagnostics(state: state, deferred: deferred, replayLog: log)
        func put(_ data: Data?, _ name: String, _ what: String) {
            guard let data else { return }
            if let u = write(data, name, in: folder) { out.urls.append(u) } else { out.notes.append("The \(what) could not be prepared for sharing, so it was left out.") }
        }
        put(shared.state, "state.json", "state file"); put(shared.deferred, "deferred.json", "saved-crop result"); put(shared.replayLog.map { Data($0.utf8) }, "replay.jsonl", "reading log")
        func what(_ p: ShareTimes.Part) -> String { p == .state ? "state file" : p == .deferred ? "saved-crop result" : "reading log" }
        for part in shared.unreadable where part != .result { out.notes.append("The \(what(part)) could not be read, so it was left out.") }
        for part in shared.notPrepared where part != .result { out.notes.append("The \(what(part)) could not be prepared for sharing, so it was left out.") }
        dropped(shared.droppedLines, &out)
        return out
    }

    private static let unreadableResult = "The scan's results could not be read, so they were left out."
    private static let failedResult = "The scan's results could not be prepared for sharing, so they were left out."
    private static let unreadableLog = "The scan's reading log could not be read, so it was left out."
    private static let failedLog = "The scan's reading log could not be prepared for sharing, so it was left out."

    private static func dropped(_ n: Int, _ out: inout Prepared) {
        if n > 0 { out.notes.append("\(n) damaged \(n == 1 ? "line" : "lines") of the reading log \(n == 1 ? "was" : "were") left out.") }
    }

    /// Replaces any earlier copy of the same name.
    private static func write(_ text: String, _ name: String, in dir: URL) -> URL? { write(Data(text.utf8), name, in: dir) }
    private static func write(_ data: Data, _ name: String, in dir: URL) -> URL? {
        let url = dir.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: url)
            try data.write(to: url, options: .atomic)
            return url
        } catch { return nil }
    }
}
