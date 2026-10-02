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

    public init(id: String = UUID().uuidString, row: ScanRow, firstSeen: Date, lastSeen: Date, corrections: Corrections = Corrections(), megaWhenScanned: Bool? = nil) {
        self.id = id; self.row = Self.stripped(row); self.firstSeen = firstSeen; self.lastSeen = lastSeen; self.corrections = corrections; self.megaWhenScanned = megaWhenScanned
    }

    public var isHandCorrected: Bool { !corrections.isEmpty }
    /// Flags remain that need a look in the game (a hand correction or "mark as checked" removes them).
    public var needsCheck: Bool { !row.flags.isEmpty }

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
