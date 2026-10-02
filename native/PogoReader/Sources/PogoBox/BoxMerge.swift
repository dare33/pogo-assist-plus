import Foundation
import PogoReader

/// Adding a scan to a saved box. Pure: `plan` reads the saved entries and the scanned rows and returns a value for the
/// review screen; `apply` is a separate step that returns the new entries. Nothing here touches disk.
///
/// The game shows no unique id for a Pokémon, so a scanned Pokémon is matched to a saved one by what a power-up or an
/// evolution does not change. In this order, each rule on what the earlier rules left over:
///
///  1. Unchanged: same species and form, same three IVs, same CP.
///  2. Powered up: same species and form, same IVs, higher CP.
///  3. Evolved: the scanned species is a later stage of the saved species (game master family data), same IVs.
///  4. IVs unread: when either side has no IVs, same species and form, same CP and same HP. (Decision: "no IVs on either
///     side" is read as "at least one side", because a Pokémon whose bars failed to read this time is the common case.)
///  5. Identical twins: matched by count. Two saved and two scanned are two unchanged; a third scanned is new.
///  6. Ambiguous: a scanned Pokémon with more than one saved candidate (or the reverse) at the same rule, where the
///     candidates are not interchangeable, is never guessed. It is "unsure" and the person picks.
///
/// A full scan proposes saved entries matched by nothing as gone; an add-and-update scan removes nothing. Entries that are
/// candidates in an unsure match are never proposed as gone (they might be one of the unsure Pokémon).
///
/// Hand corrections. A corrected field remembers the value the scan had read (`Fix.was`). A later scan that reads that
/// same value again, or the corrected value, leaves the correction in place; a scan that reads anything else (the Pokémon
/// really changed) replaces the value and drops that correction. The old wrong read also counts as a match when pairing, so
/// the corrected entry still pairs with the scan that keeps reading the old value. For the IVs a scan that read no IVs also
/// leaves the correction alone. The level and dust follow the IVs: taken from the scan unless the IVs are a kept correction.
public enum BoxMerge {
    public enum UpdateReason: String, Codable, Equatable {
        case poweredUp, evolved
        /// Rule 4: the saved entry had no IVs and the scan read them.
        case ivsNowRead
        /// The person chose this saved entry for an unsure Pokémon and its values differ.
        case chosen
    }

    public struct Update: Equatable {
        /// Position of the row in `MergePlan.scanned`.
        public var scanned: Int
        public var savedId: String
        public var reason: UpdateReason
    }

    public struct Pair: Equatable {
        public var scanned: Int
        public var savedId: String
    }

    /// A scanned Pokémon that could be more than one saved one. `candidates` are saved ids, never empty.
    public struct Unsure: Equatable {
        public var scanned: Int
        public var candidates: [String]
    }

    public struct Plan: Equatable {
        public var kind: BoxStore.Kind
        public var scanDate: Date
        public var scanned: [ScanRow]
        /// Positions in `scanned` of Pokémon not in the saved box.
        public var new: [Int]
        public var updated: [Update]
        public var same: [Pair]
        public var unsure: [Unsure]
        /// Saved ids proposed as gone: always empty for an add-and-update scan.
        public var gone: [String]

        public var isUnresolvedFree: Bool { unsure.isEmpty }
    }

    public enum Resolution: Equatable {
        case existing(String)
        case new
    }

    public enum Failure: Error, LocalizedError, Equatable {
        case unresolved(Int)
        case notACandidate(scanned: Int, savedId: String)
        case chosenTwice(savedId: String)
        public var errorDescription: String? {
            switch self {
            case .unresolved(let n): return "\(n) unsure Pokémon still need an answer."
            case .notACandidate: return "That saved Pokémon is not one of the choices for this one."
            case .chosenTwice: return "Two scanned Pokémon were matched to the same saved one. Pick \"New\" for one of them."
            }
        }
    }

    // MARK: - plan

