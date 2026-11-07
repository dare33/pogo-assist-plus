import Foundation

/// Design pass 2-5, rule 27: the tabs of a squad. Current is the squad the player saved (`SquadStore.current`); Available and Best are the suggestions, drawn from the box and the
/// tables each time; the player's edits of them are kept (`SquadStore.edits`).
public enum SquadTab: String, Codable, CaseIterable {
    case current, available, best

    /// The list a tab draws from. Current is drawn as kept (nothing hides a kept pick) but lists the player's own box, as Available does.
    public var mode: SquadMode { self == .best ? .best : .available }
    public var title: String { self == .current ? "Current" : self == .available ? "Available" : "Best" }
    public init(_ mode: SquadMode) { self = mode == .best ? .best : .available }
}

/// One squad of a screen, as the store keeps it: a raid or Max event's, the Gym's six, a Rocket leader's three, a PvP league's three.
public enum SquadRef {
    case event(row: HubData.RotationRow, screen: SquadScreen)
    case gym
    case rocket(leader: String)
    case pvp(league: String)

    public var screen: SquadScreen {
        switch self {
        case let .event(_, screen): return screen
        case .gym: return .gym
        case .rocket: return .rocket
        case .pvp: return .pvp
        }
    }

    /// The key the screen's view state (`SquadTabChoices`) holds the squad under.
    public var key: String {
        switch self {
        case let .event(row, screen): return "\(screen.rawValue)|" + SquadStore.eventKey(row)
        case .gym: return "gym"
        case let .rocket(leader): return "rocket|\(leader)"
        case let .pvp(league): return "pvp|\(league)"
        }
    }
}

/// One earlier Current squad (pass 2-6, rule 27): what the squad was, when it stopped being the Current, and how it came to be. Never reconciled against the box.
public struct HistoryEntry: Codable, Equatable {
    public var date: Date
    public var slots: [SquadSlot]
    /// The tab the Current was set from: `.available`, `.best`, or `.current` when it came from an undo, a restore or edits made on Current.
    public var source: SquadTab
    /// It differed from that tab's suggestion.
    public var edited: Bool
    /// The bar's whole percent when the entry was recorded; nil when it was not worked out. The screen passes it; the store never computes it.
    public var strength: Int?
    public init(date: Date, slots: [SquadSlot], source: SquadTab, edited: Bool, strength: Int?) {
        self.date = date; self.slots = slots; self.source = source; self.edited = edited; self.strength = strength
    }
}

extension SquadStore {
    /// The key an Available or Best edit is stored under: `SquadRef.key` and the tab, with the Raids style between them on Raids.
    public static func editKey(_ ref: SquadRef, _ tab: SquadTab, style: RaidStyle) -> String {
        ref.screen == .raids ? "\(ref.key)|\(style.rawValue)|\(tab.rawValue)" : "\(ref.key)|\(tab.rawValue)"
    }

    /// Rule 27 (pass 2-6): "set" and "has a Current" are one thing.
    public func isSet(_ ref: SquadRef) -> Bool { current(ref) != nil }

    // MARK: kept edits of Available and Best

    /// The kept edit of the tab (Current has none); nil while the squad matches the suggestion, which the screen then draws.
    public func edit(_ ref: SquadRef, _ tab: SquadTab, style: RaidStyle) -> Saved? {
        tab == .current ? nil : edits[Self.editKey(ref, tab, style: style)]
    }
    public mutating func setEdit(_ squad: Saved, _ ref: SquadRef, _ tab: SquadTab, style: RaidStyle) {
        guard tab != .current else { return }
        edits[Self.editKey(ref, tab, style: style)] = squad
        noteEnd(ref)
    }
    /// "Reset to suggestion": the kept edit is dropped at once.
    public mutating func resetEdit(_ ref: SquadRef, _ tab: SquadTab, style: RaidStyle) { edits[Self.editKey(ref, tab, style: style)] = nil }
    /// The tab holds a kept edit that differs from its suggestion: the squad shows "Reset to suggestion".
    public func differs(_ ref: SquadRef, _ tab: SquadTab, style: RaidStyle) -> Bool { edit(ref, tab, style: style)?.changed == true }

    /// Remembers an event's last day for `pruned`.
    private mutating func noteEnd(_ ref: SquadRef) {
        if case let .event(row, _) = ref { eventEnds[ref.key] = row.to }
    }

    // MARK: history

    /// Records `saved` as an earlier Current of the squad: newest first, not again when the newest entry already holds the same slots, at most `historyLimit`.
    public mutating func pushHistory(_ saved: Saved, _ ref: SquadRef, source: SquadTab, edited: Bool, strength: Int?, date: Date) {
        var list = history[ref.key] ?? []
        guard list.first?.slots != saved.slots else { return }
        list.insert(HistoryEntry(date: date, slots: saved.slots, source: source, edited: edited, strength: strength), at: 0)
        history[ref.key] = Array(list.prefix(Self.historyLimit))
        noteEnd(ref)
    }

    /// "Set this squad": `squad` becomes the Current and is marked set, remembering `source` (the tab it was set from), `edited` (it differed from that tab's suggestion) and `strength`
    /// (the bar's whole percent now). A different Current it replaces goes to the history first, recorded from that Current's OWN stored source, edited and strength (an older file's
    /// Current reads as set from Current, unedited, no figure).
    public mutating func replaceCurrent(with squad: Saved, _ ref: SquadRef, source: SquadTab, edited: Bool, strength: Int?, date: Date) {
        if let old = current(ref), old.slots != squad.slots { pushHistory(old, ref, source: old.source ?? .current, edited: old.edited ?? false, strength: old.strength, date: date) }
        var new = squad
        new.isSet = true
        new.source = source; new.edited = edited; new.strength = strength
        setCurrent(new, ref)
        noteEnd(ref)
    }

