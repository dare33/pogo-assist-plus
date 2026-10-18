import Foundation

/// A Voice Control commands file that pages through Pokémon GO storage: a Swift port of
/// `experiments/voice-control/generate_commands.py`, which stays the reference (a test compares the two). The file is an XML
/// property list with a CommandsTable holding a batch gesture (an NSKeyedArchiver archive of an `AXMutableReplayableGesture`:
/// touch events in screen points) and a chain (`CACRecordedUserActionFlow`) that repeats the batch until enough Pokémon are
/// passed. Nothing here acts in the game beyond paging: a swipe or a tap on the "next Pokémon" arrow.
///
/// The scheme, as the Python does it: the batch gesture holds at most 50 page steps (50 was proven on devices); the chain
/// repeats it `ceil(steps / 50)` times and the batch is cut to `ceil(steps / repeats)`; there is no separate final partial gesture.
/// A scan of `steps` page steps pages `repeats * batch` times, which overshoots by less than the number of repeats; at the end of the list a swipe stays on the last Pokémon
/// and a tap on the arrow closes the appraisal and then does nothing (tested on the 440 x 956 iPhone only).
public enum VoiceCommandFile {
    // MARK: - paces

    public enum Pace: String, CaseIterable, Codable, Identifiable {
        case swipeNormal, swipeFast, tapNormal, tapFast
        public var id: String { rawValue }
        /// Seconds between the start of one page step and the next.
        public var every: Double { switch self { case .swipeNormal: return 2.1; case .swipeFast: return 1.6; case .tapNormal: return 1.2; case .tapFast: return 1.0 } }
        /// Seconds one swipe lasts (a tap lasts `tapHold`).
        public var swipeDuration: Double { self == .swipeFast ? 0.6 : 0.85 }
        public var isTap: Bool { self == .tapNormal || self == .tapFast }

        /// The setting's name, used everywhere: the pace list, the button, the "last made" line.
        public var title: String {
            switch self { case .tapNormal: return "Scan"; case .tapFast: return "Fast scan"; case .swipeNormal: return "Slow swipe"; case .swipeFast: return "Swipe" }
        }
        public var spokenTitle: String { title.lowercased() }
        /// "1.2 s per Pokémon", the secondary text of a row.
        public var secondsText: String { "\(every) s per Pokémon" }
        /// What is said to Voice Control, one command per mode so several can be installed together.
        public var commandName: String { "Pogo " + spokenTitle }
        /// The name of the mode's batch gesture: words nobody says, none shared with any spoken command or with another gesture's name.
        public var gestureName: String {
            switch self { case .tapNormal: return "Amber lantern"; case .tapFast: return "Silver compass"; case .swipeNormal: return "Quiet walnut"; case .swipeFast: return "Velvet marble" }
        }
        /// The number the mode's two command identifiers come from (`Custom.<n>` for the gesture, `Custom.<n+60>` for the command): the
        /// same every time the mode's file is made, so importing it replaces that mode's commands and no other mode's.
        public var idBase: Double {
            switch self { case .tapNormal: return 780_000_000; case .tapFast: return 780_000_200; case .swipeNormal: return 780_000_400; case .swipeFast: return 780_000_600 }
        }
        /// The modes a person can choose. Where the tap position has been measured: Scan and Fast scan (both paged by taps). Elsewhere there is no choice, only
        /// `Swipe` (the 1.6 s swipe, the pace that read every value correctly on the phone). The 2.1 s swipe is still made by the
        /// generator, as the proven reference timing, but is not offered.
        public static func offered(tapAvailable: Bool) -> [Pace] { tapAvailable ? [.tapNormal, .tapFast] : [.swipeFast] }
        public static func defaultMode(tapAvailable: Bool) -> Pace { offered(tapAvailable: tapAvailable)[0] }
        /// A note shown on the row, or nil.
        public var note: String? { self == .tapFast ? "misreads seen at this pace" : nil }
        /// The file the app offers: "Pogo scan 300 (440x956 iPhone).voicecontrolcommands". A tap file holds absolute screen points, so its
        /// name carries the screen it was made for; a swipe file does not need to.
        public func fileName(count: Int, screen: String? = nil) -> String {
            let on = (isTap && screen != nil) ? " (\(screen!))" : ""
            return "\(commandName) \(count)\(on).voicecontrolcommands"
        }
    }

