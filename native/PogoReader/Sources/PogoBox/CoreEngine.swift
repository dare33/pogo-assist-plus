import Foundation
import JavaScriptCore
import PogoReader

/// The project's JavaScript (grouping, voting, the level/IV solver, the Poke Genie CSV, clip joining,
/// the advisor) running in a `JSContext`. The script is `Resources/pogo-core.js`, generated from the
/// JavaScript sources by `native/tools/build-js-bundle.mjs`; nothing here re-implements any of it.
///
/// Thread confinement: a `JSContext` must be used from one thread at a time and this class does no
/// locking. Create the engine on, and use it from, one queue or actor (the app should give it its own
/// serial queue: `finish` takes seconds on a large box). It is deliberately not `Sendable`.
///
/// The script and the three data files (about 2 MB of JSON) are loaded once, on first use. Readings go
/// to JavaScript as JSON text and results come back as JSON text, so no Swift object is bridged.
public final class CoreEngine {
    public enum Failure: Error, LocalizedError, Equatable {
        case resourceMissing(String)
        /// An exception thrown inside the JavaScript. `line` is the line in pogo-core.js when JSC gives one.
        case script(message: String, line: Int?)
        case badResult(String)

        public var errorDescription: String? {
            switch self {
            case .resourceMissing(let n): return "app core resource missing: \(n)"
            case .script(let m, let l): return "JavaScript error: \(m)" + (l.map { " (pogo-core.js line \($0))" } ?? "")
            case .badResult(let m): return "unexpected result from the JavaScript: \(m)"
            }
        }
    }

    private let scriptURL: URL?
    private let dataURLs: (gamemaster: URL, tiers: URL, rankings: URL)?
    private var context: JSContext?
    private var pendingException: (String, Int?)?

    /// `scriptURL` / `dataDirectory` default to the PogoBox resources. Passing them lets a test load a
    /// broken script; the data directory must hold gamemaster.json, tiers.json, pvp-rankings.json.
    public init(scriptURL: URL? = nil, dataDirectory: URL? = nil) {
        self.scriptURL = scriptURL
        if let d = dataDirectory {
            dataURLs = (d.appendingPathComponent("gamemaster.json"), d.appendingPathComponent("tiers.json"), d.appendingPathComponent("pvp-rankings.json"))
        } else { dataURLs = nil }
    }

    // MARK: - API

    /// Load the script and data now instead of on first use (to time it, or to do it off the main path).
    public func prepare() throws { _ = try ready() }

    /// Group, vote, solve, dedupe and flag a scan's frame readings (JS `finish`).
    public func finish(readings: [FrameReading]) throws -> ScanResult {
        let text = try call("finishJSON", [try Self.json(readings)])
        return try Self.decode(ScanResult.self, text)
    }

    /// The scan as a Poke Genie CSV (JS `toPokeGenieCsv`). `scanDate` goes into the two scan-date columns,
    /// shown in the device's time zone to the minute.
    public func csv(rows: [ScanRow], scanDate: Date = Date()) throws -> String {
        try call("csvJSON", [try Self.json(rows), scanDate.timeIntervalSince1970 * 1000])
    }

    /// Join several clips of one box into one (batch.js `mergeClips`); the result is passed through as JSON:
    /// `rows`, `review`, `unmatched`, `boundaries`, `reconciled`, `clips`.
    public func mergeClips(_ clips: [ClipInput], maxOverlap: Int? = nil) throws -> JSONValue {
        let options = maxOverlap.map { "{\"maxOverlap\":\($0)}" }
        let text = try call("mergeClipsJSON", [try Self.json(clips)] + (options.map { [$0] } ?? []))
        return try Self.decode(JSONValue.self, text)
    }

    /// The advisor's report (advise.js `analyseBox`) for a box in `importPokeGenie`'s record shape,
    /// passed through as JSON: `builds`, `gaps`, `hygiene`, `pokemon`, `areaLabel`.
    public func advise(box: JSONValue) throws -> JSONValue {
        let text = try call("adviseJSON", [try Self.json(box)])
        return try Self.decode(JSONValue.self, text)
    }

    /// Advise on a Poke Genie CSV (what `scripts/advise.mjs` does: import it, then analyse).
    public func advise(csv: String) throws -> JSONValue {
        let box = try Self.decode(JSONValue.self, try call("importPokeGenieJSON", [csv]))
        return try advise(box: box)
    }

    /// Advise on a scan's rows by the same route as the CLI: through the Poke Genie CSV.
    public func advise(rows: [ScanRow], scanDate: Date = Date()) throws -> JSONValue {
        try advise(csv: try csv(rows: rows, scanDate: scanDate))
    }

    /// A Poke Genie CSV read back into records (JS `importPokeGenie`), as JSON.
    public func importPokeGenie(csv: String) throws -> JSONValue {
        try Self.decode(JSONValue.self, try call("importPokeGenieJSON", [csv]))
    }

    // MARK: - JavaScriptCore plumbing

    private func ready() throws -> JSContext {
        if let c = context { return c }
        guard let ctx = JSContext() else { throw Failure.badResult("no JSContext") }
        ctx.exceptionHandler = { [weak self] _, exception in
            guard let self, let e = exception else { return }
            let line = e.objectForKeyedSubscript("line")
            self.pendingException = (e.toString() ?? "unknown exception", (line?.isNumber ?? false) ? Int(line!.toInt32()) : nil)
        }
        let script = try resource(scriptURL, "pogo-core", "js")
        _ = ctx.evaluateScript(try String(contentsOf: script, encoding: .utf8), withSourceURL: script)
        try raiseIfThrown()
        let core = ctx.objectForKeyedSubscript("PogoCore")
        guard let core, core.isObject else { throw Failure.badResult("pogo-core.js did not define PogoCore") }
        let gm = try resource(dataURLs?.gamemaster, "gamemaster", "json"), tiers = try resource(dataURLs?.tiers, "tiers", "json"), ranks = try resource(dataURLs?.rankings, "pvp-rankings", "json")
        _ = core.invokeMethod("load", withArguments: [try String(contentsOf: gm, encoding: .utf8), try String(contentsOf: tiers, encoding: .utf8), try String(contentsOf: ranks, encoding: .utf8)])
        try raiseIfThrown()
        context = ctx
        return ctx
    }

    private func resource(_ override: URL?, _ name: String, _ ext: String) throws -> URL {
        if let o = override {
            guard FileManager.default.fileExists(atPath: o.path) else { throw Failure.resourceMissing(o.path) }
            return o
        }
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else { throw Failure.resourceMissing("\(name).\(ext)") }
        return url
    }

    private func raiseIfThrown() throws {
        if let (m, l) = pendingException {
            pendingException = nil
            context?.exception = nil
            throw Failure.script(message: m, line: l)
        }
    }

    private func call(_ function: String, _ args: [Any]) throws -> String {
        let ctx = try ready()
        let core = ctx.objectForKeyedSubscript("PogoCore")
        let result = core?.invokeMethod(function, withArguments: args)
        try raiseIfThrown()
        guard let result, result.isString, let s = result.toString() else { throw Failure.badResult("\(function) returned no text") }
        return s
    }

    private static func json<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        do { return try JSONDecoder().decode(type, from: Data(text.utf8)) }
        catch { throw Failure.badResult("\(error)") }
    }
}
