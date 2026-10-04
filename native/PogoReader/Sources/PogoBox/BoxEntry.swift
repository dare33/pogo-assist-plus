import Foundation
import PogoReader

/// A value a person typed over a read one. `was` is what the scan had read there (nil when it had read nothing), kept
/// so a later scan that reads the same wrong value again does not undo the correction (see `BoxMerge`).
public struct Fix<T: Codable & Equatable>: Codable, Equatable {
    public var was: T?
    public init(was: T?) { self.was = was }
}

/// Which values of an entry were corrected by hand.
public struct Corrections: Codable, Equatable {
    public var cp: Fix<Int>?
    public var hp: Fix<Int>?
    public var ivs: Fix<IVs>?
    /// `was` is the species id the scan had read.
    public var species: Fix<String>?
    public init(cp: Fix<Int>? = nil, hp: Fix<Int>? = nil, ivs: Fix<IVs>? = nil, species: Fix<String>? = nil) {
        self.cp = cp; self.hp = hp; self.ivs = ivs; self.species = species
    }
    public var isEmpty: Bool { cp == nil && hp == nil && ivs == nil && species == nil }
}

/// The Mega (or Primal) form of a box entry: the values its own scan read while it was Mega evolved. The entry's own values (its base form) and its IVs stay the entry's: a Mega has its
/// base's IVs. Optional on `BoxEntry`, so a box written without any decodes and encodes exactly as before. CP 0 means "not known", as in `ScanRow`.
public struct MegaForm: Codable, Equatable {
    /// The Mega species id (`staraptor_mega`) and its name, display name, form and dex as the scan read them.
    public var speciesId: String
    public var name: String
    public var display: String
    public var form: String
    public var dex: Int?
    public var cp: Int
    public var hp: Int?
    public var level: Double?
    public var levelMax: Double?
    public var dust: Int?
    public var firstSeen: Date
    public var lastSeen: Date

    public init(speciesId: String, name: String, display: String, form: String, dex: Int?, cp: Int, hp: Int?, level: Double?, levelMax: Double?, dust: Int?, firstSeen: Date, lastSeen: Date) {
        self.speciesId = speciesId; self.name = name; self.display = display; self.form = form; self.dex = dex; self.cp = cp; self.hp = hp
        self.level = level; self.levelMax = levelMax; self.dust = dust; self.firstSeen = firstSeen; self.lastSeen = lastSeen
    }
    /// The Mega values of a row, first and last seen at the given dates.
    public init(row r: ScanRow, firstSeen: Date, lastSeen: Date) {
        self.init(speciesId: r.speciesId, name: r.name, display: r.display, form: r.form, dex: r.dex, cp: r.cp, hp: r.hp, level: r.level, levelMax: r.levelMax, dust: r.dust, firstSeen: firstSeen, lastSeen: lastSeen)
    }
}

/// One Pokémon in a saved box. The game shows no id, so the app keeps its own: `id` is made when the Pokémon is first
/// saved and never changes, through power-ups, evolutions and hand corrections.
public struct BoxEntry: Codable, Equatable, Identifiable {
    public var id: String
    /// The current values. `frames` is always empty here (the frame labels of one scan mean nothing later); the
    /// scan's own file keeps them.
    public var row: ScanRow
    public var firstSeen: Date
    public var lastSeen: Date
    public var corrections = Corrections()
    /// The latest scan that saw this Pokémon found it Mega (or Primal) evolved. Its values were not saved from that scan: the
    /// Mega CP is temporary. nil or false when the latest scan saw it in its own form.
    public var megaWhenScanned: Bool?
    /// The Mega form's own values, when a scan has read this Pokémon Mega evolved (or a box held it as a second, Mega entry that was joined to this one). `row` stays the base form. One
    /// entry with a Mega form is one Pokémon everywhere: the box count, advice and the CSV use `row` once.
    public var megaForm: MegaForm?

    public init(id: String = UUID().uuidString, row: ScanRow, firstSeen: Date, lastSeen: Date, corrections: Corrections = Corrections(), megaWhenScanned: Bool? = nil, megaForm: MegaForm? = nil) {
        self.id = id; self.row = Self.stripped(row); self.firstSeen = firstSeen; self.lastSeen = lastSeen; self.corrections = corrections; self.megaWhenScanned = megaWhenScanned; self.megaForm = megaForm
    }

    public var isHandCorrected: Bool { !corrections.isEmpty }
    /// A `check` flag remains that needs a look in the game (a hand correction or "These values are right" removes it). Notes do not count.
    public var needsCheck: Bool { row.needsCheck }

    static func stripped(_ row: ScanRow) -> ScanRow { var r = row; r.frames = []; return r }

    /// The species as a comparison key (the id names the form too).
    public var speciesKey: String { row.speciesId }
}

extension ScanRow {
    /// The species as a comparison key (the id names the form too).
    var speciesKey: String { speciesId }

    /// Name with form in brackets, for display ("Zamazenta (Hero)").
    public var title: String { form.isEmpty || form == "Normal" ? name : "\(name) (\(form))" }
}
