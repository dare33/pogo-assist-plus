import Foundation
import PogoReader

// What the JavaScript `finish()` returns, decoded. Every field of a row is kept (see
// src/extract/pipeline.js: resolveRow / collapseRun), so a row can be handed back to the JavaScript
// (the CSV, a clip merge) unchanged. A field the JS writes as null is an optional here and is encoded
// back as null, not omitted: toPokeGenieCsv tests `r.level !== null`.

/// Which frames a row was voted from, as the JS keeps them (frame label, time, the reads on that frame).
public struct FrameLabel: Codable, Equatable {
    public var frame: String?
    public var time: Double?
    public var cp: Int?
    public var cpText: String?
    public var name: String?
    /// "167/167" as the JS prints it, or nil when no HP was read on that frame.
    public var hp: String?
    /// "15/15/14", or nil.
    public var ivs: String?
    public var ivConfidence: Double?
    public var sharpness: Double?
    /// Set by a clip merge (batch.js) on the frames of a joined row.
    public var clip: String?
}

/// One Pokémon. `ivs` are what the solver settled on; `ivsRead` what the bars said; `ivsGuess` the
/// solver's guess when the bars did not settle.
public struct ScanRow: Codable, Equatable {
    public var index: Int
    public var name: String
    public var display: String
    public var form: String
    public var speciesId: String
    public var dex: Int?
    public var cp: Int
    public var hp: Int?
    public var ivs: IVs?
    public var ivsRead: IVs?
    public var ivsGuess: IVs?
    public var level: Double?
    public var levelMax: Double?
    public var dust: Int?
    /// "exact", "corrected", ... (solve.js).
    public var solveStatus: String
    public var flags: [String]
    public var frames: [FrameLabel]
    /// How many runs `dedupeAdjacent` joined into this row (absent on a row that was not joined).
    public var merged: Int?
    /// Set only by a clip merge: 1 shadow, 2 purified.
    public var shadow: Int?
    /// Set only by a clip merge: the clip the row came from.
    public var clip: String?

    public init(index: Int, name: String, display: String, form: String, speciesId: String, dex: Int?, cp: Int, hp: Int?, ivs: IVs?, ivsRead: IVs?,
                ivsGuess: IVs?, level: Double?, levelMax: Double?, dust: Int?, solveStatus: String, flags: [String], frames: [FrameLabel],
                merged: Int? = nil, shadow: Int? = nil, clip: String? = nil) {
        self.index = index; self.name = name; self.display = display; self.form = form; self.speciesId = speciesId; self.dex = dex; self.cp = cp
        self.hp = hp; self.ivs = ivs; self.ivsRead = ivsRead; self.ivsGuess = ivsGuess; self.level = level; self.levelMax = levelMax; self.dust = dust
        self.solveStatus = solveStatus; self.flags = flags; self.frames = frames; self.merged = merged; self.shadow = shadow; self.clip = clip
    }

    private enum Key: String, CodingKey {
        case index, name, display, form, speciesId, dex, cp, hp, ivs, ivsRead, ivsGuess, level, levelMax, dust
        case solveStatus, flags, frames, merged, shadow, clip
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(index, forKey: .index)
        try c.encode(name, forKey: .name)
        try c.encode(display, forKey: .display)
        try c.encode(form, forKey: .form)
        try c.encode(speciesId, forKey: .speciesId)
        try c.encode(dex, forKey: .dex)
        try c.encode(cp, forKey: .cp)
        try c.encode(hp, forKey: .hp)
        try c.encode(ivs, forKey: .ivs)
        try c.encode(ivsRead, forKey: .ivsRead)
        try c.encode(ivsGuess, forKey: .ivsGuess)
        try c.encode(level, forKey: .level)
        try c.encode(levelMax, forKey: .levelMax)
        try c.encode(dust, forKey: .dust)
        try c.encode(solveStatus, forKey: .solveStatus)
        try c.encode(flags, forKey: .flags)
        try c.encode(frames, forKey: .frames)
        try c.encodeIfPresent(merged, forKey: .merged)
        try c.encodeIfPresent(shadow, forKey: .shadow)
        try c.encodeIfPresent(clip, forKey: .clip)
    }
}

extension ScanRow {
    /// The flags that ask for a look in the game, and the ones that only record how the row was read (see `FlagInfo.Severity`).
    public var checkFlags: [String] { FlagInfo.checkFlags(flags, solveStatus: solveStatus) }
    public var noteFlags: [String] { FlagInfo.noteFlags(flags, solveStatus: solveStatus) }
    /// The row belongs in "To check": it has at least one `check` flag.
    public var needsCheck: Bool { !checkFlags.isEmpty }
}

/// A flagged row, as `finish()` lists them for review (the row's reads without its solver fields).
public struct ReviewEntry: Codable, Equatable {
    public var index: Int
    public var name: String
    public var cp: Int
    public var hp: Int?
    public var ivs: IVs?
    public var ivsRead: IVs?
    public var ivsGuess: IVs?
    public var level: Double?
    public var levelMax: Double?
    public var flags: [String]
    public var frames: [FrameLabel]
    public var clip: String?
    public var shadow: Int?
}

/// A Pokémon that was on screen and did not become a row: a CP with no readable name (`name-not-read`),
/// a named Pokémon whose CP was never read (`cp-not-read`, with the CPs its HP and bars allow in
/// `cpOptions`), a one-frame row folded into its neighbour (`absorbed`, `into` is that CP), or a stretch of card-less readings under command paging that lasted whole periods
/// (`blank-card`: `count` cards, between the rows with CP `cpBefore` and `cpAfter`; see `BlankCards`).
public struct Unmatched: Codable, Equatable {
    public var frame: String?
    public var cp: Int?
    public var name: String?
    public var nameText: String?
    public var hp: Int?
    public var ivs: IVs?
    public var cpOptions: [Int]?
    public var frames: Int?
    public var reason: String
    public var into: Int?
    public var clip: String?
    /// `blank-card` only: how many cards the stretch lasted (a whole number of periods) and the CPs of the rows before and after it. Optional, so a scan saved before they existed still decodes.
    public var count: Int?
    public var cpBefore: Int?
    public var cpAfter: Int?
}

public struct ScanResult: Codable, Equatable {
    public var rows: [ScanRow]
    public var review: [ReviewEntry]
    public var unmatched: [Unmatched]

    public init(rows: [ScanRow], review: [ReviewEntry], unmatched: [Unmatched]) {
        self.rows = rows; self.review = review; self.unmatched = unmatched
    }
}

/// Free-form JSON for the calls that pass through (clip merge output, the advisor's report), whose
/// shape is the JavaScript's and is not mirrored in Swift.
public enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a } else { return nil } }
}

/// One clip for `CoreEngine.mergeClips` (batch.js): `kind` is "normal", "shadow" or "purified".
public struct ClipInput: Codable, Equatable {
    public var name: String
    public var kind: String
    public var rows: [ScanRow]
    public var unmatched: [Unmatched]
    public init(name: String, kind: String = "normal", rows: [ScanRow], unmatched: [Unmatched] = []) {
        self.name = name; self.kind = kind; self.rows = rows; self.unmatched = unmatched
    }
}
