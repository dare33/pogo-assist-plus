import Foundation
import PogoReader

/// Adding a scan to a saved box. Pure: `plan` reads the saved entries and the scanned rows and returns a value for the
/// review screen; `apply` is a separate step that returns the new entries. Nothing here touches disk.
///
/// The game shows no unique id for a Pokémon, so a scanned Pokémon is matched to a saved one by what a power-up or an
/// evolution does not change. In this order, each rule on what the earlier rules left over:
///
///  1. Unchanged: same species and form, same three IVs, same CP.
///  2. Powered up: same species and form, same IVs, higher CP. NEVER applied automatically: an Unsure question (kind `poweredUp`) with the saved entry as the candidate.
///  3. Evolved: the scanned species is a later stage of the saved species (game master family data), same IVs. Likewise a question (kind `evolved`), as is a base form
///     scanned for an entry first saved as a Mega. "It is this one" does what the automatic update did; "It is new" adds the row and leaves the saved entry (in a Full scan it
///     then appears under "Not seen", kept by default). The owner has four genuinely different 15/15/15 Combee: the same IVs do not prove the same Pokémon.
///  4. IVs unread: when either side has no IVs, same species and form, same CP and same HP. (Decision: "no IVs on either
///     side" is read as "at least one side", because a Pokémon whose bars failed to read this time is the common case.)
///  5. Identical twins: matched by count. Two saved and two scanned are two unchanged; a third scanned is new.
///  6. Ambiguous: a scanned Pokémon with more than one saved candidate (or the reverse) at the same rule, where the
///     candidates are not interchangeable, is never guessed. It is "unsure" and the person picks.
///  7. Part-read CP: a scanned Pokémon that matched nothing above, whose CP fits no level (`no-level-fits`) or whose IVs were
///     not read, and whose CP digits are a subsequence of a saved same-species Pokémon's CP digits (182 in 1982) with the same
///     HP (or HP unread on either side), is unsure with those saved ones as candidates: never New, never matched without the
///     person. Also unsure: a row flagged `no-level-fits` (or with no usable CP) of the same species and HP whose `ivsRead` equals a
///     saved Pokémon's IVs, whatever its CP digits (a read of 281 for a saved 2611). The candidate may already be matched to another scanned row (the real read of it); "It is this one" then only
///     marks it seen and does not copy the part-read values over it.
///
///  8. Same CP and HP, other IVs: a row with the IVs read and a saved entry (same species, CP and HP read on both sides) with other IVs is
///     unsure with that entry as candidate, never New plus Gone. IVs never change in the game, so one of the two reads is wrong and the
///     merge does not guess: "It is this one" keeps the saved IVs (always when hand-corrected), marks the entry seen and flags it
///     `ivs-rescan-differs` to check; only saved IVs that were not an exact read, replaced by a clean read, are overwritten.
///  9. Evolution with unread IVs: a leftover row with no IVs that is a later stage of a saved entry's species (not lower HP) is unsure.
/// 10. Misread saved entry (M12): a saved entry with no IVs and no level fits, of the same species and HP as a row with IVs read, is
///     a candidate whatever the CP; "It is new" leaves it in the box whatever other candidates there were.
/// 11. Leftover rows are all judged against the same saved entries: two rows that could be one entry are both asked, and Save refuses
///     two rows that would each write values to one entry (part-read rows only mark seen, so any number of them may share one).
/// 12. Extra twin (rule 5): any scanned row identical to a saved entry already paired is asked about, flagged by the paging beat or not.
///
/// A row whose own CP is not trusted (flagged `no-level-fits`, a part read, or a `partialRead` question) writes NOTHING onto a saved entry:
/// "It is this one" only marks it seen. The automatic rules agree: such a row is never auto-paired as powered up, evolved, base of a Mega or
/// IVs now read (it is asked about, with the entries it would have paired with); pairing as Same, which writes nothing, stays automatic. An
/// entry already paired or updated by another row in the same plan is likewise only marked seen. `BoxMerge.effect` is the one decision of what
/// an answer does, used by `apply` and by the review card.
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
        /// A saved Mega-form entry scanned in its base form: the base species and values replace it.
        case megaToBase
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

    public struct PartMatch: Equatable {
        public var scanned: Int
        public var savedId: String
    }

    public struct Pair: Equatable {
        public var scanned: Int
        public var savedId: String
        /// The scanned Pokémon was Mega (or Primal) evolved and matched its base entry: only "last seen" is updated.
        public var mega = false
        public init(scanned: Int, savedId: String, mega: Bool = false) { self.scanned = scanned; self.savedId = savedId; self.mega = mega }
    }

    /// A scanned Pokémon that could be more than one saved one. `candidates` are saved ids, never empty.
    public struct Unsure: Equatable {
        public enum Kind: String, Equatable {
            /// More than one saved candidate, or a candidate the row only plausibly is (a power-up whose IVs were not read, other IVs at the
            /// same CP and HP, an evolution with unread IVs).
            case ambiguous
            /// The row's CP is a fragment of a saved CP (182 in 1982), or it fits no level: "It is this one" only marks the entry seen.
            case partialRead
            /// Every candidate is a misread saved entry (no IVs, no level fits) of what this correctly read row is: "It is this one" replaces
            /// its unread values with the read ones; "It is new" adds the row and leaves them.
            case misreadSaved
            /// A scanned row identical to a saved entry that was already paired with another row (flagged by the paging beat or not): add a
            /// second one, or leave it out.
            case extraTwin
            /// One saved entry of the species and IVs, one scanned row of the same IVs and a higher CP: it may be that Pokémon powered up, or a different one with the same
            /// IVs. NEVER applied automatically ("It is this one" does what the automatic update did; "It is new" adds the row and leaves the saved entry).
            case poweredUp
            /// The same for a scanned row that is a later stage of the saved species (an evolution).
            case evolved
            /// A base form scanned for an entry first saved in its Mega form, same IVs: the same Pokémon (the Mega values were temporary) or a different one.
            case megaToBase
            /// The box holds one Pokémon twice, once saved in its Mega form and once in its base form (same IVs and HP), and this scan read either: join them or keep both.
            /// Candidates: the base entry first, then the Mega entry. Choosing "this one" (the base entry) joins them; leaving it out keeps both.
            case megaPair
        }
        public var scanned: Int
        public var candidates: [String]
        public var kind: Kind = .ambiguous
        /// The candidates that are misread saved entries (no IVs, no level fits) of this correctly read row, whatever the kind: "It is new"
        /// leaves them in the box and choosing one replaces its unread values, even when other, plausible candidates were present.
        public var misread: [String] = []
        public init(scanned: Int, candidates: [String], kind: Kind = .ambiguous, misread: [String] = []) { self.scanned = scanned; self.candidates = candidates; self.kind = kind; self.misread = misread }
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
        /// Saved ids proposed as gone before any answer: always empty for an add-and-update scan. `goneReport` is the list after the
        /// person's answers to the unsure rows.
        public var gone: [String]
        /// Always empty now (kept for the saved scan format): nothing shields an unpaired entry from the "Not seen" list any more, which keeps every entry unless it is marked.
        public var kept: [Kept] = []
        /// What the scan saw on screen and did not read. It protects nothing; `unreadLine` tells the person that some "not seen" entries may be those items.
        public var unmatchedItems: [Unmatched] = []
        /// Part reads matched to a saved Pokémon by the merge itself (`autoPartMatch`): marked seen, nothing written. Shown on the review so it is visible.
        public var partMatches: [PartMatch] = []
        /// Saved entries that no scanned row was paired with (candidates of an unsure row included), for `goneReport`.
        public var unpaired: [Unpaired] = []
        /// Scanned positions whose species is a Mega or Primal form, with the base species id. A Mega row never writes its own
        /// values into the box: it matches its base entry as "same", or is saved as New under the base species with no CP, HP or level.
        public var megaBases: [Int: String] = [:]

        public var isUnresolvedFree: Bool { unsure.isEmpty }
    }

    /// A saved entry nothing was paired with: what `goneReport` needs to know about it.
    public struct Unpaired: Equatable {
        public var id: String
        public var speciesKey: String
        public var name: String
        public var display: String
        public var title: String
    }

    /// A saved entry the scan did not match but that is not proposed as gone, and why.
    public struct Kept: Equatable {
        public var savedId: String
        public var reason: String
    }

    /// What Save will remove, and what it keeps because of something unread, given the answers so far. Entries that are candidates of an
    /// unsure row still waiting for an answer are in neither list.
    public struct GoneReport: Equatable {
        public var gone: [String]
        public var kept: [Kept]
    }

    public enum Resolution: Equatable {
        case existing(String)
        case new
        /// A junk row: it is not added and nothing in the box changes.
        case leaveOut
    }

    public enum Failure: Error, LocalizedError, Equatable {
        case unresolved(Int)
        case notACandidate(scanned: Int, savedId: String)
        case chosenTwice(savedId: String)
        public var errorDescription: String? {
            switch self {
            case .unresolved(let n): return n == 1 ? "1 unsure Pokémon still needs an answer." : "\(n) unsure Pokémon still need an answer."
            case .notACandidate: return "That saved Pokémon is not one of the choices for this one."
            case .chosenTwice: return "Two scanned Pokémon were matched to the same saved one. Change one of the answers."
            }
        }
    }

    // MARK: - plan

    /// Whether a row's IVs are a clean read: not guessed, and not corrected by the solver (`ivs-corrected-from…`), ambiguous or unsettled. Others are treated as
    /// UNREAD when pairing (they may fill nothing and rescue nothing), so a flagged solver guess is never "other IVs at the same CP and HP".
    static func cleanIVs(_ r: ScanRow) -> Bool {
        guard r.ivs != nil, r.ivsGuess == nil else { return false }
        return !r.flags.contains { $0.hasPrefix("ivs-corrected") || $0.hasPrefix("ambiguous-ivs") || ($0.hasPrefix("bars-unsettled") && r.solveStatus != "exact") }
    }

    public static func plan(scanned originals: [ScanRow], unmatched: [Unmatched] = [], into saved: [BoxEntry], kind: BoxStore.Kind, scanDate: Date, gameMaster gm: GameMaster, shareIVs: Bool = true) -> Plan {
        // Matching sees a row whose IVs are not a clean read as one with no IVs read; the plan keeps the rows as scanned.
        let rows: [ScanRow] = originals.map { r in
            guard r.ivs != nil, !cleanIVs(r) else { return r }
            var v = r; v.ivs = nil; return v
        }
        var sPool = Array(rows.indices)
        var vPool = Array(saved.indices)
        var plan = Plan(kind: kind, scanDate: scanDate, scanned: originals, new: [], updated: [], same: [], unsure: [], gone: [])
        plan.unmatchedItems = unmatched
        var unsureSaved = Set<Int>()   // saved entries that are candidates of an unsure row and were not paired with anything

        for (i, r) in rows.enumerated() { if let b = megaBase(r.speciesId, gm) { plan.megaBases[i] = b } }

        enum Rule { case unchanged, megaSame, baseOfMega, poweredUp, evolved, noIVs }

        // One Pokémon saved twice across its Mega state (a base entry and a Mega-form entry with the same IVs and HP): the next scan that reads either asks once whether to
        // join them, instead of pairing the row with one entry and listing the other as not seen.
        for (mi, m) in saved.enumerated() {
            guard let base = megaBase(m.row.speciesId, gm), let mivs = m.row.ivs, m.row.hp != nil else { continue }
            guard let bi = saved.indices.first(where: { saved[$0].row.speciesId == base && saved[$0].row.ivs == mivs && saved[$0].row.hp == m.row.hp }) else { continue }
            // The scanned row must BE one of the two entries by the normal rules (the base row agrees with the base entry's CP, the Mega row with the Mega entry's; the HP agrees or
            // was not read): a row at another CP is a power-up or something new, never a reason to ask about joining. And only when exactly one row is that Pokémon: two identical
            // rows are two Pokémon (twins), left to the ordinary rules so the second is asked about, never silently added.
            let matching = sPool.filter { i in
                let r = rows[i]
                guard r.ivs == mivs, r.hp == nil || r.hp == m.row.hp else { return false }
                if r.speciesId == base { return sameCP(r, saved[bi]) }
                return r.speciesId == m.row.speciesId && sameCP(r, m)
            }
            guard matching.count == 1, let si = matching.first else { continue }
            plan.unsure.append(Unsure(scanned: si, candidates: [saved[bi].id, m.id], kind: .megaPair))
            unsureSaved.insert(bi); unsureSaved.insert(mi)
            sPool.removeAll { $0 == si }; vPool.removeAll { $0 == bi || $0 == mi }
        }

        func record(_ rule: Rule, _ si: Int, _ vi: Int) {
            let s = rows[si], v = saved[vi], id = v.id
            // A row whose CP fits no level is never paired by a rule that would write its values (power-up, evolution, IVs now read, base of a
            // Mega): it is asked about, and the answer only marks the entry seen. Pairing as Same writes nothing and stays automatic.
            // An apparent power-up or evolution is NEVER applied automatically: it may be a different Pokémon with the same IVs (the owner has four genuinely different 15/15/15
            // Combee). It is a question with the saved entry as the candidate; "It is this one" does what the automatic update did.
            switch rule {
            case .poweredUp: ask([si], [vi], kind: .poweredUp); return
            case .evolved: ask([si], [vi], kind: .evolved); return
            case .baseOfMega: ask([si], [vi], kind: .megaToBase); return
            default: break
            }
            // A row whose CP fits no level never writes by the IVs-now-read rule either: it is asked about, and the answer only marks the entry seen.
            if rule == .noIVs, v.row.ivs == nil, s.ivs != nil, hasNoLevelFits(s) { ask([si], [vi]); return }
            // The IVs-now-read path writes the IVs, level, dust, flags, shadow and solve status over the saved entry, so it is automatic only for an entry with no hand
            // corrections whose CP and HP equal their CURRENT values (a match through a correction's old value, or an HP one point off, is asked about).
            if rule == .noIVs, v.row.ivs == nil, s.ivs != nil, v.isHandCorrected || s.cp != v.row.cp || s.hp != v.row.hp { ask([si], [vi]); return }
            switch rule {
            case .unchanged: plan.same.append(Pair(scanned: si, savedId: id))
            case .megaSame: plan.same.append(Pair(scanned: si, savedId: id, mega: true))
            case .baseOfMega, .poweredUp, .evolved: break   // asked above, never reached
            case .noIVs:
                if v.row.ivs == nil && s.ivs != nil { plan.updated.append(Update(scanned: si, savedId: id, reason: .ivsNowRead)) }
                else { plan.same.append(Pair(scanned: si, savedId: id)) }
            }
            sPool.removeAll { $0 == si }
            vPool.removeAll { $0 == vi }
        }
        func ask(_ ss: [Int], _ candidates: [Int], kind: Unsure.Kind = .ambiguous) {
            let ids = candidates.map { saved[$0].id }
            for si in ss { plan.unsure.append(Unsure(scanned: si, candidates: ids, kind: kind)) }
            for vi in candidates where vPool.contains(vi) { unsureSaved.insert(vi) }
            sPool.removeAll { ss.contains($0) }
            vPool.removeAll { candidates.contains($0) }
        }

        // Before the rules: several saved Pokémon of one species with the SAME IVs (M6). The game shows no id, so when they were
        // powered up since the last scan, an exact match can pair a scanned row with the wrong one (saved 300 and 400, scanned 400
        // and 500: the 400 may be the old 400 or the old 300 powered up). Unless every scanned row of the group matches a saved one
        // exactly, pair only when exactly one assignment is consistent (no CP, HP or level lowered); otherwise ask about the whole
        // group. What cannot be known without unique ids: which of two look-alike Pokémon is which, so ids, dates and hand corrections
        // follow the assignment that was chosen, and a wrong guess cannot be told apart afterwards.
        var groups = [String: (saved: [Int], scanned: [Int])]()
        // Only what is still unpaired: a row or an entry the Mega-pair step took carries no second question (a scanned row is in at most one of same / updated / unsure / new).
        for (vi, v) in saved.enumerated() where vPool.contains(vi) { if let iv = v.row.ivs { groups["\(v.speciesKey)|\(iv)", default: ([], [])].saved.append(vi) } }
        for (si, r) in rows.enumerated() where plan.megaBases[si] == nil && sPool.contains(si) { if let iv = r.ivs, groups["\(r.speciesKey)|\(iv)"] != nil { groups["\(r.speciesKey)|\(iv)"]!.scanned.append(si) } }
        for key in groups.keys.sorted() {
            let g = groups[key]!
            guard g.saved.count > 1, !g.scanned.isEmpty else { continue }
            if allExact(g.scanned.map { rows[$0] }, g.saved.map { saved[$0] }) { continue }
            if let pairs = uniqueConsistentAssignment(scanned: g.scanned, saved: g.saved, rows: rows, entries: saved) {
                for (si, vi) in pairs { record(rows[si].cp == saved[vi].row.cp ? .unchanged : .poweredUp, si, vi) }
            } else {
                ask(g.scanned, g.saved)
            }
        }

        // Rule 1 (with 5: twins by count), the Mega rules, 2, 3, then 4. Each takes what the one before left.
        let megaBases = plan.megaBases
        let rules: [(Rule, (Int, ScanRow, BoxEntry) -> Bool)] = [
            (.unchanged, { _, s, v in sameSpecies(s, v) && sameIVs(s, v) && sameCP(s, v) }),
            // A Mega row against its base entry (the base is the saved species), same three IVs.
            (.megaSame, { i, s, v in megaBases[i].map { $0 == v.speciesKey || v.corrections.species?.was == $0 } == true && sameIVs(s, v) }),
            // A base row against an entry first saved in its Mega form.
            (.baseOfMega, { i, s, v in megaBases[i] == nil && megaBase(v.row.speciesId, gm) == s.speciesId && sameIVs(s, v) }),
            // A power-up never lowers the HP or the level: a higher CP with either lower is something else, and is asked about below.
            (.poweredUp, { _, s, v in sameSpecies(s, v) && sameIVs(s, v) && s.cp > v.row.cp && !lowers(s, v.row) }),
            (.evolved, { i, s, v in megaBases[i] == nil && sameIVs(s, v) && evolved(s, from: v, gm) }),
            (.noIVs, { _, s, v in (s.ivs == nil || v.row.ivs == nil) && sameSpecies(s, v) && sameCP(s, v) && sameHP(s, v) }),
        ]
        for (rule, test) in rules {
            var edges = [Int: [Int]]()   // scanned index -> saved indices
            for si in sPool { for vi in vPool where test(si, rows[si], saved[vi]) { edges[si, default: []].append(vi) } }
            for comp in components(edges) {
                let ss = comp.scanned, vs = comp.saved
                if ss.count == 1 && vs.count == 1 {
                    record(rule, ss[0], vs[0])
                } else if interchangeable(ss.map { rows[$0] }, key: scannedKey), interchangeable(vs.map { saved[$0] }, key: valueKey) {
                    // Identical twins on at least one side: pair by count, the surplus goes on to the later rules. Of identical saved
                    // entries a hand-corrected one is paired first (M7), so which one survives never depends on the saved order.
                    let ordered = vs.sorted { (saved[$0].isHandCorrected ? 0 : 1, $0) < (saved[$1].isHandCorrected ? 0 : 1, $1) }
                    let paired = Array(zip(ss, ordered))
                    for (si, vi) in paired { record(rule, si, vi) }
                    // M8: a surplus row identical to the saved entry it was paired with (same CP, IVs and HP) is a second identical Pokémon:
                    // asked about whether or not the paging beat flagged it, never silently added.
                    if rule == .unchanged, ss.count > ordered.count, let last = paired.last {
                        let extra = ss.dropFirst(ordered.count).filter { rows[$0].hp == nil || saved[last.1].row.hp == nil || sameHP(rows[$0], saved[last.1]) }
                        // Another saved entry of the species with the SAME CP and HP and other IVs that is still unpaired (the owner's two Fidough CP 768 HP 89, 15/4/10 and
                        // 15/11/12, both read as 15/4/10) may be the very Pokémon the surplus row is: it is offered too (candidates after the first), so it is never listed as
                        // not seen on a wrong "add a second".
                        let others = vPool.filter { $0 != last.1 && sameSpecies(rows[ss[0]], saved[$0]) && saved[$0].row.cp == saved[last.1].row.cp && saved[$0].row.hp == saved[last.1].row.hp && saved[$0].row.hp != nil }
                        for si in extra { plan.unsure.append(Unsure(scanned: si, candidates: [saved[last.1].id] + others.map { saved[$0].id }, kind: .extraTwin)); sPool.removeAll { $0 == si } }
                        if !extra.isEmpty { for vi in others { unsureSaved.insert(vi) }; vPool.removeAll { others.contains($0) } }
                    }
                } else {
                    // Never guessed: each row is asked about its own candidates.
                    for si in ss { plan.unsure.append(Unsure(scanned: si, candidates: (edges[si] ?? []).map { saved[$0].id })) }
                    for vi in vs { unsureSaved.insert(vi) }
                    sPool.removeAll { ss.contains($0) }
                    vPool.removeAll { vs.contains($0) }
                }
            }
        }

        // What is left: a row that matched nothing is asked about when it could be a saved Pokémon (a part-read CP, a power-up whose
        // IVs were not read, a lower CP, ...), and only otherwise is New.
        // Every leftover row is judged against the same pool: a row asked about an entry does not hide it from the next row that could
        // also be it (two reads of one saved Pokémon are both asked; applying the answers refuses one entry taken twice).
        let leftoverPool = vPool
        // The leftover rows' part-read candidates, so a candidate that two rows could be is never matched automatically.
        let leftoverParts: [Int: [Int]] = Dictionary(uniqueKeysWithValues: sPool.map { ($0, partialCandidates(rows[$0], saved)) })
        /// A part read is resolved without a question when ALL hold: its own CP fits no level (flagged `no-level-fits`) and was read with an HP; the one saved candidate has an
        /// HP within 1 of it and is itself a consistent reading (CP, HP, not flagged); the read CP's digits are a run of the candidate's CP (one direction: 607 in 1607); that is the
        /// only candidate; the candidate is still unpaired by the rules; and no other leftover row could be it. For one species the HP fixes the level, so a row whose CP fits no
        /// level for its HP cannot be a different Pokémon with that HP. Effect: the same as answering "It is this one" for a part read (marked seen, nothing written).
        func autoPartMatch(_ si: Int, part: [Int]) -> Int? {
            let r = rows[si]
            guard part.count == 1, let vi = part.first, hasNoLevelFits(originals[si]), r.cp > 0, let h = r.hp else { return nil }
            let v = saved[vi]
            guard vPool.contains(vi), v.row.cp > 0, let vh = v.row.hp, abs(vh - h) <= 1, !hasNoLevelFits(v.row), v.row.cp != r.cp, isSubsequence(Array(String(r.cp)), Array(String(v.row.cp))) else { return nil }
            guard !leftoverParts.contains(where: { $0.key != si && $0.value.contains(vi) }) else { return nil }
            // Bars that were read and clearly disagree with the saved IVs (beyond one notch on any stat, the same tolerance the candidate checks use) make this a real question: the
            // owner's rule is for a part read with no contradicting bars.
            if let read = originals[si].ivsRead ?? originals[si].ivs, let saw = v.row.ivs, !IVFit.near(IVFit.index(saw), read) { return nil }
            // nothing else may be a candidate for this row (a plausible or misread entry would make it a real question)
            guard !leftoverPool.contains(where: { $0 != vi && (plausibleCandidate(r, saved[$0], gm, fits) || misreadSaved(r, saved[$0])) }) else { return nil }
            return vi
        }
        let fits = IVFit(enabled: shareIVs)   // CP and HP fits per species, shared by every leftover row
        var stillNew = [Int]()
        for si in sPool {
            let r = rows[si]
            if let base = plan.megaBases[si] {
                // M3: a Mega row whose IVs were not read could be any saved base-species entry.
                if r.ivs == nil {
                    let cands = saved.indices.filter { saved[$0].speciesKey == base || saved[$0].corrections.species?.was == base }
                    if !cands.isEmpty { ask([si], cands); continue }
                }
                stillNew.append(si); continue
            }
            let part = partialCandidates(r, saved)
            if let vi = autoPartMatch(si, part: part) {
                plan.same.append(Pair(scanned: si, savedId: saved[vi].id)); plan.partMatches.append(PartMatch(scanned: si, savedId: saved[vi].id))
                vPool.removeAll { $0 == vi }
                continue
            }
            let plausible = leftoverPool.filter { plausibleCandidate(r, saved[$0], gm, fits) && !part.contains($0) }
            // M12: a saved entry that was misread (no IVs, no level fits) of this correctly read row, whatever the CP.
            let misread = leftoverPool.filter { misreadSaved(r, saved[$0]) && !part.contains($0) && !plausible.contains($0) }
            if part.isEmpty && plausible.isEmpty && misread.isEmpty { stillNew.append(si); continue }
            let all = part + plausible + misread
            let kind: Unsure.Kind = !part.isEmpty ? .partialRead : (all.allSatisfy { misreadSaved(r, saved[$0]) } ? .misreadSaved : .ambiguous)
            ask([si], all, kind: kind)
            plan.unsure[plan.unsure.count - 1].misread = all.filter { misreadSaved(r, saved[$0]) }.map { saved[$0].id }
        }
        sPool = stillNew
        plan.new = sPool

        // An entry that a later component of the same rule paired (as Same, or updated) may already have been offered as an extra twin's other candidate: it was seen, so it is
        // neither listed as not seen nor offered.
        let pairedIds = Set(plan.same.map { $0.savedId } + plan.updated.map { $0.savedId })
        for i in plan.unsure.indices where plan.unsure[i].kind == .extraTwin { plan.unsure[i].candidates = Array(plan.unsure[i].candidates.prefix(1)) + plan.unsure[i].candidates.dropFirst().filter { !pairedIds.contains($0) } }
        unsureSaved = unsureSaved.filter { !pairedIds.contains(saved[$0].id) }
        plan.unpaired = (vPool + unsureSaved.sorted()).map { Unpaired(id: saved[$0].id, speciesKey: saved[$0].speciesKey, name: saved[$0].row.name, display: saved[$0].row.display, title: saved[$0].row.title) }
        let report = goneReport(plan, resolutions: [:])
        plan.gone = report.gone
        plan.kept = report.kept
        plan.unsure.sort { $0.scanned < $1.scanned }
        plan.updated.sort { $0.scanned < $1.scanned }
        plan.same.sort { $0.scanned < $1.scanned }
        return plan
    }

    /// The "Not seen in this scan" list, given the answers so far. Only a full scan lists anything, and nothing is removed unless the person marks it (`keepSet`). Every unpaired
    /// saved entry is listed, whatever was on screen unread or left out of the box (`unreadLine` and `leftOutLine` say some may simply not have been read). A candidate of an
    /// unsure row is held back until that row is answered:
    /// "this one" means it was seen; "new" or an answer for another candidate makes it eligible again (M9).
    public static func goneReport(_ plan: Plan, resolutions: [Int: Resolution]) -> GoneReport {
        guard plan.kind == .full else { return GoneReport(gone: [], kept: []) }
        var pending = Set<String>(), seen = Set<String>()
        for u in plan.unsure {
            // Either answer to a Mega pair means both entries were seen (the scan read one of them; joining or keeping both is the person's decision).
            if u.kind == .megaPair, resolutions[u.scanned] != nil { seen.formUnion(u.candidates); continue }
            switch resolutions[u.scanned] {
            case nil: pending.formUnion(u.candidates)
            case .existing(let id)?: seen.insert(id)
            case .leaveOut?:
                // The candidates are listed as not seen like any other (see `leftOutLine`), except those of an extra twin: a same-CP-and-HP entry offered there may be the
                // Pokémon that was read, and leaving the row out must not put it up for removal.
                if u.kind == .extraTwin { seen.formUnion(u.candidates) }
            case .new?:
                // Answering "new" to a row that a misread saved entry might have been leaves that entry alone, in a full scan too, whatever
                // the kind: the other, plausible candidates still follow M9.
                seen.formUnion(u.misread)
            }
        }
        let kept = [Kept](); var gone = [String]()
        // Items on screen that were not read no longer protect anything: every Pokémon the scan did not pair is listed as "not seen" (kept unless the person marks it), and
        // `unreadLine` tells the person some of them may be those items.
        for e in plan.unpaired where !seen.contains(e.id) && !pending.contains(e.id) {
            gone.append(e.id)
        }
        return GoneReport(gone: gone, kept: kept)
    }

    /// "Read as CP 607; matched to your Charizard CP 1607 by its HP." for a part read the merge matched itself.
    public static func partMatchLine(_ plan: Plan, _ m: PartMatch, saved: BoxEntry?) -> String {
        let s = plan.scanned[m.scanned]
        return "Read as CP \(s.cp); matched to your \(saved.map { "\($0.row.title) CP \($0.row.cp)" } ?? "Pokémon") by its HP."
    }

    /// One line for the "Not seen" list when the person left rows out of the box at review (an extra twin does not count): some of the entries listed may simply not have been read.
    public static func leftOutLine(_ plan: Plan, resolutions: [Int: Resolution]) -> String? {
        let n = plan.unsure.filter { $0.kind != .extraTwin && resolutions[$0.scanned] == .leaveOut }.count
        guard n > 0 else { return nil }
        return "You left \(n == 1 ? "1 row" : "\(n) rows") out of the box. Some of the entries below may be those Pokémon, which simply were not read."
    }

    /// The one line shown above the "Not seen in this scan" list when items on screen could not be read (they absorbed into another row are not counted), else nil.
    public static func unreadLine(_ plan: Plan) -> String? {
        let items = plan.unmatchedItems.filter { $0.reason != "absorbed" }
        guard !items.isEmpty else { return nil }
        // What was read of each, so the person can match it to an entry in the list: a name, or the start of one with an ellipsis, and the CP when read.
        let names: [String] = items.map { u in
            var label = (u.name?.isEmpty == false) ? u.name! : ((u.nameText?.isEmpty == false) ? u.nameText! + "…" : "unknown")
            if let cp = u.cp { label += " CP \(cp)" }
            return label
        }
        var seen = Set<String>(), unique = [String]()
        for n in names where seen.insert(n.lowercased()).inserted { unique.append(n) }
        let n = items.count
        return "\(n) Pokémon on screen could not be read (names: \(unique.joined(separator: ", "))). Some of the entries below may be those."
    }

    // MARK: - rule predicates

    /// The base species of a Mega or Primal form (`<base>_mega`, `_mega_x`, `_mega_y`, `_primal`) when the game master has it.
    public static func megaBase(_ id: String, _ gm: GameMaster) -> String? {
        for suffix in ["_mega_x", "_mega_y", "_mega", "_primal"] where id.hasSuffix(suffix) {
            let base = String(id.dropLast(suffix.count))
            return gm.byId[base] != nil ? base : nil
        }
        return nil
    }

    /// What a Mega row is saved as when nothing in the box matches it: the base species with the IVs read, and no CP, HP or level
    /// (the Mega values are temporary), flagged `mega-when-scanned`. CP 0 means "not known".
    public static func asBase(_ r: ScanRow, base: String, _ gm: GameMaster) -> ScanRow {
        var out = r
        let sp = gm.byId[base]
        let nf = GameMaster.nameAndForm(sp?.name ?? base)
        out.speciesId = base; out.name = nf.name; out.display = nf.name; out.form = nf.form; out.dex = sp?.dex ?? r.dex
        out.cp = 0; out.hp = nil; out.level = nil; out.levelMax = nil; out.dust = nil
        out.solveStatus = "mega"; out.flags = ["mega-when-scanned"]
        return out
    }

    private static func partialCandidates(_ s: ScanRow, _ saved: [BoxEntry]) -> [Int] {
        let noLevelFits = s.flags.contains { $0 == "no-level-fits" || $0.hasPrefix("no-level-fits:") }
        guard noLevelFits || s.ivs == nil || s.cp <= 0 else { return [] }
        let digits = Array(String(s.cp))
        return saved.indices.filter { vi in
            let v = saved[vi]
            guard sameSpecies(s, v) else { return false }
            // (a) the CP digits are a subsequence of the saved CP's (182 in 1982), HP equal or unread on either side
            if s.cp != v.row.cp, isSubsequence(digits, Array(String(v.row.cp))), s.hp == nil || v.row.hp == nil || nearHP(s, v) { return true }
            // (b) whatever the CP digits: the solver found no level (or the CP is unusable), the HP is the same, and the bars read as
            // this saved Pokémon's IVs. The JavaScript nulls `ivs` when no level fits but keeps `ivsRead`.
            if noLevelFits || s.cp <= 0, s.hp != nil, nearHP(s, v), let read = s.ivsRead, read == v.row.ivs || read == v.corrections.ivs?.was { return true }
            return false
        }
    }

    /// A power-up never lowers the HP or the level; an HP one point lower is within a misread, so it is not "lowered" (the pair is asked about, never paired or New).
    private static func lowers(_ s: ScanRow, _ old: ScanRow) -> Bool {
        if let a = s.hp, let b = old.hp, a < b - 1 { return true }
        if let a = s.level, let b = old.level, a < b { return true }
        return false
    }

    /// Every scanned row has the CP of some saved one (counts aside: an extra identical copy is a twin, which the twin rule handles).
    private static func allExact(_ rows: [ScanRow], _ entries: [BoxEntry]) -> Bool {
        rows.allSatisfy { r in entries.contains { sameCP(r, $0) } }
    }

    /// The one way to pair `scanned` with `saved` (same species and IVs) in which no CP, HP or level goes down, or nil when there is
    /// none or more than one (rows that are identical count once). Groups above seven are never paired.
    private static func uniqueConsistentAssignment(scanned: [Int], saved: [Int], rows: [ScanRow], entries: [BoxEntry]) -> [(Int, Int)]? {
        guard scanned.count == saved.count, scanned.count <= 7 else { return nil }
        let order = saved.sorted { (entries[$0].isHandCorrected ? 0 : 1, $0) < (entries[$1].isHandCorrected ? 0 : 1, $1) }   // a hand-corrected one first (M7)
        var found = [String: [(Int, Int)]]()
        func consistent(_ si: Int, _ vi: Int) -> Bool { rows[si].cp >= entries[vi].row.cp && !lowers(rows[si], entries[vi].row) }
        func walk(_ k: Int, _ used: Set<Int>, _ acc: [(Int, Int)]) {
            if k == scanned.count {
                // Look-alike saved entries are interchangeable: only their values (and whether a hand correction is on them) tell assignments apart.
                let sig = acc.map { "\(valueKey(entries[$0.1]))\(entries[$0.1].isHandCorrected ? "*" : "")=\(scannedKey(rows[$0.0]))" }.sorted().joined(separator: ";")
                found[sig] = acc
                return
            }
            for vi in order where !used.contains(vi) && consistent(scanned[k], vi) { walk(k + 1, used.union([vi]), acc + [(scanned[k], vi)]) }
        }
        walk(0, [], [])
        return found.count == 1 ? found.values.first : nil
    }

    /// A saved entry the unmatched row could be, when it is not the exact or power-up match: the same species and IVs that do not
    /// contradict each other; and for a row that has no IVs, or a saved entry that has none, a CP that is not lower (a power-up).
    /// A saved entry flagged `no-level-fits` (or without a usable CP) and without IVs, of the same species and HP (or an HP not read) as a
    /// row that has its IVs: the saved one was probably a misread of this Pokémon.
    private static func misreadSaved(_ s: ScanRow, _ v: BoxEntry) -> Bool {
        guard s.ivs != nil, v.row.ivs == nil, sameSpecies(s, v) else { return false }
        guard v.row.flags.contains(where: { $0 == "no-level-fits" || $0.hasPrefix("no-level-fits:") }) || v.row.cp <= 0 else { return false }
        return s.hp == nil || v.row.hp == nil || nearHP(s, v)
    }

    /// A saved entry is not offered as "the same Pokémon" (powered up, evolved, read earlier) when NO IV triple explains both readings, judged conservatively: it only
    /// vetoes when the mismatch is beyond what a small misread explains, and otherwise asks.
    /// - No level direction: the triple may sit at ANY two levels (this also covers an evolution, whose CP can fall as the species changes, and a lower CP).
    /// - HP within 1 on each side; CP exact on a side whose IVs are read and within 1 on a side whose IVs are unread; each READ IV may be one notch off (the triple is
    ///   within 1 of the read values per stat). A hand correction counts as read; its `was` value does not rescue it.
    /// - Each side is judged on its own: a reading the app already flagged `no-level-fits` (or with no usable CP) fits anything, but an unflagged reading on the other side
    ///   must still fit by itself with these tolerances, else nothing fits and the entry is not a candidate.
    /// Each side uses its own species' base stats. When the stats are unknown it cannot say no.
    static func sharesAnIVTriple(_ s: ScanRow, _ v: BoxEntry, _ gm: GameMaster, _ fits: IVFit) -> Bool {
        guard fits.enabled, let bs = gm.byId[s.speciesId]?.baseStats, let bv = gm.byId[v.row.speciesId]?.baseStats else { return true }
        if let a = s.ivs, let b = v.row.ivs, a != b { return true }   // different IVs read on both sides: other rules decide
        func flagged(_ r: ScanRow) -> Bool { r.cp <= 0 || r.flags.contains { $0 == "no-level-fits" || $0.hasPrefix("no-level-fits:") } }
        // the triples a side allows: nil means "anything"
        func allowed(_ r: ScanRow, _ base: BaseStats) -> Set<Int>? {
            if flagged(r) { return nil }
            let all = fits.triples(base, cp: r.cp, hp: r.hp, exactCP: r.ivs != nil)
            guard let read = r.ivs else { return all }
            return all.filter { IVFit.near($0, read) }
        }
        let fromSaved = allowed(v.row, bv), fromScanned = allowed(s, bs)
        // the IVs one side read bound the other side too (a triple within a notch of what was read)
        func bound(_ set: Set<Int>?, by read: IVs?) -> Set<Int>? {
            guard let read else { return set }
            return set.map { $0.filter { IVFit.near($0, read) } } ?? Set((0..<4096).filter { IVFit.near($0, read) })
        }
        let a = bound(fromSaved, by: s.ivs), b = bound(fromScanned, by: v.row.ivs)
        switch (a, b) {
        case (nil, nil): return true
        case (let x?, nil): return !x.isEmpty
        case (nil, let y?): return !y.isEmpty
        case (let x?, let y?): return !x.isDisjoint(with: y)
        }
    }

    private static func plausibleCandidate(_ s: ScanRow, _ v: BoxEntry, _ gm: GameMaster, _ fits: IVFit) -> Bool {
        // An evolution whose IVs were not read: the later stage of a saved species (the rule the automatic match uses), HP not lower.
        if s.ivs == nil, megaBase(s.speciesId, gm) == nil, evolved(s, from: v, gm) {
            if let a = s.hp, let b = v.row.hp, a < b - 1 { return false }
            return sharesAnIVTriple(s, v, gm, fits)
        }
        guard sameSpecies(s, v) else { return false }
        if let a = s.hp, let b = v.row.hp, a < b - 1, s.ivs == nil || v.row.ivs == nil { return false }   // a power-up never lowers the HP (one point is a misread)
        // equal IVs: any CP or HP (a power-up that is not consistent, or a lower CP). Different IVs with the same CP and the same HP
        // read are one Pokémon whose bars were misread (or whose IVs were corrected by hand), so asked about, never New plus Gone.
        if let a = s.ivs, let b = v.row.ivs {
            if a == b { return sharesAnIVTriple(s, v, gm, fits) }
            return v.corrections.ivs?.was == a || (sameCP(s, v) && sameHP(s, v))
        }
        return (s.cp <= 0 || s.cp >= v.row.cp) && sharesAnIVTriple(s, v, gm, fits)
    }

    private static func isSubsequence(_ small: [Character], _ big: [Character]) -> Bool {
        var i = 0
        for c in big where i < small.count && c == small[i] { i += 1 }
        return i == small.count
    }

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
    /// The HP within 1 of the saved one's current (or hand-corrected `was`) value: a read off by a point is still asked about, never New.
    private static func nearHP(_ s: ScanRow, _ v: BoxEntry) -> Bool {
        guard let h = s.hp else { return false }
        return [v.row.hp, v.corrections.hp?.was].contains { $0.map { abs($0 - h) <= 1 } == true }
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
    /// A saved entry's values without its hand corrections: look-alike entries are interchangeable by this.
    private static func valueKey(_ v: BoxEntry) -> String { scannedKey(v.row) }
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
                // Several part reads may point at one saved Pokémon (they only mark it seen); two rows that would each write values to one
                // entry cannot both be it.
                if writes(u, id, plan) { guard chosen.insert(id).inserted else { throw Failure.chosenTwice(savedId: id) } }
            }
        }
    }

    /// The flag a saved entry gets when a later scan read other IVs at the same CP and HP and the person kept the saved ones.
    public static let ivsRescanFlag = "ivs-rescan-differs"

    private static func hasNoLevelFits(_ r: ScanRow) -> Bool { r.flags.contains { $0 == "no-level-fits" || $0.hasPrefix("no-level-fits:") } }

    /// The row's own CP cannot be trusted: it fits no level, or it is a fragment of a saved CP.
    private static func untrusted(_ u: Unsure, _ r: ScanRow) -> Bool { u.kind == .partialRead || hasNoLevelFits(r) }

    /// What answering "It is this one" for this candidate does. The ONE decision: `apply` does exactly this and the review card says exactly
    /// this, so the text cannot disagree with the result.
    public enum Effect: Equatable {
        /// Only marks the entry seen; nothing is changed (an untrusted row, an extra twin's own entry, an entry another row already paired).
        case seenOnly
        /// A Mega row for its base entry: seen, and marked Mega when scanned; the Mega values are not copied.
        case seenAsMega
        /// The read values replace the saved ones the scan read (unread values stay).
        case replacesValues
        /// Other IVs read at the same CP and HP: the saved IVs were not an exact read, so the clean read replaces them.
        case replacesIVs
        /// Other IVs read at the same CP and HP: the saved IVs are kept, the entry is marked seen and flagged to check.
        case keepsIVsAndFlags
        /// The base entry and the Mega-form entry of one Pokémon become one entry (the base entry, marked Mega when scanned as such).
        case joinsMegaPair
    }

    public static func effect(_ plan: Plan, _ u: Unsure, candidate e: BoxEntry, gameMaster gm: GameMaster?) -> Effect {
        let r = plan.scanned[u.scanned]
        if u.kind == .megaPair { return u.candidates.first == e.id ? .joinsMegaPair : .seenOnly }
        if onlyMarksSeen(plan, u, e.id) { return .seenOnly }
        // An extra twin's other candidate is never overwritten, however shaky its saved IVs: the row is a second read of a Pokémon already paired, so the saved IVs are kept and flagged.
        if ivsDisagree(r, e) { return ivsReplaceable(r, e) && u.kind != .extraTwin ? .replacesIVs : .keepsIVsAndFlags }
        if let gm, plan.megaBases[u.scanned] != nil, megaBase(e.row.speciesId, gm) == nil { return .seenAsMega }
        return .replacesValues
    }

    /// An answer for this candidate changes nothing but "seen": an extra twin, a row whose CP is not trusted, or an entry another row already
    /// paired or updated in this plan (it is never written twice).
    private static func onlyMarksSeen(_ plan: Plan, _ u: Unsure, _ id: String) -> Bool {
        (u.kind == .extraTwin && u.candidates.first == id) || untrusted(u, plan.scanned[u.scanned]) || plan.same.contains(where: { $0.savedId == id }) || plan.updated.contains(where: { $0.savedId == id })
    }

    /// Whether choosing saved entry `id` for this unsure row writes the row's values onto it. Rows that only mark seen may share an entry.
    private static func writes(_ u: Unsure, _ id: String, _ plan: Plan) -> Bool { u.kind != .megaPair && !onlyMarksSeen(plan, u, id) }

    /// Both have IVs, they differ (a hand correction's old read counts as the same), and the CP and HP read are the same.
    public static func ivsDisagree(_ s: ScanRow, _ v: BoxEntry) -> Bool {
        guard let a = s.ivs, let b = v.row.ivs, a != b, v.corrections.ivs?.was != a else { return false }
        return sameCP(s, v) && sameHP(s, v)
    }

    /// The saved IVs were not an exact read (a guess or an IV flag, no hand correction) and the scan read its own cleanly.
    public static func ivsReplaceable(_ s: ScanRow, _ v: BoxEntry) -> Bool {
        func shaky(_ r: ScanRow) -> Bool { r.ivsGuess != nil || r.solveStatus != "exact" || r.flags.contains { FlagInfo.field(of: $0) == .ivs } }
        return v.corrections.ivs == nil && shaky(v.row) && !shaky(s)
    }

    /// Nothing is removed unless the person chooses it: of the entries a full scan did not see, only those marked for removal go. This is the `keepGone`
    /// to hand to `apply` (and `ScanReportBuilder.reviewLines`) when the review starts with every not-seen entry kept and the person marks some.
    public static func keepSet(plan: Plan, resolutions: [Int: Resolution], markedForRemoval: Set<String>) -> Set<String> {
        Set(goneReport(plan, resolutions: resolutions).gone).subtracting(markedForRemoval)
    }

    /// The box after the scan is added. `resolutions` answers each unsure Pokémon by its position in `plan.scanned`.
    /// Entries keep their order; new ones follow, in scan order. Gone entries (`goneReport`, less any in `keepGone`) are removed.
    /// With an `engine`, an entry whose IVs were kept (a hand correction, or a scan that read none) and whose CP or HP changed gets its
    /// level and dust worked out again (`LevelSolve`); nothing fitting leaves the old values and flags it.
    public static func apply(_ plan: Plan, resolutions: [Int: Resolution] = [:], keepGone: Set<String> = [], to saved: [BoxEntry], makeID: () -> String = { UUID().uuidString },
                             engine: CoreEngine? = nil) throws -> [BoxEntry] {
        try validate(plan, resolutions: resolutions)
        let gm0 = try GameMaster.bundled()
        var byId = [String: BoxEntry](); for e in saved { byId[e.id] = e }
        var added = [BoxEntry]()
        var resolve = Set<String>()
        var removedByJoin = Set<String>()
        let date = plan.scanDate
        func touch(_ id: String) { if let e = byId[id] { byId[id]?.lastSeen = max(e.lastSeen, date) } }
        func update(_ id: String, _ row: ScanRow) {
            guard let e = byId[id] else { return }
            let new = updated(e, with: row, date: date)
            let keptIVs = (row.ivs == nil && e.row.ivs != nil) || new.corrections.ivs != nil
            if keptIVs, new.row.ivs != nil, new.row.cp != e.row.cp || new.row.hp != e.row.hp { resolve.insert(id) }
            byId[id] = new
        }

        func setMega(_ id: String, _ mega: Bool) { byId[id]?.megaWhenScanned = mega ? true : nil }
        // An untrusted row paired as Same writes nothing but last-seen (not even the Mega mark).
        for p in plan.same { touch(p.savedId); if !hasNoLevelFits(plan.scanned[p.scanned]) { setMega(p.savedId, p.mega) } }
        for u in plan.updated { update(u.savedId, plan.scanned[u.scanned]); setMega(u.savedId, false) }
        var newRows = plan.new
        for u in plan.unsure {
            switch resolutions[u.scanned]! {
            case .new: if u.kind != .megaPair { newRows.append(u.scanned) }
            case .leaveOut: break
            case .existing(let id):
                guard let e = byId[id] else { break }
                if u.kind == .megaPair {
                    // Join: the base entry (candidates[0]) stays, with its own values and hand corrections UNCHANGED (the Mega entry's values and corrections go with it), is marked Mega when the scan
                    // read the Mega form, and the Mega-form entry is removed. Nothing else changes (the earlier first-seen date is kept). Any other answer than "this one" keeps both.
                    guard id == u.candidates.first, u.candidates.count == 2, let m = byId[u.candidates[1]] else { break }
                    byId[id]?.firstSeen = min(e.firstSeen, m.firstSeen)
                    touch(id)
                    setMega(id, plan.megaBases[u.scanned] != nil)
                    removedByJoin.insert(m.id)
                    break
                }
                switch effect(plan, u, candidate: e, gameMaster: gm0) {
                case .joinsMegaPair: break   // handled above
                case .seenOnly: byId[id]?.lastSeen = max(e.lastSeen, date)
                case .seenAsMega: touch(id); setMega(id, true)
                case .replacesValues, .replacesIVs: update(id, plan.scanned[u.scanned]); setMega(id, false)
                case .keepsIVsAndFlags:
                    // The same Pokémon read twice with other IVs: the IVs never change, so one read is wrong and neither is guessed.
                    byId[id]?.lastSeen = max(e.lastSeen, date)
                    if byId[id]?.row.flags.contains(ivsRescanFlag) == false { byId[id]?.row.flags.append(ivsRescanFlag) }
                }
            }
        }
        for i in newRows.sorted() {
            var row = plan.scanned[i]
            var mega = false
            if let base = plan.megaBases[i] { row = Self.asBase(row, base: base, gm0); mega = true }
            added.append(BoxEntry(id: makeID(), row: row, firstSeen: date, lastSeen: date, megaWhenScanned: mega ? true : nil))
        }
        if let engine { for id in resolve { if let e = byId[id] { byId[id] = LevelSolve.apply(to: e, engine: engine).entry } } }
        let gone = Set(goneReport(plan, resolutions: resolutions).gone).subtracting(keepGone).union(removedByJoin)
        return saved.filter { !gone.contains($0.id) }.compactMap { byId[$0.id] } + added
    }

    /// The entry with a later scan's values, keeping hand corrections the scan does not contradict. A field the scan did not read
    /// (nil, or a CP of 0) never replaces a saved value; IVs, HP, level, level range, dust and the bars read each follow this
    /// independently. When the IVs are kept (a hand correction, or the scan read none) the level and dust are kept too: they follow the
    /// IVs, and `apply` works them out again when an engine is given.
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

        if let f = fix.cp {
            if s.cp <= 0 || s.cp == row.cp || s.cp == f.was { /* keep */ } else { row.cp = s.cp; fix.cp = nil }
        } else if s.cp > 0 { row.cp = s.cp }
        if let f = fix.hp {
            if s.hp == nil || s.hp == row.hp || s.hp == f.was { /* keep */ } else { row.hp = s.hp; fix.hp = nil }
        } else if let hp = s.hp { row.hp = hp }

        var keepIVs = row.ivs != nil && s.ivs == nil
        if let f = fix.ivs {
            if s.ivs == nil || s.ivs == row.ivs || s.ivs == f.was { keepIVs = true } else { fix.ivs = nil; keepIVs = false }
        }
        if !keepIVs {
            row.ivs = s.ivs ?? row.ivs; row.ivsRead = s.ivsRead ?? row.ivsRead
            // IVs that were read replace a guess: the entry stops counting as one (a stale guess would let a later clean read replace again).
            row.ivsGuess = s.ivs != nil ? s.ivsGuess : (s.ivsGuess ?? row.ivsGuess)
            row.solveStatus = s.ivs != nil ? s.solveStatus : (row.ivs != nil ? row.solveStatus : s.solveStatus)
            row.level = s.level ?? row.level; row.levelMax = s.levelMax ?? row.levelMax; row.dust = s.dust ?? row.dust
        }
        row.shadow = s.shadow ?? row.shadow
        // The scan's flags about IVs it did not read do not apply to IVs that were kept.
        let scanFlags = keepIVs ? s.flags.filter { FlagInfo.field(of: $0) != .ivs } : s.flags
        row.flags = FlagInfo.remaining(scanFlags, corrected: fix)
        // A rescan that read other IVs and was answered "keep the saved ones" stays flagged until the IVs are corrected by hand, checked, or replaced.
        if e.row.flags.contains(BoxMerge.ivsRescanFlag), row.ivs == e.row.ivs, !row.flags.contains(BoxMerge.ivsRescanFlag) { row.flags.append(BoxMerge.ivsRescanFlag) }
        out.row = BoxEntry.stripped(row)
        out.corrections = fix
        return out
    }

    // MARK: - hand corrections

    public enum EditFailure: Error, LocalizedError, Equatable {
        case badValue(String)
        public var errorDescription: String? { if case .badValue(let m) = self { return m } else { return nil } }
    }

    /// A person's corrections to one entry. nil leaves a value alone; there is no way to clear a value to "unknown": a scan that reads nothing leaves it alone.
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
            row.flags.removeAll { $0 == ivsRescanFlag }   // the person has decided the IVs
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

    /// Clear the `check` flags without changing a value (the notes on how it was read stay) ("I checked it in the game and it is right").
    public static func markChecked(_ e: BoxEntry) -> BoxEntry { var o = e; o.row.flags = o.row.noteFlags; return o }
}

