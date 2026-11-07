import Foundation

/// Design pass 2, rule 27 (D58): what the squad screens keep, per account, on the phone. This is the model and its rules only; where the value is
/// written (one file per account next to the account's box, say) is the app's job. One `SquadStore` is one account's.
///
/// What a stored `Saved` is, from pass 2-5: the squad's CURRENT squad (`SquadStore.current`). The suggestions (Available, Best) are never stored; the player's edit of one is kept (`SquadStore.edits`) until reset, and "Set this squad"
/// makes the squad as drawn the Current. Everything below describes a Current squad.
///
/// What is kept is the player's own choices: each slot's role and the Pokémon they picked (a copy, or under Best a species the box may not have: `SquadSlot.species`,
/// which a copy leaving the box does not touch). A squad with nothing kept has no Current and shows the suggestions, refilled whenever drawn.
/// Every change (a Pokémon chosen for a slot, a slot's role changed) first keeps the squad exactly as shown (`Saved.fixing`), so an edit acts on what the player
/// sees; a slot that refills in a changed squad is kept too (`adoptRefills`), so no slot changes on its own afterwards. A Current squad is drawn as kept: no mode placement rule hides a kept pick. A slot with no kept Pokémon (its copy left the box, or a swap emptied it) takes the next best unused one for its
/// role, that slot only (`reconciled`, `HubSquads.fill`). "Delete current squad" (`SquadStore.deleteCurrent`) takes the Current away and puts it in the squad's history. Copies are keyed by the box entry id,
/// which the app keeps through power-ups, evolutions, hand corrections and re-scans (`BoxEntry.id`), so a re-scan keeps every pick whose Pokémon is still in the box.
public struct SquadStore: Codable, Equatable {
    /// One squad as the player left it.
    public struct Saved: Codable, Equatable {
        public var slots: [SquadSlot]
        /// Set by `replaceCurrent` and `restoreFromHistory`. "Set" and "has a Current" are one thing (`SquadStore.isSet`); the flag stays so an older file's mark still counts (`hasCurrent`). Kept as it is when a pick leaves the box.
        public var isSet: Bool
        /// True once the player has changed the squad (rule 27): `fixing` has kept the shown squad. A file saved before this existed reads false, so a squad saved with some
        /// picks counts as changed only from its next change.
        public var changed: Bool
        /// Pass 2-6: how a Current came to be, written when it is made (`replaceCurrent`, `restoreFromHistory`) and read when it goes to the history, so the screen never has to carry
        /// the old Current's values: the tab it was set from, whether it differed from that tab's suggestion, and the bar's whole percent at that time. nil in an older file.
        public var source: SquadTab?
        public var edited: Bool?
        public var strength: Int?
        public init(slots: [SquadSlot], isSet: Bool = false, changed: Bool = false, source: SquadTab? = nil, edited: Bool? = nil, strength: Int? = nil) {
            self.slots = slots; self.isSet = isSet; self.changed = changed; self.source = source; self.edited = edited; self.strength = strength
        }

        private enum CodingKeys: String, CodingKey { case slots, isSet, changed, source, edited, strength }

        /// Tolerant: a file saved before `changed` existed has no such key.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            slots = try c.decode([SquadSlot].self, forKey: .slots)
            isSet = try c.decode(Bool.self, forKey: .isSet)
            changed = try c.decodeIfPresent(Bool.self, forKey: .changed) ?? false
            source = try c.decodeIfPresent(SquadTab.self, forKey: .source)
            edited = try c.decodeIfPresent(Bool.self, forKey: .edited)
            strength = try c.decodeIfPresent(Int.self, forKey: .strength)
        }

        /// Whether this is a Current squad (pass 2-5, rule 27): the player has changed it, or an older file holds picks of theirs or its "Squad set" mark. A squad with nothing
        /// kept has no Current and shows the suggestions.
        public var hasCurrent: Bool { changed || isSet || slots.contains { $0.pickId != nil } }

        /// The squads of two saved values are the same squad: the same slots (roles, picks, species picks, the "listed for" marker). The set mark is not part of it.
        public func sameSquad(as other: Saved) -> Bool { slots == other.slots }