    public static func plan(scanned rows: [ScanRow], into saved: [BoxEntry], kind: BoxStore.Kind, scanDate: Date, gameMaster gm: GameMaster) -> Plan {
        var sPool = Array(rows.indices)
        var vPool = Array(saved.indices)
        var plan = Plan(kind: kind, scanDate: scanDate, scanned: rows, new: [], updated: [], same: [], unsure: [], gone: [])
        var unsureSaved = Set<Int>()

        func record(_ ruleIndex: Int, _ si: Int, _ vi: Int) {
            let s = rows[si], v = saved[vi], id = v.id
            switch ruleIndex {
            case 0: plan.same.append(Pair(scanned: si, savedId: id))
            case 1: plan.updated.append(Update(scanned: si, savedId: id, reason: .poweredUp))
            case 2: plan.updated.append(Update(scanned: si, savedId: id, reason: .evolved))
            default:
                if v.row.ivs == nil && s.ivs != nil { plan.updated.append(Update(scanned: si, savedId: id, reason: .ivsNowRead)) }
                else { plan.same.append(Pair(scanned: si, savedId: id)) }
            }
            sPool.removeAll { $0 == si }
            vPool.removeAll { $0 == vi }
        }

        // Rule 1 (with 5: twins by count), 2, 3, then 4. Each takes what the one before left.
        let rules: [(ScanRow, BoxEntry) -> Bool] = [
            { s, v in sameSpecies(s, v) && sameIVs(s, v) && sameCP(s, v) },
            { s, v in sameSpecies(s, v) && sameIVs(s, v) && s.cp > v.row.cp },
            { s, v in sameIVs(s, v) && evolved(s, from: v, gm) },
            { s, v in (s.ivs == nil || v.row.ivs == nil) && sameSpecies(s, v) && sameCP(s, v) && sameHP(s, v) },
        ]
        for (n, test) in rules.enumerated() {
            var edges = [Int: [Int]]()   // scanned index -> saved indices
            for si in sPool { for vi in vPool where test(rows[si], saved[vi]) { edges[si, default: []].append(vi) } }
            for comp in components(edges) {
                let ss = comp.scanned, vs = comp.saved
                if ss.count == 1 && vs.count == 1 {
                    record(n, ss[0], vs[0])
                } else if interchangeable(ss.map { rows[$0] }, key: scannedKey), interchangeable(vs.map { saved[$0] }, key: savedKey) {
                    // Identical twins on at least one side: pair by count, the surplus goes on to the later rules.
                    for (si, vi) in zip(ss, vs) { record(n, si, vi) }
                } else {
                    for si in ss { plan.unsure.append(Unsure(scanned: si, candidates: (edges[si] ?? []).map { saved[$0].id })) }
                    unsureSaved.formUnion(vs)
                    sPool.removeAll { ss.contains($0) }
                    vPool.removeAll { vs.contains($0) }
                }
            }
        }

        plan.new = sPool
        if kind == .full { plan.gone = vPool.filter { !unsureSaved.contains($0) }.map { saved[$0].id } }
        plan.unsure.sort { $0.scanned < $1.scanned }
        plan.updated.sort { $0.scanned < $1.scanned }
        plan.same.sort { $0.scanned < $1.scanned }
        return plan
    }

    // MARK: - rule predicates

    private static func values<T: Equatable>(_ current: T, _ fix: Fix<T>?) -> [T] { fix?.was.map { [current, $0] } ?? [current] }

    private static func sameSpecies(_ s: ScanRow, _ v: BoxEntry) -> Bool {
        s.speciesKey == v.speciesKey || (v.corrections.species?.was).map { $0 == s.speciesKey } == true
    }
    private static func sameIVs(_ s: ScanRow, _ v: BoxEntry) -> Bool {
        guard let si = s.ivs else { return false }
        if v.row.ivs == si { return true }
        if let fix = v.corrections.ivs, fix.was == si { return true }
        return false
    }
    private static func sameCP(_ s: ScanRow, _ v: BoxEntry) -> Bool {
        s.cp == v.row.cp || v.corrections.cp?.was == s.cp
    }
    private static func sameHP(_ s: ScanRow, _ v: BoxEntry) -> Bool {
        guard let h = s.hp else { return false }
        return h == v.row.hp || v.corrections.hp?.was == h
    }
    private static func evolved(_ s: ScanRow, from v: BoxEntry, _ gm: GameMaster) -> Bool {
        guard s.speciesId != v.row.speciesId else { return false }
        return gm.isDescendant(s.speciesId, of: v.row.speciesId)
    }

    // MARK: - twins and components

    private struct Component { var scanned: [Int]; var saved: [Int] }

