import Foundation
import CoreVideo
import PogoReader

// pogo-read: read Pokémon GO detail-screen frames with the same code the broadcast extension runs.
//
//   pogo-read <dir of PNG frames | single PNG> [--width N | --full] [--fps 5] --out readings.json
//             [--rows rows.json] [--via-pixelbuffer] [--range video|full] [--verbose] [--deferred]
//   pogo-read --synthetic N [same options]      N drawn full-size frames, via pixel buffers

struct Options {
    var input: String?
    var synthetic: Int?
    var width: Int? = 750
    var fps = 5.0
    var out: String?
    var rows: String?
    var viaPixelBuffer = false
    var fullRangeBuffers = false
    var verbose = false
    var saveSynthetic: String?
    var fast = false
    var noVision = false
    var cpPadding: Double?
    var cpDigitsOnly = false
    var deferred = false
    var noSwipeTicks = false
    var visionDevice = VisionOptions.Device.system
    var visionMinTextHeight: Float?
    var visionRecreate = false
    var limit: Int?
}

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    usage: pogo-read <dir of PNG frames | single PNG> [--width N | --full] [--fps 5] --out readings.json [--rows rows.json] [--via-pixelbuffer] [--range video|full] [--verbose] [--deferred]
           pogo-read --synthetic N [--width N | --full] [--out readings.json] [--rows rows.json] [--verbose] [--save-synthetic DIR]

    """.utf8))
    exit(2)
}

func parse() -> Options {
    var o = Options()
    var args = Array(CommandLine.arguments.dropFirst())[...]
    func value() -> String { guard let v = args.popFirst() else { usage() }; return v }
    while let a = args.popFirst() {
        switch a {
        case "--width": guard let n = Int(value()), n > 0 else { usage() }; o.width = n
        case "--full": o.width = nil
        case "--fps": guard let f = Double(value()), f > 0 else { usage() }; o.fps = f
        case "--out": o.out = value()
        case "--rows": o.rows = value()
        case "--via-pixelbuffer": o.viaPixelBuffer = true
        case "--range": let r = value(); guard r == "video" || r == "full" else { usage() }; o.fullRangeBuffers = r == "full"
        case "--synthetic": guard let n = Int(value()), n > 0 else { usage() }; o.synthetic = n; o.viaPixelBuffer = true
        case "--verbose": o.verbose = true
        case "--vision-fast": o.fast = true
        case "--no-vision": o.noVision = true
        case "--cp-padding": guard let x = Double(value()) else { usage() }; o.cpPadding = x
        case "--cp-digits-only": o.cpDigitsOnly = true
        case "--deferred": o.deferred = true
        case "--no-swipe-ticks": o.noSwipeTicks = true
        case "--vision-device": guard let d = VisionOptions.Device(rawValue: value()) else { usage() }; o.visionDevice = d
        case "--vision-min-text-height": guard let h = Float(value()) else { usage() }; o.visionMinTextHeight = h
        case "--vision-recreate": o.visionRecreate = true
        case "--limit": guard let n = Int(value()), n > 0 else { usage() }; o.limit = n
        case "--save-synthetic": o.saveSynthetic = value()
        default:
            if a.hasPrefix("--") || o.input != nil { usage() }
            o.input = a
        }
    }
    if o.input == nil && o.synthetic == nil { usage() }
    if o.input != nil && o.synthetic != nil { usage() }
    if o.synthetic == nil && o.out == nil { usage() }
    return o
}

/// Reads nothing: isolates the memory of scaling and the pixel routines from Vision's.
final class EmptyTextReader: TextReader {
    func read(_ image: RGBAImage, kind: TextKind) -> TextRead { .empty }
}

struct Report: Encodable {
    struct Memory: Encodable { var peakFootprintMB: Double; var baselineMB: Double; var finalFootprintMB: Double }
    struct Ms: Encodable { var mean: Double; var worst: Double }
    var frames: Int
    var width: Int?
    var viaPixelBuffer: Bool
    var readings: [FrameReading]
    var rows: [LiveRow]
    var memory: Memory
    var msPerFrame: Ms
    /// `--deferred` only: the "save crops" path (extension half, then the app's read).
    struct Deferred: Encodable {
        var savedFrames: Int; var files: Int; var bytes: Int
        var extensionPeakFootprintMB: Double; var extensionBaselineMB: Double
        var appReadPeakFootprintMB: Double; var appReadMs: Double
    }
    var deferred: Deferred?
    /// The swipe signature's difference from the previous frame, per frame (nil for the first). Replayed by pogo-drop.
    var signatureDiffs: [Double?]
}

func run() throws {
    let o = parse()
    let table = try SpeciesTable.bundled()
    let names = displayNames(table)
    let probe = MemoryProbe()
    var vopts = VisionOptions()
    vopts.fast = o.fast; vopts.device = o.visionDevice; vopts.minimumTextHeight = o.visionMinTextHeight; vopts.recreateRequestEachRead = o.visionRecreate
    // --deferred: the extension half only (no Vision request is ever created); Vision runs afterwards.
    let processor = o.deferred
        ? FrameProcessor.cropsOnly(names: names, targetWidth: o.width, memory: probe)
        : FrameProcessor(textReader: o.noVision ? EmptyTextReader() : VisionTextReader(options: vopts), names: names, targetWidth: o.width, memory: probe)
    let archive = o.deferred ? CropArchive(directory: FileManager.default.temporaryDirectory.appendingPathComponent("pogo-deferred-\(getpid())")) : nil
    var saver = CropSaver()
    var detector = SwipeDetector()
    var ticker = SwipeTicker()
    var signatureDiffs = [Double?]()
    if let p = o.cpPadding { processor.reader.cpPadding = p }
    if o.cpDigitsOnly { processor.reader.cpIncludesPrefix = false }
    var grouper = LiveGrouper(species: table)
    let maker = Pixel420Maker(fullRange: o.fullRangeBuffers)

    // Frame source: PNG paths, or the synthetic generator (one reused full-size RGBA canvas).
    let paths = try o.input.map(pngPaths) ?? []
    let total = o.synthetic ?? min(paths.count, o.limit ?? Int.max)
    if total == 0 { throw ToolError.message("no PNG frames in \(o.input ?? "")") }
    var canvas = RGBAImage(width: o.synthetic != nil ? 1320 : 0, height: o.synthetic != nil ? 2868 : 0)

    var readings = [FrameReading]()
    var msTotal = 0.0, msWorst = 0.0
    var deferredRows: [LiveRow]?
    // Baseline: after the tool's own buffers exist, before the first frame is read.
    if o.synthetic != nil { _ = try maker.make(from: canvas) }
    let baseline = MemoryProbe.footprintBytes()
    probe.resetPeak()

    for i in 0..<total {
        let label: String
        var image: RGBAImage? = nil
        var buffer: CVPixelBuffer? = nil
        if o.synthetic != nil {
            SyntheticScreen.draw(into: &canvas, SyntheticScreen.spec(frame: i))
            buffer = try maker.make(from: canvas)
            label = String(format: "synthetic-%05d", i + 1)
            if let dir = o.saveSynthetic { try writePNG(canvas, to: URL(fileURLWithPath: dir).appendingPathComponent(label + ".png")) }
        } else {
            label = paths[i].lastPathComponent
            // Decoded, converted, and released before the timed read, so the footprint sampled
            // during the read is the reader's, not the tool's frame loading.
            try autoreleasepool {
                let decoded = try decodePNG(paths[i])
                if o.viaPixelBuffer { buffer = try maker.make(from: decoded) } else { image = decoded }
            }
        }
        let time = Double(i) / o.fps
        // The swipe signature of every frame, as the extension computes it in its callback.
        let diff = buffer.map { detector.feed($0) } ?? detector.feed(image!)
        signatureDiffs.append(diff)
        if let tick = ticker.feed(diff: diff, time: time), !o.noSwipeTicks { grouper.swipe(at: tick); saver.noteSwipe(at: tick) }
        let t0 = DispatchTime.now().uptimeNanoseconds
        var reading = FrameReading(frame: label, time: time)
        if let archive = archive {
            // The extension's work in "save crops" mode: pixels only, then maybe write the crops.
            var (a, crops) = buffer.map { processor.analyse($0, time: time, frame: label) } ?? processor.analyse(image!, time: time, frame: label)
            if saver.shouldSave(&a), let c = crops { archive.save(a, c); probe.sample() }
            reading.flags = a.flags
        } else if let b = buffer { reading = processor.process(b, time: time, frame: label) }
        else { reading = processor.process(image!, time: time, frame: label) }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
        msTotal += ms; msWorst = max(msWorst, ms)
        if archive == nil { readings.append(reading); grouper.add(reading) }
        if o.verbose {
            FileHandle.standardError.write(Data("\(label) \(String(format: "%.0f", ms)) ms  cp=\(reading.cp.map(String.init) ?? "-") name=\(reading.name ?? "-") (\(reading.nameText) @\(Int(reading.nameConfidence))) hp=\(reading.hp.map { "\($0.current)/\($0.max)" } ?? "-") ivs=\(reading.ivs.map { "\($0.atk)/\($0.def)/\($0.hp)" } ?? "-") \(reading.flags.joined(separator: ","))\n".utf8))
        }
    }
    var deferredInfo: Report.Deferred?
    if let archive = archive {
        // The app's half: Vision on the saved crops, then the grouper.
        let extPeak = probe.peakBytes
        let files = archive.fileCount, bytes = archive.byteCount, savedFrames = archive.frameCount
        let appProbe = MemoryProbe()
        appProbe.resetPeak()
        let reader = FrameReader(text: VisionTextReader(options: vopts), names: names)
        let t0 = DispatchTime.now().uptimeNanoseconds
        let result = DeferredRun.readAndGroup(archive: archive, reader: reader, species: table)
        appProbe.sample()
        readings = result.readings
        deferredRows = result.rows
        deferredInfo = .init(savedFrames: savedFrames, files: files, bytes: bytes, extensionPeakFootprintMB: MemoryProbe.megabytes(extPeak), extensionBaselineMB: MemoryProbe.megabytes(baseline),
                             appReadPeakFootprintMB: MemoryProbe.megabytes(appProbe.peakBytes), appReadMs: Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
        try? FileManager.default.removeItem(at: archive.directory)
    }
    grouper.finish()
    let final = MemoryProbe.footprintBytes()
    let report = Report(frames: total, width: o.width, viaPixelBuffer: o.viaPixelBuffer, readings: readings, rows: deferredRows ?? grouper.rows,
                        memory: .init(peakFootprintMB: MemoryProbe.megabytes(probe.peakBytes), baselineMB: MemoryProbe.megabytes(baseline), finalFootprintMB: MemoryProbe.megabytes(final)),
                        msPerFrame: .init(mean: msTotal / Double(total), worst: msWorst), deferred: deferredInfo, signatureDiffs: signatureDiffs)
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    if let out = o.out { try enc.encode(report).write(to: URL(fileURLWithPath: out)) }
    if let rowsPath = o.rows { try enc.encode(report.rows).write(to: URL(fileURLWithPath: rowsPath)) }

    let named = readings.filter { $0.name != nil && $0.cp != nil }.count
    func f(_ v: Double) -> String { String(format: "%.1f", v) }
    print("frames \(total), name+CP read on \(named), rows \(report.rows.count)")
    print("width \(o.width.map(String.init) ?? "full"), via \(o.viaPixelBuffer ? "pixel buffer (420 \(o.fullRangeBuffers ? "full" : "video") range)" : "RGBA")")
    print("footprint: baseline \(f(report.memory.baselineMB)) MB, peak \(f(report.memory.peakFootprintMB)) MB (+\(f(report.memory.peakFootprintMB - report.memory.baselineMB)) over baseline), final \(f(report.memory.finalFootprintMB)) MB")
    if let d = report.deferred {
        print("save-crops: \(d.savedFrames) frames saved (\(d.files) files, \(f(Double(d.bytes) / 1_048_576)) MB); extension half peak \(f(d.extensionPeakFootprintMB)) MB (+\(f(d.extensionPeakFootprintMB - d.extensionBaselineMB)) over baseline); app read peak \(f(d.appReadPeakFootprintMB)) MB in \(f(d.appReadMs / 1000)) s")
    }
    print("ms per frame: mean \(f(report.msPerFrame.mean)), worst \(f(report.msPerFrame.worst))")
}

do { try run() } catch { FileHandle.standardError.write(Data("pogo-read: \(error)\n".utf8)); exit(1) }