        /// The squad as it is drawn becomes the player's: every slot keeps the Pokémon it shows (a copy as `pick`, a species row as `species`, nothing for an empty slot), and a
        /// suggestion listed for another role keeps saying so (`SquadSlot.fallback`). Runs before EVERY change (a choice, a role change, "Squad set"), so an edit always acts on
        /// what the player sees, never on picks they cannot see (a Best pick viewed under Available is replaced by what Available shows). The roles and the set mark are left alone.
        public mutating func fixing(_ shown: [FilledSlot]) {
            for i in slots.indices where shown.indices.contains(i) {
                // A species pick that reads as a copy has both ids: the species is the row the player chose, so it is what is kept.
                if let key = shown[i].species { slots[i].pick = nil; slots[i].species = key }
                else { slots[i].pick = shown[i].entryId; slots[i].species = nil }
                slots[i].fallback = shown[i].fallback && !shown[i].chosen && shown[i].pickId != nil ? true : nil
            }
            changed = true
        }

        /// Whether a slot of a changed squad has no kept Pokémon but the screen shows one (a copy left the box, or a swap emptied the slot): `adoptRefills` keeps it.
        public func needsAdopting(_ shown: [FilledSlot]) -> Bool {
            changed && slots.indices.contains { i in shown.indices.contains(i) && slots[i].pickId == nil && shown[i].pickId != nil }
        }

        /// Keeps what a changed squad shows in a slot with no kept Pokémon, so it does not change again on a later scan or box change. A slot with a kept Pokémon that the mode
        /// does not place is left alone (it returns under its mode).
        public mutating func adoptRefills(_ shown: [FilledSlot]) {
            guard changed else { return }
            for i in slots.indices where shown.indices.contains(i) && slots[i].pickId == nil && shown[i].pickId != nil {
                if let key = shown[i].species { slots[i].species = key } else { slots[i].pick = shown[i].entryId }
                slots[i].fallback = shown[i].fallback && !shown[i].chosen ? true : nil
            }
        }

        /// Puts the Pokémon of `pickId` form (`pick`, `species`) into a slot.
        private mutating func put(_ pick: String?, _ species: String?, at i: Int) { slots[i].pick = pick; slots[i].species = species; slots[i].fallback = nil }

        /// Choosing a Pokémon for a slot. `id` is a copy's entry id, or `squadSpeciesPrefix` + a species key for a Best pick of a Pokémon the box does not have (kept as
        /// `SquadSlot.species`); nil clears the slot's pick. `alsoClearing` are the other ids that stand for the same Pokémon (its copy and its species:
        /// `HubSquads.equivalents`), so a copy chosen here wins over a species pick of it in another slot, and the reverse.
        /// A Pokémon sits in one slot at a time, so one already in another slot is swapped: that slot takes the Pokémon this slot held (nothing, if it was empty, which empties
        /// the other slot). Nothing else moves. `shown` is the squad as drawn: given, it is kept first (`fixing`), so the swap exchanges what the player sees.
        public mutating func choose(_ id: String?, at index: Int, alsoClearing: [String] = [], shown: [FilledSlot]? = nil) {
            guard slots.indices.contains(index) else { return }
            if let shown { fixing(shown) }
            changed = true
            let previous = (pick: slots[index].pick, species: slots[index].species)
            defer { for i in slots.indices where slots[i].pickId == nil { slots[i].fallback = nil } }
            if let id {
                let same = Set([id] + alsoClearing)
                // What this slot held goes to the first slot holding the chosen Pokémon, unless it is the same Pokémon (a species pick of the chosen copy); any further slot
                // holding it is emptied.
                var handedOver = previous.pick.map(same.contains) ?? previous.species.map { same.contains(squadSpeciesPrefix + $0) } ?? false
                for i in slots.indices where i != index && (slots[i].pickId.map(same.contains) ?? false) {
                    if handedOver { put(nil, nil, at: i) } else { put(previous.pick, previous.species, at: i); handedOver = true }
                }
            }
            if let id, id.hasPrefix(squadSpeciesPrefix) {
                put(nil, String(id.dropFirst(squadSpeciesPrefix.count)), at: index)
            } else {
                put(id, nil, at: index)
            }
        }

