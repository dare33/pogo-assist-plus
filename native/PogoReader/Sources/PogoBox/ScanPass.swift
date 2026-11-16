import Foundation

/// A filtered pass: the player types a storage search in the game (`dynamax`) and scans as usual, so every Pokémon the scan reads is one the game's own search selected.
/// Saved as a partial scan with the pass as an optional string (`StoredScan.pass`, `PendingScanMeta.pass`, `BroadcastState.pass`): no enum case on `BoxStore.Kind`, so an
/// older build still reads the scan, and a value this build does not know decodes as no pass.
public enum ScanPass: String, CaseIterable, Codable, Equatable {
    case shadow, purified, dynamax, gigantamax

    /// What the player types in the game's storage search.
    public var searchWord: String { rawValue }
    /// "Dynamax".
    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    /// "Dynamax pass".
    public var passName: String { title + " pass" }

    /// The passes Greg wants that cannot be scanned yet (31 Oct 2026, "placeholder 'coming soon' tag until scans are developed for it"): the Scan screen lists them tagged
    /// "Coming soon", not choosable. They are not cases of this enum, so nothing can save, store or broadcast one.
    public static let comingSoon = ["Lucky", "Shiny", "Background"]

    /// The pass for a stored string; nil for none or one this build does not know.
    public init?(stored: String?) {
        guard let stored, let p = ScanPass(rawValue: stored) else { return nil }
        self = p
    }

    /// Shadow and Purified are one field with a hand value that outranks a pass; Dynamax and Gigantamax are on-only marks.
    var shadowValue: Int? { self == .shadow ? 1 : (self == .purified ? 2 : nil) }
}

/// More than this share of a pass's rows matching no box entry means the search was probably mistyped: the review asks before saving it as a pass.
/// The plan said about 20%, but Greg's genuine Dynamax pass of 25 Oct 2026 (61 rows) has 14 rows (23%) that match no entry of his 22 Oct box: 13 are species the box did not hold
/// (Uxie, Sneasel, Weavile, Gengar), caught or added since. The threshold is 30% so a real pass does not trip it (implementer call).
public enum PassGuard {
    public static let threshold = 0.30
    /// `unmatched` rows of `total`.
    public static func fires(unmatched: Int, total: Int) -> Bool { total > 0 && Double(unmatched) / Double(total) > threshold }
}
