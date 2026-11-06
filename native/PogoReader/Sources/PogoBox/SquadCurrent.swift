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

    /// "Delete current squad": the squad keeps nothing again (its picks, roles and "Squad set" mark), and shows the suggestions.
    public mutating func deleteCurrent(_ ref: SquadRef) {
        switch ref {
        case let .event(row, screen):
            let key = Self.eventKey(row)
            if screen == .raids { raids[key] = nil } else if screen == .max { max[key] = nil }
        case .gym: gym = Saved(slots: HubSquads.defaultGymSlots())
        case let .rocket(leader): rocket[leader] = nil
        case let .pvp(league): pvp[league] = nil
        }
    }
}

/// What a squad screen holds while the player is on it and drops when they leave (pass 2-5, rule 27): the tab each squad is on, the drafts (edits of Available and Best), and which
/// draft was just saved to Current. Never stored. Keyed by `SquadRef.key`. Pure, so the rules can be tested.
public struct SquadDrafts: Equatable {
    private var chosen: [String: SquadTab] = [:]
    private var drafts: [String: SquadStore.Saved] = [:]
    private var savedAs: [String: SquadStore.Saved] = [:]
    public init() {}

    private static func slot(_ key: String, _ tab: SquadTab) -> String { key + "|" + tab.rawValue }

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

    /// The draft was saved to Current: the player stays on the tab, which says "Saved to Current" until the draft changes again.
    public mutating func didSave(_ squad: SquadStore.Saved, _ key: String, _ tab: SquadTab) {
        chosen[key] = tab
        drafts[Self.slot(key, tab)] = squad
        savedAs[Self.slot(key, tab)] = squad
    }

    /// "Saved to Current": the tab's draft is exactly what was last saved.
    public func justSaved(_ key: String, _ tab: SquadTab) -> Bool {
        guard let s = savedAs[Self.slot(key, tab)] else { return false }
        return drafts[Self.slot(key, tab)] == s
    }
}
