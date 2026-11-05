import Foundation

/// Design pass 2, rule 27 (D58): what the squad screens keep, per account, on the phone. This is the model and its rules only; where the value is
/// written (one file per account next to the account's box, say) is the app's job. One `SquadStore` is one account's.
///
/// What is kept is the player's own choices: each slot's role and the Pokémon they picked (a copy, or under Best a species the box may not have: `SquadSlot.species`,
/// which a copy leaving the box does not touch). A squad the player has never changed keeps nothing and shows the suggestion, refilled whenever it is drawn.
/// The first change (a Pokémon chosen for a slot, or a slot's role changed) makes the shown squad the player's own (`Saved.fixing`): every slot's Pokémon is kept as
/// shown, and from then on no slot changes on its own. A slot with no kept Pokémon (its copy left the box, or a swap emptied it) takes the next best unused one for its
/// role, that slot only (`reconciled`, `HubSquads.fill`). "Back to suggested squad" (`Saved.backToSuggested`) forgets it all. Copies are keyed by the box entry id,
/// which the app keeps through power-ups, evolutions, hand corrections and re-scans (`BoxEntry.id`), so a re-scan keeps every pick whose Pokémon is still in the box.
public struct SquadStore: Codable, Equatable {
    /// One squad as the player left it.
    public struct Saved: Codable, Equatable {
        public var slots: [SquadSlot]
        /// "Set this squad / Squad set" (raids and Max): the player's own mark that the squad is ready. Kept as it is when a pick leaves the box.
        public var isSet: Bool
        /// True once the player has changed the squad (rule 27): `fixing` has kept the shown squad. A file saved before this existed reads false, so a squad saved with some
        /// picks counts as changed only from its next change.
        public var changed: Bool
        public init(slots: [SquadSlot], isSet: Bool = false, changed: Bool = false) { self.slots = slots; self.isSet = isSet; self.changed = changed }

        private enum CodingKeys: String, CodingKey { case slots, isSet, changed }

        /// Tolerant: a file saved before `changed` existed has no such key.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            slots = try c.decode([SquadSlot].self, forKey: .slots)
            isSet = try c.decode(Bool.self, forKey: .isSet)
            changed = try c.decodeIfPresent(Bool.self, forKey: .changed) ?? false
        }

        /// Whether the squad's "Back to suggested squad" button shows: the player has changed it, or an older file holds picks of theirs.
        public var showsBackToSuggested: Bool { changed || slots.contains { $0.pickId != nil } }

        /// The squad as it is drawn becomes the player's: every slot keeps the Pokémon it shows (a copy as `pick`, a species row as `species`, nothing for an empty slot).
        /// Done once, at the first change; a squad already changed is left alone, as are the roles and the set mark.
        public mutating func fixing(_ shown: [FilledSlot]) {
            guard !changed else { return }
            for i in slots.indices where shown.indices.contains(i) {
                // A species pick that reads as a copy has both ids: the species is the row the player chose, so it is what is kept.
                if let key = shown[i].species { slots[i].pick = nil; slots[i].species = key }
                else { slots[i].pick = shown[i].entryId; slots[i].species = nil }
            }
            changed = true
        }

        /// Puts the Pokémon of `pickId` form (`pick`, `species`) into a slot.
        private mutating func put(_ pick: String?, _ species: String?, at i: Int) { slots[i].pick = pick; slots[i].species = species }

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
        }

        /// "Back to suggested squad": forgets every kept Pokémon, puts the roles back to the screen's defaults (`defaults`: its `HubSquads.default...Slots()`) and clears the
        /// "Squad set" mark. The squad then shows the suggestion again, as one never changed does.
        public mutating func backToSuggested(defaults: [SquadSlot]) {
            slots = defaults
            isSet = false
            changed = false
        }
    }

    /// A raid or Max squad with the last day of its event, which is when it is dropped.
    public struct EventSquad: Codable, Equatable {
        public var squad: Saved
        /// `yyyy-mm-dd`, the rotation row's `to`.
        public var endsOn: String
        public init(squad: Saved, endsOn: String) { self.squad = squad; self.endsOn = endsOn }
    }

    public var version: Int = 1
    /// Raid and Max squads by `eventKey`.
    public var raids: [String: EventSquad] = [:]
    public var max: [String: EventSquad] = [:]
    /// The Gym's six.
    public var gym = Saved(slots: HubSquads.defaultGymSlots())
    /// Rocket: three per leader, by leader name.
    public var rocket: [String: Saved] = [:]
    /// PvP: three per league (`gl`, `ul`, `ml`), with roles.
    public var pvp: [String: Saved] = [:]
    /// Available | Best, per screen (`SquadScreen.rawValue`); a screen with no entry reads Available.
    public var modes: [String: SquadMode] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey { case version, raids, max, gym, rocket, pvp, modes }

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
        return s
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
        return out
    }

    /// Both rules, as the app applies them when it opens a screen or finishes a scan.
    public func refreshed(today: String, rotation: [HubData.RotationRow], boxIds: Set<String>) -> SquadStore {
        pruned(today: today, rotation: rotation).reconciled(boxIds: boxIds)
    }
}
