import PogoBox

/// Which Pokémon a PvP slot may place under a mode, for the ranking the screen shows. Under Available a pick is placed only when the option the screen shows for its copy
/// (the Classic pick, or the experimental member under the Pogo Assist ranking: `LeaguePanel.shownIndex`) is the copy itself, so the check and the candidate list agree.
enum PvPPlacement {
    static func placeable(league: String, mode: SquadMode, pogoAssist: Bool, ctx: HubContext) -> (String, String) -> Bool {
        guard mode == .available else { return { _, _ in true } }
        return { id, _ in
            guard let r = ctx.advice.leagues[id]?[league] else { return false }
            return r.options[LeaguePanel.shownIndex(r, pogoAssist: pogoAssist)].isSelf
        }
    }
}

extension PvPPlacement {
    /// A species id (`squadSpeciesPrefix` + key, a Best pick of a Pokémon the box lacks) names its own species; any other id is a copy and `copy` says which species it is.
    /// One species to a squad holds for both.
    static func speciesOf(_ id: String, copy: (String) -> String?) -> String? {
        id.hasPrefix(squadSpeciesPrefix) ? String(id.dropFirst(squadSpeciesPrefix.count)) : copy(id)
    }

    /// The squad's slots (`HubSquads.pvpSquad`'s rule 23) with GO Battle League's rule that a squad never holds two copies of one species: a kept pick wins over a new
    /// suggestion of the same species, and a suggestion skips a candidate whose species an earlier slot already holds. `species` names a copy's species in the league.
    static func squad(slots: [SquadSlot], candidates: [HubSquads.PvpCandidate], placeable: (String, String) -> Bool, species: (String) -> String?) -> [FilledSlot] {
        squad(slots: slots, pool: { role in HubSquads.pool(role: role, in: candidates) }, all: candidates.map(\.entryId), placeable: placeable, species: species)
    }

    /// The same with the ids a role lists (`pool`) and every id in rank order (`all`, for a slot whose role lists none). An id may be a copy's entry id or, under Best, a
    /// `squadSpeciesPrefix` species id for a Pokémon the box lacks; `species` names the species of either.
    static func squad(slots: [SquadSlot], pool: (String) -> [String], all: [String], placeable: (String, String) -> Bool, species rawSpecies: (String) -> String?) -> [FilledSlot] {
        func species(_ id: String) -> String? { speciesOf(id, copy: rawSpecies) }
        var used = Set<String>(), usedSpecies = Set<String>()
        func take(_ id: String) -> Bool {
            let sp = species(id)
            guard !used.contains(id), sp.map({ !usedSpecies.contains($0) }) ?? true else { return false }
            used.insert(id); if let sp { usedSpecies.insert(sp) }
            return true
        }
        // `FilledSlot` can only be made by `HubSquads.fill`, so each slot is minted through it from a one-slot squad.
        func mint(_ role: String, _ id: String?, chosen: Bool = false, fallback: Bool = false) -> FilledSlot {
            let one = [SquadSlot(role: role, pick: chosen && !(id?.hasPrefix(squadSpeciesPrefix) ?? false) ? id : nil, species: chosen && (id?.hasPrefix(squadSpeciesPrefix) ?? false) ? id.map { String($0.dropFirst(squadSpeciesPrefix.count)) } : nil)]
            let pool = HubSquads.Pool(preferred: !chosen && !fallback ? id.map { [$0] } ?? [] : [], fallback: fallback ? id.map { [$0] } ?? [] : [])
            return HubSquads.fill(slots: one, pool: { _, _ in pool }, placeable: { _, _ in true })[0]
        }
        var out = slots.map { mint($0.role, nil) }
        for (i, s) in slots.enumerated() { if let p = s.pickId, placeable(p, s.role), take(p) { out[i] = mint(s.role, p, chosen: true) } }
        for (i, s) in slots.enumerated() where out[i].pickId == nil {
            if let id = pool(s.role).first(where: take) { out[i] = mint(s.role, id) }
            else if let id = all.first(where: take) { out[i] = mint(s.role, id, fallback: true) }
        }
        return out
    }

    /// The copies a slot's picker must not offer: those in other slots, and those of a species another slot holds.
    static func excluded(by filled: [FilledSlot], editing: Int, candidates: [HubSquads.PvpCandidate], species: (String) -> String?) -> Set<String> {
        excluded(by: filled, editing: editing, ids: candidates.map(\.entryId), species: species)
    }

    /// The same over any ids the picker may list (copies, and under Best species ids).
    static func excluded(by filled: [FilledSlot], editing: Int, ids: [String], species rawSpecies: (String) -> String?) -> Set<String> {
        func species(_ id: String) -> String? { speciesOf(id, copy: rawSpecies) }
        var out = HubSquads.excluded(by: filled, editing: editing, onlyChosen: false)
        let held = Set(filled.enumerated().compactMap { $0.offset != editing ? $0.element.pickId.flatMap(species) : nil })
        for id in ids where species(id).map(held.contains) ?? false { out.insert(id) }
        return out
    }
}

extension PvPPlacement {
    /// "Weak to Fire and Rock.": the attacking types that hit two or more of the members' type sets for more than normal damage; "No shared weakness." when none do.
    static func sharedWeakness(memberTypes: [[String]], hub: HubData) -> String {
        let shared = HubData.typeOrder.filter { attacker in memberTypes.filter { hub.beats([attacker], $0) }.count >= 2 }
        return shared.isEmpty ? "No shared weakness." : "Weak to \(SquadWords.typeList(shared))."
    }
}
