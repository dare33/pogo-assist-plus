import Foundation

/// What one screenshot gave, read ONCE by `FrameReader`. No second look, no voting between frames and no confidence that the reader did not report: a screenshot is
/// a Pokémon GO appraisal screen that read cleanly, or it says why it did not. Nothing here ever names a Pokémon the reader did not read.
public enum StillOutcome: Equatable {
    /// Name, CP, HP and settled appraisal bars were all read.
    case read(FrameReading)
    /// The Pokémon was read but its IVs were not: the appraisal bars were not on screen, or not finished filling. Carries the reading so the person can be told which Pokémon it was.
    case ivsMissing(FrameReading, StillIVsReason)
    /// Not a Pokémon GO detail screen the reader supports (another screen, a cropped or moving card, a stationed Pokémon's card).
    case unsupported(String)
    /// Looks like a detail screen, but a part that identifies the Pokémon could not be read.
    case unreadable(String)
    /// The recogniser failed while reading: nothing is known about the screenshot. Worth trying again.
    case fault(String)

    /// The words shown to the person.
    public var message: String {
        switch self {
        case .read: return "Read."
        case .ivsMissing(_, let why): return why.message
        case .unsupported(let m), .unreadable(let m), .fault(let m): return m
        }
    }
}

public enum StillIVsReason: String, Equatable {
    /// The appraisal panel (the three bars) was not found.
    case barsNotVisible
    /// The bars were found but their fill was not a clean whole number of units (the panel was still animating, or partly covered).
    case barsNotSettled

    public var message: String {
        switch self {
        case .barsNotVisible: return "The appraisal bars are not showing. Open the Pokémon's appraisal and take the screenshot with all three bars on screen."
        case .barsNotSettled: return "The appraisal bars had not finished filling. Wait for the bars to stop moving, then take the screenshot again."
        }
    }
}

/// The still-image adapter for `FrameReader`: one decoded screenshot in, one `StillOutcome` out. It runs the reader's own pixel and text halves (`FrameProcessor.process`,
/// the same path the Mac tool uses on recorded frames, at the broadcast's 750 px width) and only judges the result: it does not touch the reader's decisions.
/// Not thread-safe (the processor reuses one scaled buffer): use it from one queue.
public final class StillReader {
    public let processor: FrameProcessor

    /// `textReader` nil reads with Vision. Tests pass a stand-in; `names` nil takes the bundled species table.
    public init(textReader: TextReader? = nil, names: [NameCandidate]? = nil, targetWidth: Int? = 750) throws {
        let list = try names ?? displayNames(SpeciesTable.bundled())
        processor = FrameProcessor(textReader: textReader, names: list, targetWidth: targetWidth)
    }

    public func read(_ image: RGBAImage, label: String = "image") -> StillOutcome {
        let before = (processor.reader.text as? FaultReporting)?.faultCount ?? 0
        let reading = processor.process(image, time: 0, frame: label)
        // A recogniser that failed gives empty text, which would be judged as "not a Pokémon screen": say it was a fault instead.
        if let reporter = processor.reader.text as? FaultReporting, reporter.faultCount > before {
            return .fault("The text recogniser failed while reading this screenshot. Try again.")
        }
        return Self.judge(reading)
    }

    /// Decode a staged image and read it. A file that cannot be opened is the caller's `StillImageError`, not an outcome: it is a fault of the file, not of the screen.
    public func read(contentsOf url: URL, label: String = "image") throws -> StillOutcome {
        read(try StillImage.decode(contentsOf: url), label: label)
    }

    /// The rules, in one place (pure, so a test can drive every branch with a made-up reading).
    public static func judge(_ r: FrameReading) -> StillOutcome {
        if r.isStationed {
            return .unsupported("This is a stationed Pokémon's card, which shows no CP or HP. Open the Pokémon from your storage instead.")
        }
        if r.flags.contains("mid-swipe") {
            return .unsupported("The Pokémon card is cut off or moving. Use a full, uncropped screenshot of the Pokémon's appraisal screen.")
        }
        guard r.name != nil else {
            // No CP text and no HP bar found: not a Pokémon detail screen at all. A CP or an unmatched name with no species: it is one, the name could not be read.
            if r.cp == nil && r.cpText.isEmpty && r.nameText.isEmpty && !r.flags.contains("name-unmatched") && !r.flags.contains("cp-unread") {
                return .unsupported("This does not look like a Pokémon GO detail screen. Use an uncropped screenshot of a Pokémon's appraisal screen.")
            }
            if r.flags.contains("no-hp-bar") { return .unreadable("The card was found but not its HP bar, so it could not be read. A special background or a cropped screenshot can cause this.") }
            return .unreadable("The Pokémon's name could not be read. A Pokémon with a nickname cannot be read from a screenshot yet (the species name is not shown), and a banner or a cropped screenshot can hide the name too.")
        }
        if r.nameWeak == true {
            return .unreadable("The Pokémon's name was read too faintly to be sure of it. Take the screenshot again.")
        }
        guard r.cp != nil else {
            return .unreadable("The CP could not be read. It can be covered by a banner or by a tall Pokémon's model.")
        }
        guard r.hp != nil else {
            return .unreadable("The HP could not be read, so the Pokémon cannot be told from a similar one.")
        }
        guard let _ = r.ivs else { return .ivsMissing(r, .barsNotVisible) }
        guard r.ivConfidence >= SETTLED else { return .ivsMissing(r, .barsNotSettled) }
        return .read(r)
    }
}