    // MARK: - tap position: the one place it is kept

    /// The right-hand "next Pokémon" arrow, measured on a real 1320 x 2868 px frame of the 440 x 956 pt iPhone.
    public static let measuredTapXFraction = 0.964
    public static let measuredTapYFraction = 0.811
    /// A tap point left of this fraction of the screen width is refused: once the appraisal closes at the end of the list the
    /// Pokémon page shows, with Power up and Evolve to the LEFT of the arrow. Nothing may act in the game beyond paging.
    public static let minTapXFraction = 0.95
    /// Seconds from the touch to its lift.
    public static let tapHold = 0.06

    /// A screen size the tap position has been measured on, with the measured point. Adding a device is one line here.
    public struct CheckedScreen: Equatable {
        public var width: Double, height: Double
        public var tapX: Double, tapY: Double
    }
    public static let checkedScreens: [CheckedScreen] = [
        CheckedScreen(width: 440, height: 956, tapX: 424, tapY: 775),
    ]

    /// "440x956 iPhone": a screen size and kind for a file name and for the record of what a command was made on.
    public static func screenLabel(width: Double, height: Double, isPad: Bool) -> String { "\(Int(width))x\(Int(height)) \(isPad ? "iPad" : "iPhone")" }

    /// The tap point for a screen of this size in points, or nil when the position has not been measured there.
    public static func tapPoint(width: Double, height: Double) -> CGPoint? {
        checkedScreens.first { $0.width == width && $0.height == height }.map { CGPoint(x: $0.tapX, y: $0.tapY) }
    }

    // MARK: - sizing

    public static let defaultBatch = 50
    /// The swipe set's gesture length (see `SetKind.maxBatch`).
    public static let swipeSetBatch = 10
    /// Extra seconds the chain adds at each join between two batch gestures (the estimate's 0.8 s; the app tells `Refine` so a batch
    /// join is not mistaken for a repeated Pokémon).
    public static let joinExtraSeconds = 0.8

    public struct Sizing: Equatable {
        /// Page steps the scan needs: the storage count less the first Pokémon (already on screen) plus 2%, rounded up; at least 3.
        public var steps: Int
        public var batch: Int
        public var repeats: Int
        /// Page steps the command makes in all (`repeats * batch`), at least `steps`.
        public var covers: Int { repeats * batch }
        /// The Python's estimate: repeats x (batch x every + the join).
        public var estimatedSeconds: Double
    }

    /// The most page steps a command makes: the steps for `StorageCount.maximum` Pokémon.
    public static var maxSteps: Int { steps(storageCount: StorageCount.maximum) }

    public static func steps(storageCount: Int) -> Int { max(3, ((min(max(storageCount, 1), StorageCount.maximum) - 1) * 102 + 99) / 100) }

    /// At most `defaultBatch` page steps in a gesture, cut to `ceil(steps / repeats)` so the overshoot stays small (51 steps is
    /// 2 x 26 = 52, not 2 x 50; 1,427 is 29 x 50). The Python does the same.
    public static func sizing(storageCount: Int, pace: Pace) -> Sizing {
        let steps = steps(storageCount: storageCount)
        let repeats = (steps + defaultBatch - 1) / defaultBatch
        let batch = (steps + repeats - 1) / repeats
        return Sizing(steps: steps, batch: batch, repeats: repeats, estimatedSeconds: Double(repeats) * (Double(batch) * pace.every + joinExtraSeconds))
    }

