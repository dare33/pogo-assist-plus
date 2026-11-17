import Foundation

/// Counts frame times from the scan's first frame. The broadcast's presentation timestamps count from device start, and a time since boot must
/// not end up in a replay log (which a person can report or share). The first frame with a finite timestamp is the origin (time 0); every later
/// one is `stamp - origin`. Only differences matter to the reader (the swipe ticker, the grouper, the end controller), so nothing downstream changes.
/// One clock per broadcast: `reset()` when a broadcast starts. Not thread-safe; the extension keeps it under its frame lock.
public struct ScanClock: Equatable {
    public private(set) var origin: Double?

    public init() {}

    /// The scan-relative time of a frame, or nil for a timestamp that is not a number (such a frame is dropped and must not set the origin).
    public mutating func time(for stamp: Double) -> Double? {
        guard stamp.isFinite else { return nil }
        if origin == nil { origin = stamp }
        return stamp - origin!
    }

    public mutating func reset() { origin = nil }
}
