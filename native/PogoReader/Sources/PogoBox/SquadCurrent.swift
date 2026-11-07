import Foundation

/// Design pass 2-5, rule 27: the tabs of a squad. Current is the squad the player saved (`SquadStore.current`); Available and Best are the suggestions, drawn from the box and the
/// tables each time and editable as drafts (`SquadDrafts`).
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

    /// The key the screen's view state (`SquadDrafts`) holds the squad under.
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
    /// The key an Available or Best edit is stored under: `SquadRef.key` and the tab, with the Raids style between them on Raids (`SquadDrafts.slot` plus the style).
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

    /// "Set this squad": `squad` becomes the Current and is marked set; a different Current it replaces goes to the history first, recorded with `source`, `edited` and `strength`
    /// (the screen's account of that earlier Current).
    public mutating func replaceCurrent(with squad: Saved, _ ref: SquadRef, source: SquadTab, edited: Bool, strength: Int?, date: Date) {
        if let old = current(ref), old.slots != squad.slots { pushHistory(old, ref, source: source, edited: edited, strength: strength, date: date) }
        var new = squad
        new.isSet = true
        setCurrent(new, ref)
        noteEnd(ref)
    }

    /// "✓ Squad set" tapped, or Delete current squad: the Current goes to the history and the squad keeps nothing again.
    public mutating func unsetCurrent(_ ref: SquadRef, strength: Int?, date: Date) {
        if let old = current(ref) { pushHistory(old, ref, source: .current, edited: false, strength: strength, date: date) }
        removeCurrent(ref)
    }

    /// "Set squad" on a history row: entry `index` becomes the Current (marked set, picks as the entry kept them; the app's reconcile empties any copy that left the box), the
    /// Current it replaces goes to the top of the history, and the entry leaves the list. Returns the Current it replaced, for Undo; nil when there was none or `index` is out of range.
    @discardableResult
    public mutating func restoreFromHistory(_ ref: SquadRef, index: Int, strength: Int?, date: Date) -> Saved? {
        guard let list = history[ref.key], list.indices.contains(index) else { return nil }
        let entry = list[index], previous = current(ref)
        var rest = list
        rest.remove(at: index)
        history[ref.key] = rest
        if let previous, previous.slots != entry.slots { pushHistory(previous, ref, source: .current, edited: false, strength: strength, date: date) }
        setCurrent(Saved(slots: entry.slots, isSet: true, changed: true), ref)
        noteEnd(ref)
        return previous
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

/// What a squad screen holds while the player is on it and drops when they leave (pass 2-5, rule 27): the tab each squad is on, the drafts (edits of Available and Best), and which
/// draft was just saved to Current. Never stored. Keyed by `SquadRef.key`. Pure, so the rules can be tested.
@available(*, deprecated, message: "slice 3 moves the screens to SquadStore.edits")
public struct SquadDrafts: Equatable {
    /// The account the drafts belong to (nil before the screen has attached to one).
    public private(set) var account: String?
    private var chosen: [String: SquadTab] = [:]
    private var drafts: [String: SquadStore.Saved] = [:]
    private var savedAs: [String: SquadStore.Saved] = [:]
    public init() {}

    private static func slot(_ key: String, _ tab: SquadTab) -> String { key + "|" + tab.rawValue }

    /// The screen is showing `account`'s squads. Another account's drafts, tab choices and saved notes are dropped, so a draft can never be saved into the wrong account's store.
    public mutating func switchAccount(_ new: String?) {
        guard new != account else { return }
        self = SquadDrafts()
        account = new
    }

    /// Drafts follow the box as the store does (rule 27): a draft pick whose copy left it is emptied (that slot alone then refills from the suggestion, and the screen keeps the
    /// refill in the draft). Species picks, roles and the rest are left alone.
    public func reconciled(boxIds: Set<String>) -> SquadDrafts {
        var out = self
        for (k, var d) in drafts {
            for i in d.slots.indices { if let p = d.slots[i].pick, !boxIds.contains(p) { d.slots[i].pick = nil; d.slots[i].fallback = nil } }
            out.drafts[k] = d
        }
        return out
    }

    /// The tab a squad shows: the one the player chose on this screen, else Current when the squad has one, else the remembered Available/Best choice.
    public func tab(_ key: String, hasCurrent: Bool, mode: SquadMode) -> SquadTab {
        if let c = chosen[key], c != .current || hasCurrent { return c }
        return hasCurrent ? .current : SquadTab(mode)
    }

    public mutating func select(_ tab: SquadTab, for key: String) { chosen[key] = tab }
    /// Back to the squad's default tab (Delete current squad).
    public mutating func clearTab(for key: String) { chosen[key] = nil }

    /// The edited Available or Best squad; nil while it has not been edited (the screen draws the suggestion).
    public func draft(_ key: String, _ tab: SquadTab) -> SquadStore.Saved? { drafts[Self.slot(key, tab)] }
    public mutating func setDraft(_ squad: SquadStore.Saved, _ key: String, _ tab: SquadTab) { drafts[Self.slot(key, tab)] = squad }

    /// The draft differs from the suggestion: the squad shows Save to Current and Reset.
    public func differs(_ key: String, _ tab: SquadTab) -> Bool { drafts[Self.slot(key, tab)]?.changed == true }

    /// Reset (and a change of Raids style): the draft is dropped at once and the tab draws the suggestion again.
    public mutating func reset(_ key: String, _ tab: SquadTab) {
        drafts[Self.slot(key, tab)] = nil
        savedAs[Self.slot(key, tab)] = nil
    }
    public mutating func resetAll(_ key: String) { for t in [SquadTab.available, .best] { reset(key, t) } }

    /// A change of Raids style: every Available and Best draft whose squad key starts with `prefix` was an edit of the other suggestion, so it goes; Current is untouched.
    public mutating func resetAll(keyPrefix prefix: String) {
        for k in drafts.keys where k.hasPrefix(prefix) { drafts[k] = nil }
        for k in savedAs.keys where k.hasPrefix(prefix) { savedAs[k] = nil }
    }

    /// The draft was saved to Current: the player stays on the tab, which says "Saved to Current" until the draft changes again.
    public mutating func didSave(_ squad: SquadStore.Saved, _ key: String, _ tab: SquadTab) {
        chosen[key] = tab
        drafts[Self.slot(key, tab)] = squad
        savedAs[Self.slot(key, tab)] = squad
    }

    /// "Saved to Current": the tab's draft is exactly what was last saved from it AND the stored Current is that squad still (slots, roles, species picks; the set mark is ignored).
    /// Deleting Current, replacing it from another tab or editing it all end it.
    public func justSaved(_ key: String, _ tab: SquadTab, current: SquadStore.Saved?) -> Bool {
        guard let s = savedAs[Self.slot(key, tab)], drafts[Self.slot(key, tab)] == s, let current else { return false }
        return current.slots == s.slots
    }

    /// The squad's saved notes are dropped (Delete current squad).
    public mutating func clearSaved(_ key: String) { for t in [SquadTab.available, .best] { savedAs[Self.slot(key, t)] = nil } }
}
