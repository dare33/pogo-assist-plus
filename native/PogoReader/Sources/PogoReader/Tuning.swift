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

    /// The extension keeps at most 5 frames a second.
    public static let framePeriod = 0.2

    /// All the grouper's thresholds are durations, because a busy extension drops frames: a card seen in
    /// two or three readings must be judged like one seen in seven. They are the old frame counts at 5 fps.
    ///
    /// This long of consecutive readings with neither a CP nor an HP read (mid-swipe, no anchors, a card
    /// sliding past) is a swipe: the next card is a new Pokemon, even if it reads the same as the last
    /// (two identical Staraptor in a row). On the marathon clips every swipe leaves 3 to 7 such frames
    /// (0.6 s or more) and nothing inside a Pokemon's time on screen leaves more than 2.
    public static let swipeSeparatorSeconds = 0.6

    /// A run that lasted at most this long and has no settled bars, or whose CP does not fit its HP and
    /// bars, next to a row of the same Pokemon with a related CP and an HP that does not differ, is a card
    /// caught mid-slide: it is absorbed into that neighbour, which says `absorbed:<cp>` (the intent of JS
    /// absorbStrays, which takes one frame; the iPad clip has three-frame ones while the team leader
    /// covers the HP and the bars still animate).
    public static let strayMaxSeconds = 0.6

    /// A swipe tick can end a run only between two card readings at least this far apart. A swipe lasts 0.6 s or more
    /// (three frames at 5 fps), but its first and last frames can themselves be readable cards (the old card still
    /// legible while it starts to slide, the new one already legible as it lands), so the readings that bracket it can
    /// be as little as 0.4 s apart (one blank between): that is NOT covered, and two identical Pokémon with such a
    /// swipe merge. 0.55 s is the shortest gap that holds a swipe with two non-card frames between its card readings;
    /// closer than that a tick is taken to be a jump inside one stay (a touch dot, the iPad leader's animation).
    public static let swipeMinGapSeconds = 0.55

    /// At most this many swipe ticks are kept waiting for a reading; the oldest is dropped past it.
    public static let maxPendingTicks = 64

    /// Readings with only a name belong to one stretch if no more than this lies between them (seconds).
    public static let nameOnlyGapSeconds = 1.0

    /// The luma signature must stay above its threshold for this many consecutive frames to be a swipe (a swipe
    /// gives 3 to 6; a lone jump is a touch dot or an animation and would split one Pokemon in two).
    public static let swipeEventMinFrames = 3

    /// A stretch with a CP but no readable name is listed as an unnamed row when it lasted this long
    /// (two frames at full rate, as JS lists it).
    public static let unnamedMinSeconds = 0.4

    /// A card with its CP hidden and no HP read is listed only if it lasted this long.
    public static let hiddenMinSeconds = 0.6

    /// A row seen for less than this (one reading at full rate) is flagged `short-run`.
    public static let shortRunSeconds = 0.4

    /// A row that spans this long or more is flagged `long-stay`: an ordinary card is on screen 1.0 to 1.6 s,
    /// two identical Pokemon whose swipe was not seen (frames dropped) span 3 s or more. The last card
    /// of a run, which stays on screen, is flagged too.
    public static let longStaySeconds = 2.4

    /// "Save crops" mode: at most this many frames are kept per on-screen segment (frames 2, 4, 6 of a
    /// segment whose bars have settled), and the whole archive is capped in files and bytes so a
    /// broadcast cannot fill the app group container.
    public static let maxCropFramesPerSegment = 3
    public static let maxSavedFiles = 1500
    public static let maxSavedBytes = 48 * 1_048_576

    /// Below this much `os_proc_available_memory()` the live modes skip Vision for the frame (and count
    /// it) instead of risking the extension being killed. A guess: Vision's own working set while it
    /// reads is the big unknown on the phone; raise it if runs are still killed.
    public static let lowMemoryAvailableBytes = 8 * 1_048_576

    /// The app calls the broadcast dead when no state has been written for this long (seconds); the
    /// extension writes at least once a second.
    public static let staleStateSeconds = 4.0

    /// Longest run of frames for which the grouper keeps a hidden-CP or weak-name stretch pending.
    public static let maxPendingFrames = 60
}