    /// The sizing of a command of the set: like `sizing`, with the kind's own gesture length. For the tap set it is `sizing` exactly. Every join
    /// between two gestures adds `joinExtraSeconds`, which the paging hint passes to `Refine`.
    public static func setSizing(size: Int, kind: SetKind) -> Sizing {
        let steps = steps(storageCount: size), cap = kind.maxBatch
        let repeats = (steps + cap - 1) / cap
        let batch = (steps + repeats - 1) / repeats
        return Sizing(steps: steps, batch: batch, repeats: repeats, estimatedSeconds: Double(repeats) * (Double(batch) * kind.pace.every + joinExtraSeconds))
    }

    // MARK: - make

    public enum Failure: Error, LocalizedError, Equatable {
        case needsTapPoint
        case tapTooFarLeft(x: Double, limit: Double)
        /// The point is not the measured point of a screen of this width and height (or no screen was given).
        case tapNotChecked
        case badCount
        public var errorDescription: String? {
            switch self {
            case .needsTapPoint: return "Tap paging is only available on screens it has been checked on."
            case .tapNotChecked: return "Tap paging is only available on screens it has been checked on."
            case .tapTooFarLeft: return "The tap point is too far from the right-hand edge. A tap there could reach Power up or Evolve, so the command is not made."
            case .badCount: return "The number of page steps must be from 1 to the steps for 10,000 Pokémon, and a batch from 1 to \(VoiceCommandFile.defaultBatch)."
            }
        }
    }

    /// The commands file. `count` is the number of page steps to make, as `--count` in the Python (use `sizing(...).steps`);
    /// `batch` the page steps in one gesture. A tap pace needs `tap` and the screen's width and height in points: the point must be the
    /// measured one of a checked screen of exactly that size (`checkedScreens`), and is still asserted to be at or right of `minTapXFraction` of the width. `now` fixes the time stamps (a test passes one; the app passes the time). The names and the identifiers come from the pace, so each mode has its own commands.
    public static func make(count: Int, pace: Pace, batch: Int = defaultBatch, name: String? = nil, batchName: String? = nil, idBase: Double? = nil, locale: String = "en_AU",
                            tap: CGPoint? = nil, screenWidth: Double? = nil, screenHeight: Double? = nil, now: Date = Date()) throws -> Data {
        let name = name ?? pace.commandName, batchName = batchName ?? pace.gestureName
        // Bounded above so no Int can overflow `count + batch - 1`: the most steps the app makes (10,000 Pokémon) and the largest batch.
        guard (1...maxSteps).contains(count), (1...defaultBatch).contains(batch) else { throw Failure.badCount }
        var events: [(Double, (Double, Double)?)]
        let ref = now.timeIntervalSinceReferenceDate
        if pace.isTap {
            let point = try verifiedTap(tap, screenWidth, screenHeight)
            events = taps(start: ref, count: batch, x: Double(point.x), y: Double(point.y), every: pace.every)
        } else {
            events = swipes(start: ref, count: batch, xFrom: 340, xTo: 75, y: 340, every: pace.every, duration: pace.swipeDuration)
        }
        let repeats = (count + batch - 1) / batch
        let idBase = idBase ?? pace.idBase
        let batchId = "Custom." + String(format: "%.6f", idBase), chainId = "Custom." + String(format: "%.6f", idBase + 60)
        func base() -> [String: Any] { ["ConfirmationRequired": false, "CustomModifyDate": now, "CustomScope": "com.apple.speech.SystemWideScope"] }
        var batchEntry = base()
        batchEntry["CustomCommands"] = [locale: [batchName]]; batchEntry["CustomType"] = "RunGesture"; batchEntry["CustomGesture"] = gesture(events)
        var chainEntry = base()
        chainEntry["CustomCommands"] = [locale: [name]]; chainEntry["CustomType"] = "RunUserActionFlow"; chainEntry["CustomUserActionFlow"] = flow(commandId: batchId, repeats: repeats, locale: locale)
        // An export carries the exporting phone's SystemVersion; the files imported in testing copied one (as the Python does).
        let system: [String: Any] = ["ProductName": "iPhone OS", "ProductVersion": "27.2", "ProductBuildVersion": "24B5089g", "ReleaseType": "Beta"]
        let root: [String: Any] = ["CommandsTable": [batchId: batchEntry, chainId: chainEntry], "ExportDate": ref, "SystemVersion": system]
        return try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
    }

