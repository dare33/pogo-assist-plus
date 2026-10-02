import Foundation
import PogoReader

// pogo-drop: how does the live grouper cope when the extension drops frames?
//
//   pogo-drop <readings.json> [--json] [--no-ticks] [--model SLOW/FAST ...]
//
// With the readings file's `signatureDiffs` (pogo-read writes them) every frame, read or dropped, delivers a
// swipe tick to the grouper when its signature jumps, as the extension does; --no-ticks replays without.
//
// Replays a full-rate readings file (pogo-read's output) through LiveGrouper twice: at full rate, and with
// a busy model: frames arrive every 0.2 s; a frame that needs Vision (it has a CP, name or HP text to read)
// keeps the extension busy for SLOW ms, any other frame for FAST ms; a frame arriving while busy is dropped
// (never read). The default models are 250/20, 450/200 and 650/200. The rows of each dropped run are
// compared with the full-rate rows by where they sit in time:
//   lost       a full-rate row with no row of the same name overlapping it
//   wrong-cp   overlapping rows of the same name, none with the same CP
//   extra      a row with no full-rate row of its name overlapping it
//   dup        two rows with the same name and CP overlapping one full-rate row
//   merged     one row overlapping two or more full-rate rows of its own CP (identical neighbours whose swipe was not seen)
// Full-rate flagged rows of up to three frames (cards caught mid-slide) are not counted as Pokemon.
// Each is split into "flagged" (the row carries any flag: a trace for the user) and "unflagged"; the goal
// is no unflagged wrong row and no row lost without a flagged trace beside it.

struct File: Decodable { var readings: [FrameReading]; var signatureDiffs: [Double?]? }

let args = Array(CommandLine.arguments.dropFirst())
guard let path = args.first(where: { !$0.hasPrefix("--") }) else {
    FileHandle.standardError.write(Data("usage: pogo-drop <readings.json> [--json] [--model SLOW/FAST ...]\n".utf8)); exit(2)
}
let useTicks = !args.contains("--no-ticks")
var models: [(Double, Double)] = []
var i = 0
while i < args.count { if args[i] == "--model", i + 1 < args.count { let p = args[i + 1].split(separator: "/").compactMap { Double($0) }; if p.count == 2 { models.append((p[0], p[1])) }; i += 1 }; i += 1 }
if models.isEmpty { models = [(250, 20), (450, 200), (650, 200)] }

let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
let table = try SpeciesTable.bundled()

func needsVision(_ r: FrameReading) -> Bool {
    !r.cpText.isEmpty || !r.nameText.isEmpty || r.flags.contains("cp-unread") || r.flags.contains("name-unmatched")
}

func replay(slow: Double, fast: Double) -> (rows: [LiveRow], kept: Int) {
    var g = LiveGrouper(species: table)
    var busyUntil = -1.0, kept = 0
    for (k, r) in file.readings.enumerated() {
        let t = r.time ?? Double(k) * 0.2
        // The extension looks at EVERY frame for a swipe, read or dropped (the luma signature in its callback).
        if useTicks, let diffs = file.signatureDiffs, k < diffs.count, let d = diffs[k], d > SwipeDetector.threshold { g.swipe(at: t) }
        if t < busyUntil - 1e-9 { continue }
        busyUntil = t + (needsVision(r) ? slow : fast) / 1000
        kept += 1
        g.add(r)
    }
    g.finish()
    return (g.rows, kept)
}

struct Outcome: Codable {
    var model: String
    var kept: Int, frames: Int, rows: Int, fullRateRows: Int
    var lostFlaggedTrace = 0, lostNoTrace = 0
    var wrongCpFlagged = 0, wrongCpUnflagged = 0
    var extraFlagged = 0, extraUnflagged = 0
    var dupFlagged = 0, dupUnflagged = 0
    var mergedFlagged = 0, mergedUnflagged = 0
    var details: [String] = []
}

