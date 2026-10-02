import Foundation
import PogoBox
import PogoReader

// pogo-rows: run the app core on a scan's frame readings, as the app does after a scan.
//
//   pogo-rows <readings.json | replay.jsonl> [--csv out.csv] [--json out.json] [--advise]
//             [--refine | --no-refine] [--diff]
//
// Prints the same roster table as scripts/extract.mjs, a summary line, the time taken and the peak
// physical footprint of this process. --refine (the default when the input has swipe ticks) runs the Swift
// post-pass (twin split at swipe ticks, hidden-CP rows) over the JavaScript result and prints the base and
// refined row counts; --no-refine prints the JavaScript's rows as they are. --diff compares the refined
// rows with the package's LiveGrouper run over the same readings and ticks.

func die(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

var input: String?, csvPath: String?, jsonPath: String?, advise = false, refineFlag: Bool?, diff = false
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--csv": guard !args.isEmpty else { die("--csv needs a path") }; csvPath = args.removeFirst()
    case "--json": guard !args.isEmpty else { die("--json needs a path") }; jsonPath = args.removeFirst()
    case "--advise": advise = true
    case "--refine": refineFlag = true
    case "--no-refine": refineFlag = false
    case "--diff": diff = true
    case _ where a.hasPrefix("--"): die("unknown option \(a)")
    default: if input == nil { input = a } else { die("one input file only") }
    }
}
guard let input else { die("usage: pogo-rows <readings.json | replay.jsonl> [--csv out.csv] [--json out.json] [--advise] [--refine | --no-refine] [--diff]") }

func err(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
let probe = MemoryProbe()
probe.sample()
let baseline = MemoryProbe.footprintBytes()

do {
    let loaded = try ReplayReadings.load(url: URL(fileURLWithPath: input))
    if loaded.skippedLines + loaded.malformedLines > 0 { err("replay: \(loaded.skippedLines) non-reading lines skipped, \(loaded.malformedLines) malformed") }
    let engine = CoreEngine()
    let t0 = Date()
    try engine.prepare()
    probe.sample()
    let tLoad = Date().timeIntervalSince(t0)
    let t1 = Date()
    let base = try engine.finish(readings: loaded.readings)
    let tFinish = Date().timeIntervalSince(t1)
    probe.sample()
    var result = base
    var refined: Refine.Refined?
    if refineFlag ?? loaded.hasTicks {
        let t = Date()
        let r = try Refine.apply(to: base, readings: loaded.readings, ticks: loaded.ticks, engine: engine)
        refined = r; result = r.scan
        err(String(format: "refine: %.2f s%@", Date().timeIntervalSince(t), loaded.hasTicks ? "" : " (no swipe ticks in the input: twin split skipped)"))
    }

    func pad(_ s: String, _ n: Int, left: Bool = false) -> String {
        let p = String(repeating: " ", count: max(0, n - s.count))
        return left ? p + s : s + p
    }
    print("idx  name                 cp    hp   ivs       level  frames  flags")
    for r in result.rows {
        let ivs = r.ivs.map { "\($0.atk)/\($0.def)/\($0.hp)" } ?? "?"
        func num(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }
        let level = r.level.map { l in r.levelMax.map { $0 == l ? num(l) : "\(num(l))-\(num($0))" } ?? num(l) } ?? "?"
        print("\(pad(String(r.index), 3, left: true))  \(pad(r.display, 20)) \(pad(String(r.cp), 4, left: true))  \(pad(r.hp.map(String.init) ?? "?", 4, left: true))  \(pad(ivs, 9)) \(pad(level, 6)) \(pad(String(r.frames.count), 4, left: true))    \(r.flags.joined(separator: " "))")
    }
    print("\(result.rows.count) rows from \(loaded.readings.count) readings; \(result.review.count) flagged; \(result.unmatched.count) unmatched")
    if let r = refined {
        print("base rows \(r.baseRowCount) / refined rows \(result.rows.count) (\(loaded.ticks.count) swipe ticks)")
        for c in r.changes { print("  refined #\(c.rowIndex) \(c.kind.rawValue): \(c.detail)") }
        for n in r.notices { print("  notice: \(n)") }
    }
    let peakMB = MemoryProbe.megabytes(probe.peakBytes), baseMB = MemoryProbe.megabytes(baseline)
    print(String(format: "time: load %.2f s, finish %.2f s | footprint: baseline %.1f MB, peak %.1f MB", tLoad, tFinish, baseMB, peakMB))

    if let csvPath {
        try Data(try engine.csv(rows: result.rows).utf8).write(to: URL(fileURLWithPath: csvPath), options: .atomic)
        err("wrote \(csvPath)")
    }
    if let jsonPath {
        struct Out: Encodable { var input: String; var frames: Int; var rows: [ScanRow]; var rowCount: Int; var flagged: Int; var review: [ReviewEntry]; var unmatched: [Unmatched] }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let out = Out(input: input, frames: loaded.readings.count, rows: result.rows, rowCount: result.rows.count, flagged: result.review.count, review: result.review, unmatched: result.unmatched)
        try enc.encode(out).write(to: URL(fileURLWithPath: jsonPath), options: .atomic)
        err("wrote \(jsonPath)")
    }
    if diff {
        print("\n" + GrouperDiff.compute(refined: result.rows, readings: loaded.readings, ticks: loaded.ticks).report())
    }
    if advise {
        let t2 = Date()
        let report = try engine.advise(rows: result.rows)
        let tAdvise = Date().timeIntervalSince(t2)
        probe.sample()
        let builds = report["builds"]?.arrayValue ?? [], gaps = report["gaps"]?.arrayValue ?? [], hygiene = report["hygiene"]?.arrayValue ?? []
        print("\nadvisor: \(builds.count) builds, \(gaps.count) gaps, \(hygiene.count) duplicate species (\(String(format: "%.2f", tAdvise)) s, peak footprint now \(String(format: "%.1f", MemoryProbe.megabytes(probe.peakBytes))) MB)")
        for (i, b) in builds.prefix(10).enumerated() {
            guard case .object = b, case .object(let p)? = b["pokemon"] else { continue }
            func s(_ v: JSONValue?) -> String { if case .string(let x)? = v { return x }; if case .number(let n)? = v { return String(Int(n)) }; return "?" }
            print("  \(i + 1). \(s(p["name"])) CP \(s(p["cp"])) -> \(s(b["targetName"])) (score \(s(b["score"])))")
        }
    }
} catch {
    die("pogo-rows: \(error.localizedDescription)", code: 1)
}