    /// The one check a tap passes before any file holds it: only the measured point of a checked screen of exactly this width and height
    /// (a point that merely passes the edge rule is not enough), and right of `minTapXFraction`. `make` and `makeSet` both call it.
    private static func verifiedTap(_ tap: CGPoint?, _ screenWidth: Double?, _ screenHeight: Double?) throws -> CGPoint {
        guard let tap else { throw Failure.needsTapPoint }
        guard let w = screenWidth, let h = screenHeight, w.isFinite, h.isFinite, let measured = tapPoint(width: w, height: h), Double(tap.x) == Double(measured.x), Double(tap.y) == Double(measured.y) else { throw Failure.tapNotChecked }
        guard tap.x >= minTapXFraction * w else { throw Failure.tapTooFarLeft(x: Double(tap.x), limit: minTapXFraction * w) }
        return tap
    }

    // MARK: - the one-time set

    /// The command sizes in the set: "Pogo scan N" pages for N Pokémon. One table; the owner chose these. A scan is started with the
    /// smallest size that covers the storage count, because a running command cannot be stopped: this bounds the overshoot.
    public static let setSizes = [25, 50, 100, 200, 300, 500, 750, 1000, 1500, 2000, 3000, 4000, 5000]

    /// Tap on a checked screen; swipe everywhere else. The set has no fast (1.0 s) commands.
    public enum SetKind: String, Codable, CaseIterable {
        case tap, swipe
        /// The most page steps in one gesture. A tap gesture is small, so the tap set keeps `defaultBatch` (and stays byte-identical to the first
        /// version of the set); a swipe gesture holds about 38 touch events per swipe, so the swipe set is cut to short gestures, repeated more often,
        /// to keep the file small.
        var maxBatch: Int { self == .tap ? defaultBatch : swipeSetBatch }
        /// How long "Go to sleep" takes to stop a command: it stops at the end of the batch that is playing, so up to the gesture's length (50 taps x 1.2 s is a
        /// minute; 10 swipes x 1.6 s is 16 seconds), plus the join.
        public var stopDelayText: String {
            let seconds = Double(maxBatch) * pace.every + joinExtraSeconds
            return seconds >= 55 ? "up to a minute" : "up to \(Int(seconds.rounded(.up))) seconds"
        }
        /// The pace every command of the set pages at: 1.2 s taps, 1.6 s swipes.
        public var pace: Pace { self == .tap ? .tapNormal : .swipeFast }
        public static func forScreen(tapAvailable: Bool) -> SetKind { tapAvailable ? .tap : .swipe }
        /// The first identifier number: size `i` uses `Custom.<base + 100 i>` for its gesture and `+60` for its command. The SAME for both kinds
        /// (the spoken names are the same too), so importing either set replaces the other instead of leaving two commands for one phrase. Clear of
        /// the single-mode ids (780,000,000 to 780,000,660).
        var idBase: Double { 781_000_000 }
        /// Words nobody says, none shared with any spoken command, with another gesture name or with the single modes' gesture names.
        var gestureNames: [String] {
            let (adjectives, nouns) = self == .tap
                ? (["Copper", "Maple", "Violet", "Cedar", "Linen", "Pewter", "Saffron", "Hazel", "Indigo", "Cobalt", "Russet", "Ivory", "Sable"],
                   ["anchor", "ribbon", "thimble", "kettle", "pebble", "bobbin", "trowel", "bellows", "quill", "ladder", "spindle", "mallet", "chisel"])
                : (["Tawny", "Olive", "Crimson", "Opal", "Umber", "Teal", "Ochre", "Fawn", "Slate", "Mauve", "Garnet", "Jade", "Coral"],
                   ["pitcher", "sundial", "barrel", "basket", "anvil", "lattice", "bucket", "hammock", "tassel", "abacus", "crayon", "saddle", "trellis"])
            return zip(adjectives, nouns).map { "\($0) \($1)" }
        }
    }