func span(_ r: LiveRow) -> (Double, Double) { (r.firstTime ?? 0, r.lastTime ?? 0) }
func overlaps(_ a: LiveRow, _ b: LiveRow) -> Bool {
    let (a0, a1) = span(a), (b0, b1) = span(b)
    return b0 <= a1 + 0.1 && b1 >= a0 - 0.1
}
func sameName(_ a: LiveRow, _ b: LiveRow) -> Bool { a.name == b.name || a.name == "(name not read)" || b.name == "(name not read)" }
/// The same CP (a row whose CP is not read matches any).
func sameCp(_ a: LiveRow, _ b: LiveRow) -> Bool { guard let x = a.cp, let y = b.cp else { return true }; return x == y }
func label(_ r: LiveRow) -> String { "\(r.name) \(r.cp.map(String.init) ?? "?") hp\(r.hp.map(String.init) ?? "?") f\(r.frames) [\(r.flags.joined(separator: " "))] \(r.firstFrame ?? "")" }

let full = replay(slow: 0, fast: 0)
// A flagged row of one or two frames in the full-rate run is a card caught mid-slide, kept as a flagged
// trace: it is not a Pokémon to be lost or merged.
let real = full.rows.filter { !($0.frames <= 3 && !$0.flags.isEmpty) }
var outcomes: [Outcome] = []
for (slow, fast) in models {
    let run = replay(slow: slow, fast: fast)
    var o = Outcome(model: "\(Int(slow))/\(Int(fast))", kept: run.kept, frames: file.readings.count, rows: run.rows.count, fullRateRows: real.count)
    for b in real {
        let named = run.rows.filter { overlaps($0, b) && sameName($0, b) }
        let hits = named.filter { sameCp($0, b) }
        if hits.isEmpty {
            if named.isEmpty {
                if run.rows.contains(where: { overlaps($0, b) && !$0.flags.isEmpty }) { o.lostFlaggedTrace += 1 } else { o.lostNoTrace += 1; o.details.append("LOST " + label(b)) }
            } else if named.allSatisfy({ !$0.flags.isEmpty }) { o.wrongCpFlagged += 1 }
            else { o.wrongCpUnflagged += 1; o.details.append("WRONG-CP \(label(b)) -> " + named.map(label).joined(separator: " | ")) }
        } else if hits.count >= 2 {
            if hits.contains(where: { $0.flags.isEmpty }) { o.dupUnflagged += 1; o.details.append("DUP " + hits.map(label).joined(separator: " | ")) } else { o.dupFlagged += 1 }
        }
    }
    for d in run.rows {
        let bs = real.filter { overlaps(d, $0) && sameName(d, $0) }
        let eq = bs.filter { sameCp(d, $0) }
        if bs.isEmpty { if d.flags.isEmpty { o.extraUnflagged += 1; o.details.append("EXTRA " + label(d)) } else { o.extraFlagged += 1 } }
        else if eq.count >= 2 { if d.flags.isEmpty { o.mergedUnflagged += 1; o.details.append("MERGED " + label(d) + " <- " + eq.map(label).joined(separator: " | ")) } else { o.mergedFlagged += 1 } }
    }
    outcomes.append(o)
}

if args.contains("--json") {
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try enc.encode(outcomes), as: UTF8.self))
} else {
    print("full-rate rows \(full.rows.count) from \(file.readings.count) frames")
    print("model     kept  rows | lost(trace/none)  wrong-cp(flag/unflag)  extra(flag/unflag)  dup(flag/unflag)  merged(flag/unflag)")
    for o in outcomes {
        print("\(o.model.padding(toLength: 9, withPad: " ", startingAt: 0)) \(String(o.kept).padding(toLength: 5, withPad: " ", startingAt: 0)) \(String(o.rows).padding(toLength: 4, withPad: " ", startingAt: 0)) | \(o.lostFlaggedTrace)/\(o.lostNoTrace)  \(o.wrongCpFlagged)/\(o.wrongCpUnflagged)  \(o.extraFlagged)/\(o.extraUnflagged)  \(o.dupFlagged)/\(o.dupUnflagged)  \(o.mergedFlagged)/\(o.mergedUnflagged)")
        for d in o.details { print("      \(d)") }
    }
}