    /// Connected parts of the "could be the same Pokémon" graph, in index order.
    private static func components(_ edges: [Int: [Int]]) -> [Component] {
        var vToS = [Int: [Int]]()
        for (s, vs) in edges { for v in vs { vToS[v, default: []].append(s) } }
        var seenS = Set<Int>(), out = [Component]()
        for s in edges.keys.sorted() where !seenS.contains(s) {
            var ss = [Int](), vs = Set<Int>(), stack = [s]
            while let cur = stack.popLast() {
                guard seenS.insert(cur).inserted else { continue }
                ss.append(cur)
                for v in edges[cur] ?? [] where vs.insert(v).inserted { stack.append(contentsOf: vToS[v] ?? []) }
            }
            out.append(Component(scanned: ss.sorted(), saved: vs.sorted()))
        }
        return out
    }

    private static func interchangeable<T>(_ items: [T], key: (T) -> String) -> Bool {
        guard let first = items.first else { return true }
        let k = key(first)
        return items.allSatisfy { key($0) == k }
    }
    private static func scannedKey(_ r: ScanRow) -> String {
        "\(r.speciesKey)|\(r.ivs.map { "\($0.atk)/\($0.def)/\($0.hp)" } ?? "-")|\(r.cp)|\(r.hp.map(String.init) ?? "-")"
    }
    private static func savedKey(_ v: BoxEntry) -> String {
        scannedKey(v.row) + "|\(v.corrections.cp?.was.map(String.init) ?? "")|\(v.corrections.ivs?.was.map { "\($0.atk)/\($0.def)/\($0.hp)" } ?? "")|\(v.corrections.species?.was ?? "")|\(v.corrections.hp?.was.map(String.init) ?? "")"
    }

    // MARK: - apply

    /// Check an answer for every unsure Pokémon: all answered, each from its own candidates, no saved entry chosen twice.
    public static func validate(_ plan: Plan, resolutions: [Int: Resolution]) throws {
        let open = plan.unsure.filter { resolutions[$0.scanned] == nil }.count
        if open > 0 { throw Failure.unresolved(open) }
        var chosen = Set<String>()
        for u in plan.unsure {
            if case .existing(let id)? = resolutions[u.scanned] {
                guard u.candidates.contains(id) else { throw Failure.notACandidate(scanned: u.scanned, savedId: id) }
                guard chosen.insert(id).inserted else { throw Failure.chosenTwice(savedId: id) }
            }
        }
    }

    /// The box after the scan is added. `resolutions` answers each unsure Pokémon by its position in `plan.scanned`.
    /// Entries keep their order; new ones follow, in scan order. Gone entries are removed.
    public static func apply(_ plan: Plan, resolutions: [Int: Resolution] = [:], to saved: [BoxEntry], makeID: () -> String = { UUID().uuidString }) throws -> [BoxEntry] {
        try validate(plan, resolutions: resolutions)
        var byId = [String: BoxEntry](); for e in saved { byId[e.id] = e }
        var added = [BoxEntry]()
        let date = plan.scanDate
        func touch(_ id: String) { if let e = byId[id] { byId[id]?.lastSeen = max(e.lastSeen, date) } }

        for p in plan.same { touch(p.savedId) }
        for u in plan.updated { if let e = byId[u.savedId] { byId[u.savedId] = updated(e, with: plan.scanned[u.scanned], date: date) } }
        var newRows = plan.new
        for u in plan.unsure {
            switch resolutions[u.scanned]! {
            case .new: newRows.append(u.scanned)
            case .existing(let id): if let e = byId[id] { byId[id] = updated(e, with: plan.scanned[u.scanned], date: date) }
            }
        }
        for i in newRows.sorted() { added.append(BoxEntry(id: makeID(), row: plan.scanned[i], firstSeen: date, lastSeen: date)) }
        let gone = Set(plan.gone)
        return saved.filter { !gone.contains($0.id) }.compactMap { byId[$0.id] } + added
    }

