import Foundation

/// A scan that has been read for review and not yet saved or discarded, kept across a relaunch. The review works from its own copy of the shared `replay.jsonl`
/// (the next broadcast truncates and rewrites that one), and the copy lives here, in Application Support beside the boxes, not in the temporary folder the system
/// may empty. `meta` carries what the review needs from the broadcast's state file, which the next broadcast overwrites too. One pending scan at a time.
struct PendingScan: Codable, Equatable {
    var signature: String
    var account: String
    var state: BroadcastState?
}

enum PendingScanStore {
    static var directory: URL? { BoxExportFile.boxesRoot?.deletingLastPathComponent().appendingPathComponent("pending", isDirectory: true) }
    private static let copyName = "review-copy.jsonl", metaName = "review-copy.json"

    enum CopyResult {
        case copied(URL)
        /// The shared log is not (any longer) the scan with that signature.
        case replaced
        case failed(String)
    }

    /// A copy of the shared replay log named by the scan's signature, or why there is none. The signature is checked before the read and after it, and the bytes read must be as
    /// long as the signature says, so a log rewritten underneath never gives a mixed copy. Reads and writes up to 16 MB: call it off the main actor.
    nonisolated static func take(of shared: URL, signature: String, account: String, state: BroadcastState?, directory: URL? = PendingScanStore.directory) -> CopyResult {
        guard ReplayMarker.signature() == signature, let data = try? Data(contentsOf: shared),
              String(data.count) == signature.prefix(while: { $0 != "-" }), ReplayMarker.signature() == signature else { return .replaced }
        guard let dir = directory else { return .failed(BoxExportFile.storageUnavailableText) }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            // The meta goes first when the copy is replaced, so a copy never sits beside the meta of another scan.
            try? fm.removeItem(at: dir.appendingPathComponent(metaName))
            let dest = dir.appendingPathComponent(copyName)
            try data.write(to: dest, options: .atomic)
            try JSONEncoder().encode(PendingScan(signature: signature, account: account, state: state)).write(to: dir.appendingPathComponent(metaName), options: .atomic)
            return .copied(dest)
        } catch { return .failed(AppModel.plain(error)) }
    }

    /// The pending scan left by an earlier run: its meta and its copy, when both are there and the copy is as long as its signature says.
    static func load(directory: URL? = PendingScanStore.directory) -> (scan: PendingScan, copy: URL)? {
        guard let dir = directory, let data = try? Data(contentsOf: dir.appendingPathComponent(metaName)), let scan = try? JSONDecoder().decode(PendingScan.self, from: data) else { return nil }
        let copy = dir.appendingPathComponent(copyName)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: copy.path), let size = attrs[.size] as? Int,
              String(size) == scan.signature.prefix(while: { $0 != "-" }) else { return nil }
        return (scan, copy)
    }

    static func clear(directory: URL? = PendingScanStore.directory) {
        guard let dir = directory else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(metaName))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(copyName))
    }
}