    /// What is said for a size: digits in the command text ("Pogo scan 300"). Whether Voice Control matches a spoken "three hundred" to
    /// digits is not known from the file format and has to be tried on a phone.
    public static func setCommandName(size: Int) -> String { "Pogo scan \(size)" }

    /// The smallest size that covers `count` Pokémon, or nil when `count` is above the largest (5,000 covers the first 5,000; the rest needs a
    /// second scan with Add and update).
    public static func setSize(covering count: Int) -> Int? { setSizes.first { $0 >= count } }

    /// The file the app offers: "Pogo scan commands (440x956 iPhone).voicecontrolcommands" for tap (it carries the screen), without for swipe.
    public static func setFileName(kind: SetKind, screen: String? = nil) -> String {
        "Pogo scan commands" + ((kind == .tap && screen != nil) ? " (\(screen!))" : "") + ".voicecontrolcommands"
    }

    /// ONE commands file with the whole set: for each size in `setSizes` a spoken command and its own batch gesture, sized by `sizing` (so
    /// "Pogo scan 300" pages exactly as `make(count: steps(300))` does). Tap kind goes through the same checks as `make`. Identifiers are
    /// stable per size and kind, so importing again replaces these commands and nothing else.
    public static func makeSet(kind: SetKind, locale: String = "en_AU", tap: CGPoint? = nil, screenWidth: Double? = nil, screenHeight: Double? = nil, now: Date = Date()) throws -> Data {
        let pace = kind.pace
        let point = kind == .tap ? try verifiedTap(tap, screenWidth, screenHeight) : nil
        let ref = now.timeIntervalSinceReferenceDate
        func base() -> [String: Any] { ["ConfirmationRequired": false, "CustomModifyDate": now, "CustomScope": "com.apple.speech.SystemWideScope"] }
        var table = [String: Any]()
        for (i, size) in setSizes.enumerated() {
            let sizing = setSizing(size: size, kind: kind)
            let events = point.map { taps(start: ref, count: sizing.batch, x: Double($0.x), y: Double($0.y), every: pace.every) }
                ?? swipes(start: ref, count: sizing.batch, xFrom: 340, xTo: 75, y: 340, every: pace.every, duration: pace.swipeDuration)
            let idBase = kind.idBase + Double(i) * 100
            let batchId = "Custom." + String(format: "%.6f", idBase), chainId = "Custom." + String(format: "%.6f", idBase + 60)
            var batchEntry = base()
            batchEntry["CustomCommands"] = [locale: [kind.gestureNames[i]]]; batchEntry["CustomType"] = "RunGesture"; batchEntry["CustomGesture"] = gesture(events)
            var chainEntry = base()
            chainEntry["CustomCommands"] = [locale: [setCommandName(size: size)]]; chainEntry["CustomType"] = "RunUserActionFlow"
            chainEntry["CustomUserActionFlow"] = flow(commandId: batchId, repeats: sizing.repeats, locale: locale)
            table[batchId] = batchEntry; table[chainId] = chainEntry
        }
        let system: [String: Any] = ["ProductName": "iPhone OS", "ProductVersion": "27.2", "ProductBuildVersion": "24B5089g", "ReleaseType": "Beta"]
        return try PropertyListSerialization.data(fromPropertyList: ["CommandsTable": table, "ExportDate": ref, "SystemVersion": system] as [String: Any], format: .xml, options: 0)
    }

    // MARK: - events

