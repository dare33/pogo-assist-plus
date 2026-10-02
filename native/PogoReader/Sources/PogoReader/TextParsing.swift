import Foundation

// Port of the parsers in src/extract/ocr.js. The recogniser itself changed (Vision, not
// Tesseract); the parsers are the same.

private func replacingO(_ text: String) -> [Character] {
    text.map { ($0 == "O" || $0 == "o") ? "0" : $0 }
}

private func isAsciiLetter(_ c: Character) -> Bool { c.isASCII && c.isLetter }
private func isAsciiDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }
private func isSpace(_ c: Character) -> Bool { c.isWhitespace }

/// Parse a CP read: "CP3028", "CP 3028", "P2651", "cp3O28", "ap2621", "CP4 262".
///
/// The figure is the digits at the end of the last token. Vision (unlike the Tesseract digit crops the JS
/// parser was written for) sometimes puts a space inside the figure and garbles the "CP" label, so:
/// - an O or o becomes a 0 only inside a token that has digits ("3O28"); "99 O" and "CP2 OO" end in a
///   letter token and are no read, never 990 or 200;
/// - two digit groups join only as a thousands split, one digit then exactly three ("CP4 262" is 4262,
///   "CP2 008" is 2008), the first attached to a CP-like prefix or alone; anything else with two groups
///   ("CP1 6", "CP1S 66", "CP1234 5") is no read;
/// - a letter between digits is no read ("CP1A86"), except a single leading digit that is a misread label
///   glyph ("5p2641");
/// - more than four digits in one group keep the last four (JS), fewer than two are no read.
public func parseCp(_ text: String) -> Int? {
    let raw = text.split(whereSeparator: { isSpace($0) }).map { Array($0) }
    let tokens: [[Character]] = raw.map { tok in
        tok.contains(where: isAsciiDigit) ? tok.map { ($0 == "O" || $0 == "o") ? "0" : $0 } : tok
    }
    guard let last = tokens.last else { return nil }
    var i = last.count
    while i > 0, isAsciiDigit(last[i - 1]) { i -= 1 }
    let run = Array(last[i...])
    guard !run.isEmpty else { return nil }                 // the last token must end in digits
    let before = Array(last[..<i])
    if before.contains(where: isAsciiDigit) {
        // Digits before the figure are allowed only as one leading digit followed by letters ("5p").
        let lead = before.prefix(while: isAsciiDigit), rest = before.dropFirst(lead.count)
        if !(lead.count == 1 && !rest.isEmpty && !rest.contains(where: isAsciiDigit)) { return nil }
    }
    var digits = run
    if before.isEmpty, tokens.count >= 2 {                 // the last token is the figure on its own
        let prev = tokens[tokens.count - 2]
        if prev.contains(where: isAsciiDigit) {
            // A digit group before it: only a thousands split ("4" + "262").
            var j = prev.count
            while j > 0, isAsciiDigit(prev[j - 1]) { j -= 1 }
            let prevRun = prev[j...], prevBefore = prev[..<j]
            guard prevRun.count == 1, run.count == 3, !prevBefore.contains(where: isAsciiDigit),
                  prevBefore.allSatisfy({ isAsciiLetter($0) }) else { return nil }
            digits = Array(prevRun) + run
        }
    }
    if digits.count < 2 { return nil }
    if digits.count > 4 { digits = Array(digits.suffix(4)) }
    return Int(String(digits))
}

public struct HP: Codable, Equatable, Hashable {
    public var current: Int
    public var max: Int
    public init(current: Int, max: Int) { self.current = current; self.max = max }
}

/// Parse "145 / 145 HP" style reads; nil when there is no read. A current above the max is a
/// truncated read (fault 5: on the iPad the team leader covers the end of the text, "139 / 13"), so
/// it is no read at all.
public func parseHp(_ text: String) -> HP? {
    let t = replacingO(text)
    var i = 0
    while i < t.count {
        defer { i += 1 }
        guard isAsciiDigit(t[i]) else { continue }
        var j = i
        while j < t.count, j - i < 3, isAsciiDigit(t[j]) { j += 1 }
        let a = String(t[i..<j])
        var k = j
        while k < t.count, isSpace(t[k]) { k += 1 }
        guard k < t.count, t[k] == "/" else { continue }
        k += 1
        while k < t.count, isSpace(t[k]) { k += 1 }
        var m = k
        while m < t.count, m - k < 3, isAsciiDigit(t[m]) { m += 1 }
        guard m > k else { continue }
        let hp = HP(current: Int(a)!, max: Int(String(t[k..<m]))!)
        return hp.current > hp.max ? nil : hp
    }
    return nil
}

// MARK: - read shape checks
// Vision sometimes reads a crop as if it were rotated 180 degrees ("dH 99 / 99" for "66 / 66 HP"),
// and there is no request option to stop it considering rotated text. The parsers above would take
// the digits out of such a read, so the frame reader first checks the SHAPE of the whole text.
// Rotated, a line's label ends up on the wrong side of the figures: letters before the HP digits,
// letters after the CP digits (after the LAST one: a garbled label can contain a digit, "5p2641"). The label itself is often misread (the iPad gives "ap2621", "SP2614",
// "165 / 165 Hi"), so only the SIDE of the letters is checked, never which letters they are.

/// A real HP read has no letters before its first digit and has a "/" after it.
public func hpReadHasValidShape(_ text: String) -> Bool {
    let t = replacingO(text)
    guard let firstDigit = t.firstIndex(where: isAsciiDigit) else { return false }
    if t[..<firstDigit].contains(where: isAsciiLetter) { return false }
    return t[firstDigit...].contains("/")
}

/// A real CP read has no letters after its last digit ("CP", or what Vision makes of it, comes first:
/// "5p2641", "ap2621"); a rotated one has them after the figures.
public func cpReadHasValidShape(_ text: String) -> Bool {
    let t = replacingO(text)
    guard let lastDigit = t.lastIndex(where: isAsciiDigit) else { return false }
    return !t[lastDigit...].contains(where: isAsciiLetter)
}
