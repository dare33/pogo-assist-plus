import Foundation

/// The decisions the app makes about screenshot import that are not UI, kept here so they can be tested: when the sheet may open by itself, when reading runs, and what a cancelled
/// pick leaves behind.
public enum ImportPolicy {
    /// The sheet of queued screenshots opens by itself only for a batch the person has not been shown, only when nothing else holds the screen, and never in front of a scan that has
    /// finished or is waiting to be reviewed (that comes first; the sheet is looked at again when it is done).
    public static func shouldAutoOpenSheet(unseenBatches: Int, sheetOpen: Bool, canOpenReview: Bool, scanPendingPickup: Bool) -> Bool {
        unseenBatches > 0 && !sheetOpen && canOpenReview && !scanPendingPickup
    }
}

/// Whether reading may run. It stops when the app leaves the front and starts again ONLY when the app really comes back: other reasons to look at the queue (a scan's review
/// ending while the app is in the background, say) never lift it.
public struct ReadingGate: Equatable {
    public private(set) var paused = false
    public init() {}
    public var mayRead: Bool { !paused }
    /// The scene moved. Returns true when reading should be started again.
    @discardableResult
    public mutating func scenePhaseChanged(background: Bool) -> Bool {
        if background { paused = true; return false }
        guard paused else { return false }
        paused = false
        return true
    }
    /// The system is about to suspend the app mid-read.
    public mutating func timeExpired() { paused = true }
}

/// Copying a pick out of Photos into a batch: one picture at a time, with a check for cancellation after every load and again before the batch is made. A cancelled pick commits nothing
/// and leaves no half-made folder behind.
public enum PickStager {
    public enum Result {
        case cancelled
        case committed(ImportManifest, unusable: Int)
        case failed(Error, unusable: Int)
    }

    public static func stage(count: Int, builder: ImportQueue.Builder, load: @escaping (Int) async -> (data: Data, assetId: String?)?, isCancelled: @escaping () -> Bool,
                             progress: @escaping (Int) -> Void = { _ in }) async -> Result {
        var unusable = 0
        for i in 0..<count {
            if isCancelled() { builder.abort(); return .cancelled }
            progress(i)
            guard let picture = await load(i) else { unusable += 1; continue }
            // the encode and the hashing are not the caller's thread's work
            let ok = await Task.detached(priority: .userInitiated) { (try? builder.add(data: picture.data, assetId: picture.assetId)) != nil }.value
            if !ok { unusable += 1 }
        }
        // Cancelled during the last load: nothing is queued.
        if isCancelled() { builder.abort(); return .cancelled }
        do { return .committed(try builder.commit(), unusable: unusable) } catch { return .failed(error, unusable: unusable) }
    }
}