        /// Rule 5 (see `HubSquads.changeRole`). A change of role is a change of the squad: `shown`, when given, is kept first (`fixing`).
        public mutating func changeRole(at index: Int, to role: String, fits: (String) -> Bool, shown: [FilledSlot]? = nil) {
            guard slots.indices.contains(index) else { return }
            if let shown { fixing(shown) }
            changed = true
            HubSquads.changeRole(&slots, at: index, to: role, fits: fits)
            slots[index].fallback = nil
        }
    }

    /// A raid or Max squad with the last day of its event, which is when it is dropped.
    public struct EventSquad: Codable, Equatable {
        public var squad: Saved
        /// `yyyy-mm-dd`, the rotation row's `to`.
        public var endsOn: String
        public init(squad: Saved, endsOn: String) { self.squad = squad; self.endsOn = endsOn }
    }

    /// 2 from pass 2-6 (stored Available and Best edits, the history). A version-1 file decodes with those empty; nothing old is renamed.
    public var version: Int = 2
    /// Raid and Max squads by `eventKey`.
    public var raids: [String: EventSquad] = [:]
    public var max: [String: EventSquad] = [:]
    /// The Gym's six.
    public var gym = Saved(slots: HubSquads.defaultGymSlots())
    /// Rocket: three per leader, by leader name.
    public var rocket: [String: Saved] = [:]
    /// PvP: three per league (`gl`, `ul`, `ml`), with roles.
    public var pvp: [String: Saved] = [:]
    /// Available | Best, per screen (`SquadScreen.rawValue`); a screen with no entry reads Available. The tab a squad with no Current opens on.
    public var modes: [String: SquadMode] = [:]
    /// Raids only (pass 2-5, rule 33): Balanced | Max damage, the roles the Available and Best suggestions are made of. Current squads keep their own roles.
    public var raidStyle: RaidStyle = .balanced
    /// Pass 2-6, rule 27: the player's edits of the Available and Best suggestions, kept per squad and tab (Raids also per style). Keyed by `editKey`; an entry exists only while the
    /// squad differs from its suggestion (`resetEdit` removes it and the screen draws the suggestion again).
    public var edits: [String: Saved] = [:]
    /// Pass 2-6, rule 27: the earlier Current squads of each squad (`SquadRef.key`), newest first, at most `historyLimit`.
    public var history: [String: [HistoryEntry]] = [:]
    /// The last day of each raid or Max event that holds edits or history, by `SquadRef.key`, so `pruned` can drop them with the event (an edit exists without a Current squad, so
    /// `raids`/`max` cannot say when it ends).
    public var eventEnds: [String: String] = [:]

    /// The names of the copies the Current squads, edits and history hold, by entry id, remembered while the copy is in the box (`remember`), so a history row can still name a Pokémon
    /// that has left it ("Zacian, not in your box"). Holds only ids some squad still names.
    public var pickNames: [String: String] = [:]

    /// Pass 2-6, H1: what Undo reverses, per squad (`SquadRef.key`): the last Set this squad, Set squad or Delete. In memory only; never written (not a coding key).
    public var undoRecords: [String: UndoRecord] = [:]

    public static let historyLimit = 10

    public init() {}

    private enum CodingKeys: String, CodingKey { case version, raids, max, gym, rocket, pvp, modes, raidStyle, edits, history, eventEnds, pickNames }

    /// Tolerant: a key missing from an older file reads as empty, so adding a section later does not lose the saved squads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        raids = try c.decodeIfPresent([String: EventSquad].self, forKey: .raids) ?? [:]
        max = try c.decodeIfPresent([String: EventSquad].self, forKey: .max) ?? [:]
        gym = try c.decodeIfPresent(Saved.self, forKey: .gym) ?? Saved(slots: HubSquads.defaultGymSlots())
        rocket = try c.decodeIfPresent([String: Saved].self, forKey: .rocket) ?? [:]
        pvp = try c.decodeIfPresent([String: Saved].self, forKey: .pvp) ?? [:]
        modes = try c.decodeIfPresent([String: SquadMode].self, forKey: .modes) ?? [:]
        raidStyle = try c.decodeIfPresent(RaidStyle.self, forKey: .raidStyle) ?? .balanced
        edits = try c.decodeIfPresent([String: Saved].self, forKey: .edits) ?? [:]
        history = try c.decodeIfPresent([String: [HistoryEntry]].self, forKey: .history) ?? [:]
        eventEnds = try c.decodeIfPresent([String: String].self, forKey: .eventEnds) ?? [:]
        pickNames = try c.decodeIfPresent([String: String].self, forKey: .pickNames) ?? [:]
        // A version-1 file reads as it always did; what this build writes from now on is version 2.
        if version < 2 { version = 2 }
    }

    // MARK: keys

    /// A rotation row's key: its first day, kind and title (two rows can share a day).
    public static func eventKey(_ row: HubData.RotationRow) -> String { "\(row.from)|\(row.kind.rawValue)|\(row.title)" }

    // MARK: Available | Best

    public func mode(for screen: SquadScreen) -> SquadMode { modes[screen.rawValue] ?? .available }
    public mutating func setMode(_ mode: SquadMode, for screen: SquadScreen) { modes[screen.rawValue] = mode }

    // MARK: squads

    /// The saved raid or Max squad of an event, or the default slots (no picks, not set) when the player has not touched it.
    public func eventSquad(_ row: HubData.RotationRow, screen: SquadScreen) -> Saved {
        let key = Self.eventKey(row)
        switch screen {
        case .raids: return raids[key]?.squad ?? Saved(slots: HubSquads.defaultRaidSlots())
        case .max: return max[key]?.squad ?? Saved(slots: HubSquads.defaultMaxSlots())
        default: return Saved(slots: [])
        }
    }

    /// Saves a raid or Max squad with the event's last day.
    public mutating func saveEventSquad(_ squad: Saved, row: HubData.RotationRow, screen: SquadScreen) {
        let key = Self.eventKey(row), value = EventSquad(squad: squad, endsOn: row.to)
        switch screen {
        case .raids: raids[key] = value
        case .max: max[key] = value
        default: break
        }
    }

    public func rocketSquad(leader: String) -> Saved { rocket[leader] ?? Saved(slots: HubSquads.defaultRocketSlots()) }
    public func pvpSquad(league: String) -> Saved { pvp[league] ?? Saved(slots: HubSquads.defaultPvpSlots()) }

    // MARK: rules

    /// Drops the raid and Max squads whose event has ended (its last day still counts, as in `HubRaidsModel.timeline`). An event still in `rotation`
    /// (matched by `eventKey`) is judged by the row's CURRENT last day, which may have moved since the squad was saved, and the stored day is updated;
    /// an event no longer in the rotation falls back to the day stored with the squad.
    public func pruned(today: String, rotation: [HubData.RotationRow]) -> SquadStore {
        let current = Dictionary(rotation.map { (Self.eventKey($0), $0.to) }, uniquingKeysWith: { a, _ in a })
        func keep(_ squads: [String: EventSquad]) -> [String: EventSquad] {
            var out = [String: EventSquad]()
            for (key, e) in squads {
                var e = e
                if let to = current[key] { e.endsOn = to }
                if e.endsOn >= today { out[key] = e }
            }
            return out
        }
        var s = self
        s.raids = keep(raids)
        s.max = keep(max)
        // Edits and history of a raid or Max event go with it. The day is the rotation row's current one, else the one stored when the first edit or history entry was made.
        var rotationEnds = [String: String]()
        for row in rotation { for screen in [SquadScreen.raids, .max] { rotationEnds[SquadRef.event(row: row, screen: screen).key] = row.to } }
        let known = Array(Set(eventEnds.keys).union(rotationEnds.keys))
        func owner(_ key: String) -> String? {
            guard key.hasPrefix(SquadScreen.raids.rawValue + "|") || key.hasPrefix(SquadScreen.max.rawValue + "|") else { return nil }
            return known.filter { key == $0 || key.hasPrefix($0 + "|") }.max { $0.count < $1.count }
        }
        func isEvent(_ key: String) -> Bool { key.hasPrefix(SquadScreen.raids.rawValue + "|") || key.hasPrefix(SquadScreen.max.rawValue + "|") }
        func alive(_ key: String) -> Bool {
            guard isEvent(key) else { return true }
            guard let o = owner(key), let end = rotationEnds[o] ?? eventEnds[o] else { return false }
            return end >= today
        }
        s.edits = edits.filter { alive($0.key) }
        s.history = history.filter { alive($0.key) }
        s.undoRecords = undoRecords.filter { alive($0.key) }
        var ends = [String: String]()
        for key in Array(s.edits.keys) + Array(s.history.keys) {
            if let o = owner(key), let end = rotationEnds[o] ?? eventEnds[o] { ends[o] = end }
        }
        s.eventEnds = ends
        return s
    }

    /// Old files, migrated for good (pass 2-5, rule 27.9): every squad that counts as a Current (`hasCurrent`) is marked `changed`, so a later box change refills its slots instead
    /// of dropping Current. The screens write the result back.
    public func migrated() -> SquadStore {
        func mark(_ s: Saved) -> Saved { var s = s; if s.hasCurrent { s.changed = true }; return s }
        var out = self
        out.raids = raids.mapValues { EventSquad(squad: mark($0.squad), endsOn: $0.endsOn) }
        out.max = max.mapValues { EventSquad(squad: mark($0.squad), endsOn: $0.endsOn) }
        out.gym = mark(gym)
        out.rocket = rocket.mapValues(mark)
        out.pvp = pvp.mapValues(mark)
        return out
    }

    /// Empties every slot whose chosen copy is no longer in the box (`boxIds`: the box's entry ids), so the slot shows the suggestion again. Picks of
    /// copies still in the box, the roles, the set marks and the modes are kept: a re-scan that keeps the entry ids loses nothing.
    public func reconciled(boxIds: Set<String>) -> SquadStore {
        func clean(_ s: Saved) -> Saved {
            var s = s
            for i in s.slots.indices { if let p = s.slots[i].pick, !boxIds.contains(p) { s.slots[i].pick = nil } }
            return s
        }
        var out = self
        out.raids = raids.mapValues { EventSquad(squad: clean($0.squad), endsOn: $0.endsOn) }
        out.max = max.mapValues { EventSquad(squad: clean($0.squad), endsOn: $0.endsOn) }
        out.gym = clean(gym)
        out.rocket = rocket.mapValues(clean)
        out.pvp = pvp.mapValues(clean)
        // A kept edit follows the box as Current does (rule 27.6); a history entry does not (the screen draws a Pokémon that left the box as gone).
        out.edits = edits.mapValues(clean)
        return out
    }

    /// Every copy id some squad names: a Current, a kept edit or a history entry.
    private var namedIds: Set<String> {
        var ids = Set<String>()
        func add(_ s: Saved) { for slot in s.slots { if let p = slot.pick { ids.insert(p) } } }
        for e in raids.values { add(e.squad) }
        for e in max.values { add(e.squad) }
        add(gym)
        for s in rocket.values { add(s) }
        for s in pvp.values { add(s) }
        for s in edits.values { add(s) }
        for l in history.values { for e in l { for slot in e.slots { if let p = slot.pick { ids.insert(p) } } } }
        for r in undoRecords.values { if let c = r.current { add(c) }; for e in r.history ?? [] { for slot in e.slots { if let p = slot.pick { ids.insert(p) } } } }
        return ids
    }

    /// Keeps the name of every copy a squad names that `names` (the box's, by entry id) has; a name already kept stays until the copy is named again, and one no squad names any more
    /// goes. The app runs it on every write and every attach, while the copy is still in the box.
    public mutating func remember(names: [String: String]) {
        var out = [String: String]()
        for id in namedIds { if let n = names[id] ?? pickNames[id] { out[id] = n } }
        pickNames = out
    }

    /// Both rules, as the app applies them when it opens a screen or finishes a scan.
    public func refreshed(today: String, rotation: [HubData.RotationRow], boxIds: Set<String>) -> SquadStore {
        migrated().pruned(today: today, rotation: rotation).reconciled(boxIds: boxIds)
    }
}