    static func swipes(start: Double, count: Int, xFrom: Double, xTo: Double, y: Double, every: Double, duration: Double, hz: Int = 60) -> [(Double, (Double, Double)?)] {
        var events = [(Double, (Double, Double)?)]()
        for k in 0..<count {
            let t0 = start + Double(k) * every
            let steps = Int((duration * Double(hz)).rounded(.toNearestOrEven))
            for i in 0...steps {
                var f = Double(i) / Double(steps)
                f = f * f * (3 - 2 * f)   // ease in and out, like a finger
                events.append((t0 + Double(i) / Double(hz), (round2(xFrom + (xTo - xFrom) * f), y)))
            }
            events.append((t0 + Double(steps + 1) / Double(hz), nil))
        }
        return events
    }

    static func taps(start: Double, count: Int, x: Double, y: Double, every: Double) -> [(Double, (Double, Double)?)] {
        var events = [(Double, (Double, Double)?)]()
        for k in 0..<count {
            let t0 = start + Double(k) * every
            events.append((t0, (x, y)))
            events.append((t0 + tapHold, nil))
        }
        return events
    }

    /// Python's `round(x, 2)`: the double nearest the correctly rounded two-decimal value.
    private static func round2(_ x: Double) -> Double { Double(String(format: "%.2f", x)) ?? x }

    /// Python's `%r` of a float: the shortest text that reads back as the same double.
    private static func repr(_ d: Double) -> String { "\(d)" }

    // MARK: - the archives (NSKeyedArchiver layout, the part these classes need)

    /// Mirrors the Python `Archive`: object 0 is "$null", `add` appends and returns the index, `once` makes an object once per key.
    /// Objects are added in the same order as the Python adds them, so the indexes (UIDs) agree.
    private final class Archive {
        var objects: [PV] = [.string("$null")]
        var memo = [String: Int]()
        func add(_ v: PV) -> Int { objects.append(v); return objects.count - 1 }
        func once(_ key: String, _ make: () -> PV) -> Int {
            if let i = memo[key] { return i }
            let i = add(make()); memo[key] = i; return i
        }
        func string(_ t: String) -> Int { once("s:" + t) { .string(t) } }
        func cls(_ names: String...) -> Int { once("c:" + names[0]) { .dict([("$classname", .string(names[0])), ("$classes", .array(names.map { .string($0) }))]) } }
        func dumps() -> Data {
            BinaryPlist.encode(.dict([("$version", .int(100000)), ("$archiver", .string("NSKeyedArchiver")), ("$top", .dict([("root", .uid(1))])), ("$objects", .array(objects))]))
        }
    }

    static func gesture(_ events: [(Double, (Double, Double)?)]) -> Data {
        let a = Archive()
        let root = a.add(.null), array = a.add(.null)
        let kFingers = a.string("Fingers"), kForces = a.string("Forces"), kTime = a.string("Time")
        let finger = a.once("finger") { .int(3) }   // the finger identifier the on-phone recorder used
        let zero = a.once("zero") { .real(0.0) }
        func mutable() -> Int { a.cls("NSMutableDictionary", "NSDictionary", "NSObject") }
        var uids = [Int]()
        for (time, point) in events {
            let event = a.add(.null)
            uids.append(event)
            var fingers: Int, forces: Int
            if let point {
                let value = a.add(.null)
                let pointval = a.add(.string("{\(repr(point.0)), \(repr(point.1))}"))
                a.objects[value] = .dict([("NS.pointval", .uid(pointval)), ("$class", .uid(a.cls("NSValue", "NSObject"))), ("NS.special", .int(1))])
                let c1 = mutable()
                fingers = a.add(.dict([("NS.keys", .array([.uid(finger)])), ("NS.objects", .array([.uid(value)])), ("$class", .uid(c1))]))
                let c2 = mutable()
                forces = a.add(.dict([("NS.keys", .array([.uid(finger)])), ("NS.objects", .array([.uid(zero)])), ("$class", .uid(c2))]))
            } else {
                let c1 = mutable()
                fingers = a.add(.dict([("NS.keys", .array([])), ("NS.objects", .array([])), ("$class", .uid(c1))]))
                let c2 = mutable()
                forces = a.add(.dict([("NS.keys", .array([])), ("NS.objects", .array([])), ("$class", .uid(c2))]))
            }
            let t = a.add(.real(time))
            let c = a.cls("NSDictionary", "NSObject")
            a.objects[event] = .dict([("NS.keys", .array([.uid(kFingers), .uid(kForces), .uid(kTime)])), ("NS.objects", .array([.uid(fingers), .uid(forces), .uid(t)])), ("$class", .uid(c))])
        }
        a.objects[array] = .dict([("NS.objects", .array(uids.map { .uid($0) })), ("$class", .uid(a.cls("NSMutableArray", "NSArray", "NSObject")))])
        let c = a.cls("AXMutableReplayableGesture", "AXReplayableGesture", "NSObject")
        a.objects[root] = .dict([("$class", .uid(c)), ("AllEvents", .uid(array)), ("Version", .uid(a.once("one") { .int(1) })), ("ArePointsDeviceRelative", .bool(false))])
        return a.dumps()
    }

