import Foundation

// Port of src/extract/names.js: match a read name to the species the game would have shown. The
// game prints the base name, with "Mega" / "Alolan" / "Galarian" style prefixes; other forms (Hero,
// Altered, Origin...) are not in the name, so one display name can map to several game-master
// species. The solver picks between those by CP and HP.

private let regional: [String: String] = ["alolan": "Alola", "galarian": "Galar", "hisuian": "Hisui", "paldean": "Paldea"]
// The game prints "Nidoran♀" and "Nidoran♂". Tesseract could not read the symbol, so both share the
// display name "Nidoran" and the solver tells them apart by their stats (the export uses Poke
// Genie's names). Vision can read the symbol; see `nidoranSex`.
private let nidoranNames: [String: String] = ["nidoran_female": "Nidoran♀", "nidoran_male": "Nidoran♂"]

public struct NameCandidate: Equatable {
    public var display: String
    public var name: String
    public var form: String
    public var speciesIds: [String]
    /// `normalise(display)`, computed once (the matcher compares against every candidate per read).
    public let key: String

    public init(display: String, name: String, form: String, speciesIds: [String]) {
        self.display = display; self.name = name; self.form = form; self.speciesIds = speciesIds
        self.key = normalise(display)
    }
}

/// "Base name (Form)" split the way the JS regex /^(.*?)\s*\((.*)\)$/ does.
private func splitForm(_ speciesName: String) -> (base: String, form: String) {
    guard speciesName.hasSuffix(")"), let open = speciesName.firstIndex(of: "(") else { return (speciesName, "") }
    var base = String(speciesName[speciesName.startIndex..<open])
    while let last = base.last, last.isWhitespace { base.removeLast() }
    let form = String(speciesName[speciesName.index(after: open)..<speciesName.index(before: speciesName.endIndex)])
    return (base, form)
}

/// Base name and Poke Genie style form ("", "Hero", "Mega Y", "Alola") of a species.
public func nameAndForm(_ species: Species) -> (name: String, form: String) {
    let (base, form) = splitForm(species.name)
    if let n = nidoranNames[species.id] { return (n, "") }
    return (base, regional[form.lowercased()] ?? form)
}

/// Candidate display names from the species table.
public func displayNames(_ table: SpeciesTable) -> [NameCandidate] { displayNames(table.species) }

public func displayNames(_ species: [Species]) -> [NameCandidate] {
    var order = [String]()
    var byDisplay = [String: NameCandidate]()
    func add(_ display: String, _ name: String, _ form: String, _ id: String) {
        let key = normalise(display)
        if byDisplay[key] == nil { byDisplay[key] = NameCandidate(display: display, name: name, form: form, speciesIds: []); order.append(key) }
        byDisplay[key]!.speciesIds.append(id)
    }
    for p in species {
        if p.id.hasSuffix("_shadow") { continue } // same name on screen; the shadow flag is elsewhere
        if nidoranNames[p.id] != nil { add("Nidoran", "Nidoran", "", p.id); continue }
        let (base, form) = splitForm(p.name)
        let lower = form.lowercased()
        let isMega = lower == "mega" || lower == "mega x" || lower == "mega y" || lower == "primal"
        if isMega {
            let prefix = lower.hasPrefix("mega") ? "Mega" : "Primal"
            let suffix = (lower.hasSuffix(" x") || lower.hasSuffix(" y")) ? " " + String(form.suffix(1)).uppercased() : ""
            add("\(prefix) \(base)\(suffix)", base, form, p.id)
        } else if let reg = regional[lower] {
            add("\(form) \(base)", base, reg, p.id)
        } else { add(base, base, form, p.id) }
    }
    return order.map { byDisplay[$0]! }
}

public func normalise(_ text: String) -> String {
    var out = String.UnicodeScalarView()
    var lastSpace = true  // trims leading spaces and collapses runs
    for u in text.decomposedStringWithCanonicalMapping.lowercased().unicodeScalars {
        if (0x300...0x36F).contains(u.value) { continue }
        let ok = (u.value >= 97 && u.value <= 122) || (u.value >= 48 && u.value <= 57)
        if ok { out.append(u); lastSpace = false }
        else if !lastSpace { out.append(" "); lastSpace = true }
    }
    var s = String(out)
    if s.hasSuffix(" ") { s.removeLast() }
    return s
}