    /// "✓ Squad set" tapped, or Delete current squad: the Current goes to the history and the squad keeps nothing again. `strength` is the bar's figure for the Current being unset
    /// (the screen is showing it); without one the entry keeps the figure the Current was set with.
    public mutating func unsetCurrent(_ ref: SquadRef, strength: Int?, date: Date) {
        if let old = current(ref) { pushHistory(old, ref, source: old.source ?? .current, edited: old.edited ?? false, strength: strength ?? old.strength, date: date) }
        removeCurrent(ref)
    }

    /// "Set squad" on a history row: entry `index` becomes the Current (marked set, picks as the entry kept them; the app's reconcile empties any copy that left the box), the
    /// Current it replaces goes to the top of the history, and the entry leaves the list. Returns the Current it replaced, for the screen; nil when there was none or `index` is out
    /// of range. `strength` is the bar's figure for the Current being replaced.
    @discardableResult
    public mutating func restoreFromHistory(_ ref: SquadRef, index: Int, strength: Int?, date: Date) -> Saved? {
        guard let list = history[ref.key], list.indices.contains(index) else { return nil }
        let entry = list[index], previous = current(ref)
        var rest = list
        rest.remove(at: index)
        history[ref.key] = rest
        if let previous, previous.slots != entry.slots { pushHistory(previous, ref, source: previous.source ?? .current, edited: previous.edited ?? false, strength: strength ?? previous.strength, date: date) }
        setCurrent(Saved(slots: entry.slots, isSet: true, changed: true, source: entry.source, edited: entry.edited, strength: entry.strength), ref)
        noteEnd(ref)
        return previous
    }

    /// Undo of a replace or an unset: history entry 0 goes back as the Current WITHOUT pushing the Current it replaces (the squad that was just set is dropped), and the entry leaves
    /// the list. false when there is no entry.
    @discardableResult
    public mutating func undoReplace(_ ref: SquadRef) -> Bool {
        guard var list = history[ref.key], let entry = list.first else { return false }
        list.removeFirst()
        history[ref.key] = list
        setCurrent(Saved(slots: entry.slots, isSet: true, changed: true, source: entry.source, edited: entry.edited, strength: entry.strength), ref)
        noteEnd(ref)
        return true
    }
}

extension SquadStore {
    /// The squad's Current squad; nil when the player has kept nothing (the screen then shows the suggestions).
    public func current(_ ref: SquadRef) -> Saved? {
        let saved: Saved?
        switch ref {
        case let .event(row, screen):
            let key = Self.eventKey(row)
            saved = screen == .raids ? raids[key]?.squad : screen == .max ? max[key]?.squad : nil
        case .gym: saved = gym
        case let .rocket(leader): saved = rocket[leader]
        case let .pvp(league): saved = pvp[league]
        }
        return saved.flatMap { $0.hasCurrent ? $0 : nil }
    }

    /// Stores `squad` as the squad's Current.
    public mutating func setCurrent(_ squad: Saved, _ ref: SquadRef) {
        switch ref {
        case let .event(row, screen): saveEventSquad(squad, row: row, screen: screen)
        case .gym: gym = squad
        case let .rocket(leader): rocket[leader] = squad
        case let .pvp(league): pvp[league] = squad
        }
    }

    /// The squad keeps nothing again (its picks, roles and "Squad set" mark), with no history entry.
    fileprivate mutating func removeCurrent(_ ref: SquadRef) {
        switch ref {
        case let .event(row, screen):
            let key = Self.eventKey(row)
            if screen == .raids { raids[key] = nil } else if screen == .max { max[key] = nil }
        case .gym: gym = Saved(slots: HubSquads.defaultGymSlots())
        case let .rocket(leader): rocket[leader] = nil
        case let .pvp(league): pvp[league] = nil
        }
    }

    /// "Delete current squad": the same as `unsetCurrent` (the Current goes to the history), with no figure for the entry.
    public mutating func deleteCurrent(_ ref: SquadRef) { unsetCurrent(ref, strength: nil, date: Date()) }
}

/// What a squad screen holds while the player is on it and drops when they leave: the tab each squad is on. Never stored (the kept edits are `SquadStore.edits`; pass 2-6 removed the
/// in-memory drafts). Keyed by `SquadRef.key`. Pure, so the rules can be tested.
public struct SquadTabChoices: Equatable {
    /// The account the choices belong to (nil before the screen has attached to one).
    public private(set) var account: String?
    private var chosen: [String: SquadTab] = [:]
    public init() {}

    /// The screen is showing `account`'s squads. Another account's choices are dropped.
    public mutating func switchAccount(_ new: String?) {
        guard new != account else { return }
        self = SquadTabChoices()
        account = new
    }

    /// The tab a squad shows: the one the player chose on this screen, else Current when the squad has one, else the remembered Available/Best choice.
    public func tab(_ key: String, hasCurrent: Bool, mode: SquadMode) -> SquadTab {
        if let c = chosen[key], c != .current || hasCurrent { return c }
        return hasCurrent ? .current : SquadTab(mode)
    }

    public mutating func select(_ tab: SquadTab, for key: String) { chosen[key] = tab }
    /// Back to the squad's default tab.
    public mutating func clearTab(for key: String) { chosen[key] = nil }
}