    static func flow(commandId: String, repeats: Int, locale: String) -> Data {
        let a = Archive()
        let root = a.add(.null), tasks = a.add(.null)
        let target = a.string(commandId)
        var uids = [Int]()
        for _ in 0..<repeats {
            let task = a.add(.null)
            uids.append(task)
            let c = a.cls("NSMutableDictionary", "NSDictionary", "NSObject")
            let attributes = a.add(.dict([("NS.keys", .array([])), ("NS.objects", .array([])), ("$class", .uid(c))]))
            a.objects[task] = .dict([("CommandIdentifier", .uid(target)), ("Version", .int(1)), ("Type", .int(1)), ("TargetAttributes", .uid(attributes)),
                                     ("CanIgnoreFailure", .bool(false)), ("$class", .uid(a.cls("CACRecordedUserAction", "NSObject")))])
        }
        a.objects[tasks] = .dict([("NS.objects", .array(uids.map { .uid($0) })), ("$class", .uid(a.cls("NSMutableArray", "NSArray", "NSObject")))])
        let k1 = a.string("OverlayType"), k2 = a.string("LocaleIdentifier"), v1 = a.string("None"), v2 = a.string(locale)
        let sc = a.cls("NSDictionary", "NSObject")
        let settings = a.add(.dict([("NS.keys", .array([.uid(k1), .uid(k2)])), ("NS.objects", .array([.uid(v1), .uid(v2)])), ("$class", .uid(sc))]))
        let rc = a.cls("CACRecordedUserActionFlow", "NSObject")
        a.objects[root] = .dict([("$class", .uid(rc)), ("Version", .int(1)), ("EnvironmentSettings", .uid(settings)), ("Tasks", .uid(tasks))])
        return a.dumps()
    }
}

// MARK: - a binary property list writer (bplist00), for the archives: Foundation cannot write the UID type

enum PV {
    case null, bool(Bool), int(Int), real(Double), string(String), uid(Int)
    case array([PV])
    case dict([(String, PV)])
}