/// Levenshtein distance.
public func distance(_ a: String, _ b: String) -> Int {
    let x = Array(a.unicodeScalars), y = Array(b.unicodeScalars)
    let m = x.count, n = y.count
    if m == 0 { return n }
    if n == 0 { return m }
    var prev = Array(0...n)
    for i in 1...m {
        var cur = [i] + [Int](repeating: 0, count: n)
        for j in 1...n { cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1)) }
        prev = cur
    }
    return prev[n]
}

public struct NameMatch {
    public var candidate: NameCandidate
    public var distance: Int
    public var text: String
    /// The match used the whole text (trailing one-letter tokens aside), not the text with a word dropped.
    public var whole: Bool
    /// Matched by the Nidoran rule: the gender symbol was not (or not reliably) read.
    public var symbol: Bool = false
    /// A letter stuck to the name ("Nidorano"), which a misread Nidorino or Nidorina also gives.
    public var attached: Bool = false
}

/// "nidoran" plus at most one stray character, as the JS /^nidoran ?[a-z0-9]?$/.
private func isNidoranVariant(_ v: String) -> Bool {
    guard v.hasPrefix("nidoran") else { return false }
    var rest = Substring(v.dropFirst(7))
    if rest.hasPrefix(" ") { rest = rest.dropFirst() }
    if rest.isEmpty { return true }
    guard rest.count == 1, let u = rest.unicodeScalars.first else { return false }
    return (u.value >= 97 && u.value <= 122) || (u.value >= 48 && u.value <= 57)
}

/// Best candidate for a read name. Tries the whole text, then the text with stray one-letter or
/// punctuation tokens dropped (the edit-pencil icon often reads as a dot or a letter). Nil when
/// nothing is close enough.
public func matchName(_ text: String, _ candidates: [NameCandidate], maxRatio: Double = 0.25) -> NameMatch? {
    var variants = [String]()
    func addVariant(_ v: String) { if !variants.contains(v) { variants.append(v) } }
    let norm = normalise(text)
    if norm.isEmpty { return nil }
    addVariant(norm)
    let tokens = norm.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    addVariant(tokens.filter { $0.count > 1 }.joined(separator: " "))
    // The pencil icon sits after the name, so only trailing one-letter tokens may be dropped from a
    // "whole" match; a stray token in front could be what is left of "Alolan".
    var trimmed = tokens
    while trimmed.count > 1 && trimmed[trimmed.count - 1].count == 1 { trimmed.removeLast() }
    let wholeText: Set<String> = [norm, trimmed.joined(separator: " ")]
    if tokens.count > 1 {
        addVariant(tokens.dropFirst().joined(separator: " "))
        addVariant(tokens.dropLast().joined(separator: " "))
    }
    // "Nidoran" plus at most one stray character is Nidoran with its gender symbol misread; without
    // this it is as close to "Nidorino" as to "Nidoran". Checked on the whole text first, then on
    // the text with a word dropped (an overlay can add a word after the name).
    if let nidoran = candidates.first(where: { $0.key == "nidoran" }) {
        for v in variants where isNidoranVariant(v) {
            return NameMatch(candidate: nidoran, distance: 0, text: "nidoran", whole: wholeText.contains(v), symbol: true,
                             attached: v.count == 8 && !v.contains(" "))
        }
    }
    var best: NameMatch? = nil
    for v in variants where !v.isEmpty {
        for c in candidates {
            let key = c.key
            let limit = max(1, Int((Double(key.count) * maxRatio).rounded(.down)))
            if abs(v.count - key.count) > limit { continue }  // the distance is at least the length difference
            let d = distance(v, key)
            // Equally near, "Nidoran" gives way ("Nidorin" is Nidorina or Nidorino with a letter lost).
            let yields = best != nil && d == best!.distance && best!.candidate.display == "Nidoran" && c.display != "Nidoran"
            if d <= limit && (best == nil || d < best!.distance || yields
                              || (d == best!.distance && v.count > best!.text.count && c.display != "Nidoran")) {
                best = NameMatch(candidate: c, distance: d, text: v, whole: wholeText.contains(v))
            }
        }
    }
    return best
}

/// Fault 1: Vision, unlike Tesseract, may return the gender symbol itself ("Nidoran♀"). When the
/// raw text carries one, that is the sex; a stray letter or digit in its place is no evidence.
public func nidoranSex(inRawText text: String) -> String? {
    if text.contains("♀") { return "nidoran_female" }
    if text.contains("♂") { return "nidoran_male" }
    return nil
}