    /// The entry with a later scan's values, keeping hand corrections the scan does not contradict.
    static func updated(_ e: BoxEntry, with s: ScanRow, date: Date) -> BoxEntry {
        var out = e
        out.lastSeen = max(e.lastSeen, date)
        var row = e.row, fix = e.corrections

        // Species (and the name, form and dex that follow it).
        var keepSpecies = false
        if let f = fix.species {
            if s.speciesKey == row.speciesKey || s.speciesKey == f.was { keepSpecies = true } else { fix.species = nil }
        }
        if !keepSpecies { row.speciesId = s.speciesId; row.name = s.name; row.display = s.display; row.form = s.form; row.dex = s.dex }

        if let f = fix.cp { if s.cp == row.cp || s.cp == f.was { /* keep */ } else { row.cp = s.cp; fix.cp = nil } } else { row.cp = s.cp }
        if let f = fix.hp { if s.hp == row.hp || s.hp == f.was { /* keep */ } else { row.hp = s.hp; fix.hp = nil } } else { row.hp = s.hp }

        var keepIVs = false
        if let f = fix.ivs {
            if s.ivs == nil || s.ivs == row.ivs || s.ivs == f.was { keepIVs = true } else { fix.ivs = nil }
        }
        if !keepIVs {
            row.ivs = s.ivs; row.ivsRead = s.ivsRead; row.ivsGuess = s.ivsGuess; row.solveStatus = s.solveStatus
            row.level = s.level; row.levelMax = s.levelMax; row.dust = s.dust
        }
        row.shadow = s.shadow ?? row.shadow
        row.flags = FlagInfo.remaining(s.flags, corrected: fix)
        out.row = BoxEntry.stripped(row)
        out.corrections = fix
        return out
    }

    // MARK: - hand corrections

    public enum EditFailure: Error, LocalizedError, Equatable {
        case badValue(String)
        public var errorDescription: String? { if case .badValue(let m) = self { return m } else { return nil } }
    }

    /// A person's corrections to one entry. nil leaves a value alone; `clearHP` and `clearIVs` say "unknown".
    public struct Edit: Equatable {
        public var cp: Int?
        public var hp: Int?
        public var ivs: IVs?
        public var speciesName: String?
        public init(cp: Int? = nil, hp: Int? = nil, ivs: IVs? = nil, speciesName: String? = nil) { self.cp = cp; self.hp = hp; self.ivs = ivs; self.speciesName = speciesName }
    }

    /// Apply a hand correction. A value equal to the current one is not a correction. The first correction of a value
    /// remembers what the scan had read; later ones keep that. The flags the corrected values answer are cleared.
    public static func correct(_ e: BoxEntry, with edit: Edit, gameMaster gm: GameMaster, at date: Date = Date()) throws -> BoxEntry {
        var out = e
        var row = e.row, fix = e.corrections
        if let cp = edit.cp, cp != row.cp {
            guard (10...10_000).contains(cp) else { throw EditFailure.badValue("CP must be a number between 10 and 10000.") }
            if fix.cp == nil { fix.cp = Fix(was: row.cp) }
            row.cp = cp
        }
        if let hp = edit.hp, hp != row.hp {
            guard (1...1_000).contains(hp) else { throw EditFailure.badValue("HP must be a number between 1 and 1000.") }
            if fix.hp == nil { fix.hp = Fix(was: row.hp) }
            row.hp = hp
        }
        if let ivs = edit.ivs, ivs != row.ivs {
            guard [ivs.atk, ivs.def, ivs.hp].allSatisfy({ (0...15).contains($0) }) else { throw EditFailure.badValue("Each IV must be a number from 0 to 15.") }
            if fix.ivs == nil { fix.ivs = Fix(was: row.ivs) }
            row.ivs = ivs; row.ivsGuess = nil; row.solveStatus = "hand"
        }
        if let name = edit.speciesName, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let id = gm.speciesId(forName: name), let sp = gm.byId[id] else { throw EditFailure.badValue("\"\(name)\" is not a Pokémon name the app knows. Pick one from the suggestions.") }
            if id != row.speciesId {
                if fix.species == nil { fix.species = Fix(was: row.speciesId) }
                let nf = GameMaster.nameAndForm(sp.name)
                row.speciesId = id; row.name = nf.name; row.display = nf.name; row.form = nf.form; row.dex = sp.dex
            }
        }
        row.flags = FlagInfo.remaining(row.flags, corrected: fix)
        out.row = row; out.corrections = fix
        return out
    }

    /// Clear every flag without changing a value ("I checked it in the game and it is right").
    public static func markChecked(_ e: BoxEntry) -> BoxEntry { var o = e; o.row.flags = []; return o }
}
