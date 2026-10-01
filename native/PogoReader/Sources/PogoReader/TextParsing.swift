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
