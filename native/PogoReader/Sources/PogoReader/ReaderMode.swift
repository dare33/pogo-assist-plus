import Foundation

/// How the broadcast extension reads the screen. Chosen in the app before the broadcast starts and
/// stored in the app group defaults; the extension reads it at `broadcastStarted`.
public enum ReaderMode: String, Codable, CaseIterable, Identifiable {
    /// Vision at its accurate level, live in the extension (the default).
    case accurate
    /// Vision at its fast level, live in the extension (smaller, less accurate).
    case fast
    /// No Vision in the extension: it saves a few small crops per card and the app reads them afterwards.
    case saveCrops
    /// Vision at its accurate level, live, with no pass for a name or HP crop that has not changed since the last frame
    /// (`FrameReader.reuseStaticText`). The same values on every clip on the Mac; not yet measured on a phone, so a choice to make
    /// before a scan, not the default.
    case accurateReuse
    /// As `accurateReuse`, and the name and HP crops that are read are read in one pass (`FrameReader.singlePass`): fewest passes, and
    /// a bigger image for Vision on the Mac (about 8 MB more peak footprint there). Not yet measured on a phone either.
    case accurateFewerPasses

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accurate: return "Read live (accurate)"
        case .fast: return "Read live (fast)"
        case .saveCrops: return "Save crops, read in app"
        case .accurateReuse: return "Read live (accurate, skip unchanged text)"
        case .accurateFewerPasses: return "Read live (accurate, fewest passes)"
        }
    }

    public static let defaultsKey = "readerMode"
}

/// The guard in the live modes: when iOS says little memory is left, skip Vision for the frame.
public enum ReadGuard {
    public static func shouldSkipVision(availableBytes: Int?, threshold: Int = Tuning.lowMemoryAvailableBytes) -> Bool {
        guard let a = availableBytes else { return false }
        return a < threshold
    }
}
