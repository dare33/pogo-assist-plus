import Foundation

/// Every number here is a guess made without real Vision output (or measured against the clips
/// named in the comment); change them in one place. The pixel thresholds ported from the JS reader
/// live in their own files, unchanged.
public enum Tuning {
    /// JS (Tesseract) calls a name "weak" below confidence 40 on a 0..100 scale. Vision reports
    /// 0..1 per candidate, mapped here by x100 so the JS number carries over unchanged. Vision's
    /// confidence is coarser and runs higher than Tesseract's (clean text sits near 1, garbled text
    /// well under 0.5), so 40 is a reasonable first cut, not a measured one: tune it from the
    /// `nameConfidence` field of real readings (`pogo-read` writes it per frame).
    public static let weakNameConfidence = 40.0

    /// The Lucky Pokemon second look accepts a confident, exact, whole name only; JS uses the same
    /// 40 as the weak line. Kept separate so the stricter rule can move on its own.
    public static let luckyNameConfidence = 40.0

    /// How far the CP crop extends past the "CP1234" text, in text heights, on each side. Vision does
    /// better with a little context than with Tesseract's tight digit crop. Measured on the two
    /// marathon clips at width 750 (0.1 digits-only, 0.15, 0.35, 0.6): 0.15 gave the fewest unread
    /// CPs on both (phone 5 against 12 at 0.35; iPad 9 against 11) and, on the iPad clip, the
    /// 50 rows the 50 swipes should give (48 at the others).
    public static let cpCropPadding = 0.15

    /// Vision wants text at a reasonable size. Crops shorter than these (pixels) are scaled up
    /// before recognition, because the extension works on frames scaled down to 750 px wide. The
    /// targets are crop heights chosen so the text inside is about 60 px tall: the CP crop is mostly
    /// text, the name crop about 45% text, the HP crop about 70%.
    public static let cpCropTargetHeight = 80.0
    public static let nameCropTargetHeight = 130.0
    public static let hpCropTargetHeight = 90.0
    /// Never scale a crop up by more than this (a tiny, mis-located crop is not worth blowing up).
    public static let maxUpscale = 4.0

    /// The Lucky Pokemon line sits one text line above the usual name position (fraction of the
    /// content height); same value as frame.js.
    public static let luckyLineOffset = 0.025

    /// A frame whose HP bar sits left of or right of these fractions of the content width is a card
    /// sliding in or out, not a settled one (frame.js).
    public static let settledBarLeft = 0.2...0.4

    /// Longest run of frames for which the grouper keeps a hidden-CP or weak-name stretch pending.
    public static let maxPendingFrames = 60
}