/// For a species' base stats, a CP and an HP: every IV triple (index atk * 256 + def * 16 + hp) that gives them at some level, with the lowest and highest such
/// level. Memoised for the lifetime of one `BoxMerge.plan` call. The formulas and the multiplier table are PogoReader's (`cpAt`, `hpAt`, `levels`).
final class IVFit {
    private var memo = [String: Set<Int>]()
    /// False: the test is off (a comparison in the tests of what the merge asked before it existed).
    let enabled: Bool
    init(enabled: Bool = true) { self.enabled = enabled }
    static func index(_ i: IVs) -> Int { i.atk * 256 + i.def * 16 + i.hp }
    /// Whether the triple with this index is within one notch of `read` on every stat.
    static func near(_ index: Int, _ read: IVs) -> Bool { abs(index / 256 - read.atk) <= 1 && abs((index / 16) % 16 - read.def) <= 1 && abs(index % 16 - read.hp) <= 1 }

    /// Every IV triple (index atk * 256 + def * 16 + hp) that gives about this CP and HP at SOME level: HP within 1 (when read), CP exact or, when `exactCP` is false (the
    /// IVs of that reading were not read), within 1. Memoised for the lifetime of one `BoxMerge.plan` call; the formulas and level table are PogoReader's.
    func triples(_ base: BaseStats, cp: Int, hp: Int?, exactCP: Bool) -> Set<Int> {
        let key = "\(base.atk)/\(base.def)/\(base.hp)|\(cp)|\(hp.map(String.init) ?? "-")|\(exactCP)"
        if let m = memo[key] { return m }
        var out = Set<Int>()
        let slack = exactCP ? 0 : 1
        for a in 0...15 { for d in 0...15 { for h in 0...15 {
            let ivs = IVs(atk: a, def: d, hp: h)
            for level in levels {
                let c = cpAt(base, ivs, level)
                if c > cp + slack { break }
                if abs(c - cp) <= slack, hp == nil || abs(hpAt(base, ivs, level) - hp!) <= 1 { out.insert(a * 256 + d * 16 + h); break }
            }
        } } }
        memo[key] = out
        return out
    }
}
