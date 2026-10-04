import Foundation

// The parsers of src/extract/ocr.js, adapted to Vision. `parseHp` is the JS parser unchanged; `parseCp` is NOT
// a port any more: Vision splits and garbles the figure differently from Tesseract's digit crops, so it has its own
// rules (see its doc comment), and it refuses what the JS parser would have repaired (five digits, a leading zero).

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
/// - a letter or separator between digits is no read ("1A86", "CP 1A86", "2.641", "CP 2,641", "CP²641"), except
///   one leading digit that is a misread C or the O of an "op" label (0, 5, 6 or 8) followed by exactly one letter: "5p2641", "8p2611", "op2614" (any
///   letter, figure of three digits or more) and "5p86" (a P, a figure of two digits); "5pX2641" and "1A862" are not;
/// - a leading zero in the figure is a misread ("CP0123", "CPO28") and so is a figure of more than four digits
///   ("CP12345", "23028"): no read, the last digits are not kept; a result below 10 is no read ("CP0 001"), and a
///   lone O or o token before the figure is no read ("CP O 28", "CP o 1500");
/// - fewer than two digits are no read.
public func parseCp(_ text: String) -> Int? {
    if let v = slashSevenCp(text) { return v }
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
    // A digit-like character that is not an ASCII digit ("²") next to the figure is a garbled digit, not a label.
    if before.contains(where: { $0.isNumber && !isAsciiDigit($0) }) { return nil }
    if before.contains(where: isAsciiDigit) {
        // Digits before the figure are allowed only as one leading digit that a C or the o of "op" can be misread as (0, 5, 6, 8) followed
        // by exactly one letter ("5p"); a short figure needs that letter to be the P of "CP" ("5p86").
        let lead = before.prefix(while: isAsciiDigit), rest = before.dropFirst(lead.count)
        guard lead.count == 1, "0568".contains(lead[lead.startIndex]), rest.count == 1, isAsciiLetter(rest[rest.startIndex]) else { return nil }
        if run.count < 3 && !"pP".contains(rest[rest.startIndex]) { return nil }
    }
    var digits = run
    if before.isEmpty, tokens.count >= 2 {                 // the last token is the figure on its own
        let prev = tokens[tokens.count - 2]
        if !prev.contains(where: isAsciiDigit), prev.allSatisfy({ $0 == "O" || $0 == "o" }) { return nil }   // "CP O 28"
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
    if digits.count < 2 || digits.count > 4 || digits[0] == "0" { return nil }
    guard let value = Int(String(digits)), value >= 10 else { return nil }
    return value
}

/// Vision reads a leading 7 of the CP as "/" ("CP/68" for 768, device run 8): the label "CP" (either case), optional spaces, a "/",
/// optional spaces and one to three digits, and nothing else. The slash is then the digit 7, so the figure has two to four digits.
/// Only this shape: a slash anywhere else ("12/34", "CP 12/34", "CP1/86", "CP19/") is not a 7, and without the label nothing changes.
func slashSevenCp(_ text: String) -> Int? {
    let t = Array(text.trimmingCharacters(in: .whitespaces))
    var i = 0
    guard t.count >= 4, "cC".contains(t[0]), "pP".contains(t[1]) else { return nil }
    i = 2
    while i < t.count, isSpace(t[i]) { i += 1 }
    guard i < t.count, t[i] == "/" else { return nil }
    i += 1
    while i < t.count, isSpace(t[i]) { i += 1 }
    let digits = t[i...].map { ($0 == "O" || $0 == "o") ? Character("0") : $0 }
    guard (1...3).contains(digits.count), digits.allSatisfy(isAsciiDigit) else { return nil }
    return Int("7" + String(digits))
}

public struct HP: Codable, Equatable, Hashable {
    public var current: Int
    public var max: Int
    public init(current: Int, max: Int) { self.current = current; self.max = max }
    /// What identifies a card by its HP: the MAX only. The current HP changes with battles and, on a damaged
    /// card, is the figure most often misread between frames (19 / 190 then 9 / 190); it is never part of a
    /// card's identity (the box, the grouper and the merge already use the max).
    public var identity: String { String(max) }
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
    if slashSevenCp(text) != nil { return true }
    let t = replacingO(text)
    guard let lastDigit = t.lastIndex(where: isAsciiDigit) else { return false }
    return !t[lastDigit...].contains(where: isAsciiLetter)
}
