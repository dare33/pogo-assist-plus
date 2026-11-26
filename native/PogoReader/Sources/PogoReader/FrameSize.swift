/// The pixel size of the frame a scan's first Pokémon was read from, and whether a later read frame had another size (a foldable phone's two screens
/// give different frames). Pure, so the rule is tested: the broadcast extension calls `note` for each frame that yields a card and copies the three fields into
/// its state. Integers only; nothing is allocated.
public struct FrameSize: Equatable {
    public var width: Int?
    public var height: Int?
    /// nil until a later read frame has a size other than the first; then true (never reset within a scan).
    public var changed: Bool?

    public init(width: Int? = nil, height: Int? = nil, changed: Bool? = nil) { self.width = width; self.height = height; self.changed = changed }

    /// The first call records the size; later calls with the same size do nothing; a different size sets `changed` and keeps the first size.
    public mutating func note(width w: Int, height h: Int) {
        guard let first = width, let firstH = height else { width = w; height = h; return }
        if changed == nil, w != first || h != firstH { changed = true }
    }
}
