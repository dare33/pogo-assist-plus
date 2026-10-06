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

    /// Where `AppModel` keeps the boxes. One place, so the Shortcuts action reads the folder the app writes.
    static var boxesRoot: URL {
        (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))?
            .appendingPathComponent("PogoAssist", isDirectory: true).appendingPathComponent("boxes", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("boxes", isDirectory: true)
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