enum BinaryPlist {
    static func encode(_ root: PV) -> Data {
        // Flatten depth first; a container's children are numbered after it.
        // Equal scalars (strings, numbers, UIDs) share one object, as plistlib does: the archives repeat the same few keys
        // tens of thousands of times.
        var flat = [PV](), children = [[Int]](), shared = [String: Int]()
        func visit(_ v: PV) -> Int {
            var key: String?
            switch v {
            case .string(let s): key = "s" + s
            case .int(let n): key = "i\(n)"
            case .real(let d): key = "r\(d.bitPattern)"
            case .uid(let n): key = "u\(n)"
            case .bool(let b): key = "b\(b)"
            default: break
            }
            if let key, let i = shared[key] { return i }
            let index = flat.count
            if let key { shared[key] = index }
            flat.append(v); children.append([])
            switch v {
            case .array(let items): children[index] = items.map(visit)
            case .dict(let pairs):
                let keys = pairs.map { visit(.string($0.0)) }
                let values = pairs.map { visit($0.1) }
                children[index] = keys + values
            default: break
            }
            return index
        }
        _ = visit(root)
        let refSize = byteCount(flat.count - 1)
        var out = Data("bplist00".utf8)
        var offsets = [Int]()
        for (i, v) in flat.enumerated() {
            offsets.append(out.count)
            switch v {
            case .null: out.append(0x00)
            case .bool(let b): out.append(b ? 0x09 : 0x08)
            case .int(let n): out.append(contentsOf: intObject(n))
            case .real(let d): out.append(0x23); out.append(contentsOf: withUnsafeBytes(of: d.bitPattern.bigEndian, Array.init))
            case .uid(let n): let c = byteCount(n); out.append(UInt8(0x80 | (c - 1))); out.append(contentsOf: be(n, c))
            case .string(let s):
                if s.utf8.allSatisfy({ $0 < 0x80 }) { out.append(contentsOf: header(0x50, s.utf8.count)); out.append(contentsOf: Array(s.utf8)) }
                else { let u = Array(s.utf16); out.append(contentsOf: header(0x60, u.count)); for c in u { out.append(contentsOf: be(Int(c), 2)) } }
            case .array(let items):
                out.append(contentsOf: header(0xA0, items.count))
                for r in children[i] { out.append(contentsOf: be(r, refSize)) }
            case .dict(let pairs):
                out.append(contentsOf: header(0xD0, pairs.count))
                for r in children[i] { out.append(contentsOf: be(r, refSize)) }
            }
        }
        let tableStart = out.count
        let offsetSize = byteCount(tableStart)
        for o in offsets { out.append(contentsOf: be(o, offsetSize)) }
        out.append(contentsOf: [UInt8](repeating: 0, count: 6))
        out.append(UInt8(offsetSize)); out.append(UInt8(refSize))
        out.append(contentsOf: be(flat.count, 8)); out.append(contentsOf: be(0, 8)); out.append(contentsOf: be(tableStart, 8))
        return out
    }

    private static func byteCount(_ n: Int) -> Int { n < 0x100 ? 1 : n < 0x10000 ? 2 : n < 0x1_0000_0000 ? 4 : 8 }
    private static func be(_ n: Int, _ size: Int) -> [UInt8] { (0..<size).map { UInt8((n >> (8 * (size - 1 - $0))) & 0xFF) } }
    private static func intObject(_ n: Int) -> [UInt8] {
        let c = n < 0 ? 8 : byteCount(n)
        let exp = c == 1 ? 0 : c == 2 ? 1 : c == 4 ? 2 : 3
        return [UInt8(0x10 | exp)] + be(n, c)
    }
    private static func header(_ marker: UInt8, _ count: Int) -> [UInt8] {
        count < 15 ? [marker | UInt8(count)] : [marker | 0x0F] + intObject(count)
    }
}


/// The storage count a person types for the command: 1 to 10,000, read without overflow.
public enum StorageCount {
    public static let maximum = 10_000
    /// Above this the app asks whether the count is right before making the command.
    public static let confirmAbove = 3_000

    public enum Parsed: Equatable { case empty, valid(Int), invalid }

    public static func parse(_ text: String) -> Parsed {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return .empty }
        guard t.allSatisfy({ $0.isASCII && $0.isNumber }), t.count <= 6, let n = Int(t), (1...maximum).contains(n) else { return .invalid }
        return .valid(n)
    }

    /// A plain sentence when the text is not a usable count, else nil (an empty field is not a problem).
    public static func problem(for text: String) -> String? {
        parse(text) == .invalid ? "Type a whole number of Pokémon from 1 to \(maximum.formatted())." : nil
    }

    public static func needsConfirmation(_ count: Int) -> Bool { count > confirmAbove }
}
