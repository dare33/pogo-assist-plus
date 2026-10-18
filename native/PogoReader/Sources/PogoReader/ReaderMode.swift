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

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accurate: return "Read live (accurate)"
        case .fast: return "Read live (fast)"
        case .saveCrops: return "Save crops, read in app"
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
