import Foundation
import PogoBox

// pogo-voice: make the Voice Control commands file the app makes, for testing on a Mac.
//
//   pogo-voice --set [--screen WxH] --out <file>   (the one-time set of 13 commands)
//   pogo-voice <storage-count> [--fast] [--tap] [--screen WxH] [--locale en_AU] [--now YYYY-MM-DDTHH:MM:SSZ] --out <file>
//
// Sized as the app sizes it (storage count less one, plus 2%, rounded up, at least 3; batches of 50). --tap needs a screen size
// the tap position has been measured on (440x956, the default). Compare with experiments/voice-control/generate_commands.py.

func die(_ m: String) -> Never { FileHandle.standardError.write(Data((m + "\n").utf8)); exit(2) }
var count: Int?, set = false, fast = false, tap = false, out: String?, locale = "en_AU", screen = (440.0, 956.0), now = Date()
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let a = args.removeFirst()
    func value() -> String { guard !args.isEmpty else { die("\(a) needs a value") }; return args.removeFirst() }
    switch a {
    case "--fast": fast = true
    case "--set": set = true
    case "--tap": tap = true
    case "--out": out = value()
    case "--locale": locale = value()
    case "--screen":
        let parts = value().split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { die("--screen needs WxH in points, such as 440x956") }
        screen = (parts[0], parts[1])
    case "--now":
        guard let d = ISO8601DateFormatter().date(from: value()) else { die("--now needs a UTC time like 2026-10-02T00:00:00Z") }
        now = d
    case _ where a.hasPrefix("--"): die("unknown option \(a)")
    default: count = Int(a) ?? { die("the storage count must be a whole number") }()
    }
}
if set, let out {
    // The one-time set: tap on the checked screen, swipe elsewhere.
    let tapOK = VoiceCommandFile.tapPoint(width: screen.0, height: screen.1) != nil
    let kind = VoiceCommandFile.SetKind.forScreen(tapAvailable: tap || tapOK)
    do {
        let data = try VoiceCommandFile.makeSet(kind: kind, locale: locale, tap: kind == .tap ? VoiceCommandFile.tapPoint(width: screen.0, height: screen.1) : nil, screenWidth: screen.0, screenHeight: screen.1, now: now)
        try data.write(to: URL(fileURLWithPath: out), options: .atomic)
        print("wrote \(out): \(data.count) bytes; the \(kind.rawValue) set of \(VoiceCommandFile.setSizes.count) commands")
        exit(0)
    } catch { die(error.localizedDescription) }
}
guard let count, let out else { die("usage: pogo-voice <storage-count> [--fast] [--tap] [--screen WxH] [--locale id] [--now time] --out <file>") }
let pace: VoiceCommandFile.Pace = tap ? (fast ? .tapFast : .tapNormal) : (fast ? .swipeFast : .swipeNormal)
let size = VoiceCommandFile.sizing(storageCount: count, pace: pace)
do {
    let data = try VoiceCommandFile.make(count: size.steps, pace: pace, batch: size.batch, locale: locale,
                                         tap: tap ? VoiceCommandFile.tapPoint(width: screen.0, height: screen.1) : nil, screenWidth: screen.0, screenHeight: screen.1, now: now)
    try data.write(to: URL(fileURLWithPath: out), options: .atomic)
    print("wrote \(out): \(data.count) bytes; \(size.repeats) x \(size.batch) \(pace.isTap ? "taps" : "swipes") for \(count) Pokémon (\(size.steps) steps needed), about \(Int((size.estimatedSeconds / 60).rounded())) min")
} catch { die(error.localizedDescription) }
