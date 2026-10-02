import Foundation

// Port of the parsers in src/extract/ocr.js. The recogniser itself changed (Vision, not
// Tesseract); the parsers are the same.

private func replacingO(_ text: String) -> [Character] {
    text.map { ($0 == "O" || $0 == "o") ? "0" : $0 }
}

private func isAsciiLetter(_ c: Character) -> Bool { c.isASCII && c.isLetter }
private func isAsciiDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }
private func isSpace(_ c: Character) -> Bool { c.isWhitespace }

/// Parse "CP3028", "CP 3028", "P2651", "cp3O28" style reads: the digits after the last letter,
/// two to four of them (the last four if more).
public func parseCp(_ text: String) -> Int? {
    let t = replacingO(text)
    var tail = t[...]
    if let lastLetter = t.lastIndex(where: isAsciiLetter) { tail = t[(lastLetter + 1)...] }
    var end = tail.endIndex
    while end > tail.startIndex, isSpace(tail[tail.index(before: end)]) { end = tail.index(before: end) }
    var start = end
    while start > tail.startIndex, isAsciiDigit(tail[tail.index(before: start)]) { start = tail.index(before: start) }
    var digits = Array(tail[start..<end])
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

/// A real HP read is digits, "/", digits, then at most "HP" (and a stray digit or punctuation): no
/// letters may come before the first digit. `parseHp` alone would accept "dH 99 / 99".
public func hpReadHasValidShape(_ text: String) -> Bool {
    let t = replacingO(text)
    guard let firstDigit = t.firstIndex(where: isAsciiDigit) else { return false }
    if t[..<firstDigit].contains(where: isAsciiLetter) { return false }
    // Whatever follows the figures may only be H / P letters (the "HP" label, any case).
    guard let slash = t.firstIndex(of: "/") else { return false }
    var i = slash + 1
    while i < t.count, isSpace(t[i]) || isAsciiDigit(t[i]) { i += 1 }
    return t[i...].allSatisfy { "HPhp".contains($0) || isSpace($0) || $0 == "1" || $0 == "." || $0 == "l" || $0 == "I" }
}

/// A real CP read is the "CP" prefix (or part of it: "P", "C", or nothing) then digits. Letters
/// other than C and P anywhere before the digits mean a garbled or rotated read.
public func cpReadHasValidShape(_ text: String) -> Bool {
    let t = replacingO(text)
    guard let firstDigit = t.firstIndex(where: isAsciiDigit) else { return false }
    return t[..<firstDigit].allSatisfy { !isAsciiLetter($0) || "CPcp".contains($0) }
}
