import Foundation

/// Rewrites a JSON document's TEXT, changing only the numbers and strings at the paths it is given and copying every other byte as it was. Needed because reading a
/// document into `JSONSerialization` objects and writing it out again can change a number it was not asked to touch (Foundation parses 17-digit text to a neighbouring
/// Double for some values), and decoding into model types normalises fields. A path is an array of components, a key or an array element, never a joined string (a key
/// may contain any character). The rewrite fails (nil) on text that is not well-formed JSON, that holds an object with the same key twice (after decoding escapes: the
/// parsers keep the first of two and a reader may keep the last, so what was checked may not be what is read), or that nests deeper than `maxDepth` containers, one inside another, counting the outermost (the check must not
/// overflow a small stack). With no paths it is therefore a check of exactly two things, repeated keys and depth: `JSONTextEdit().apply(to:) != nil` says the document has neither.
/// It does NOT check every scalar or escape (`{"a":tru}` passes), so a caller must also parse the document with Foundation, as every caller here does.
///
/// Bytes outside the replaced values are copied as they were. A replaced number is written in Swift's shortest form that reads back as the same Double (so "119757.60" may
/// become "119757.6"); a replaced string is written by Foundation (its escapes may differ, "\/" may become "/"); a string whose rewritten text is equal keeps its bytes.
struct JSONTextEdit {
    enum Step: Hashable { case key(String), element }
    static let maxDepth = 256

    /// Number paths: the value is replaced by `transform(value)`. A path whose value is null is left alone; any other type there, an object or a list included, makes the edit fail.
    var numbers: Set<[Step]> = []
    var transform: (Double) -> Double = { $0 }
    /// String paths: the value is replaced by `rewrite(string)`. Another type there, an object or a list included, makes the edit fail.
    var strings: Set<[Step]> = []
    var rewrite: (String) -> String = { $0 }

    func apply(to data: Data) -> Data? {
        var run = Run(bytes: [UInt8](data), edit: self)
        guard run.document(), run.skipSpace(), run.i == run.bytes.count else { return nil }
        return Data(run.out)
    }

    /// Iterative on purpose (an explicit stack, no recursion): a deeply nested document must fail on the depth cap, not on the stack of whatever thread runs this.
    private struct Run {
        let bytes: [UInt8]
        let edit: JSONTextEdit
        var i = 0
        var out = [UInt8]()
        /// One entry per open container: the keys an object has used so far, or nil for an array.
        var open = [Set<String>?]()
        var path = [Step]()
        init(bytes: [UInt8], edit: JSONTextEdit) { self.bytes = bytes; self.edit = edit; out.reserveCapacity(bytes.count + 64) }

        /// Copies white space; true always (so it can sit in a guard chain).
        @discardableResult mutating func skipSpace() -> Bool {
            while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { out.append(bytes[i]); i += 1 }
            return true
        }

        mutating func document() -> Bool {
            var wantValue = true
            while true {
                if wantValue {
                    skipSpace()
                    guard i < bytes.count else { return false }
                    switch bytes[i] {
                    case UInt8(ascii: "{"), UInt8(ascii: "["):
                        let isObject = bytes[i] == UInt8(ascii: "{"), close = isObject ? UInt8(ascii: "}") : UInt8(ascii: "]")
                        guard open.count < JSONTextEdit.maxDepth, !edit.numbers.contains(path), !edit.strings.contains(path) else { return false }
                        out.append(bytes[i]); i += 1
                        skipSpace()
                        if i < bytes.count, bytes[i] == close { out.append(bytes[i]); i += 1; wantValue = false; continue }
                        open.append(isObject ? Set<String>() : nil)
                        path.append(isObject ? .key("") : .element)
                        if isObject { guard key() else { return false } }
                    default:
                        guard scalar() else { return false }
                        wantValue = false
                    }
                } else {
                    if open.isEmpty { return true }
                    skipSpace()
                    guard i < bytes.count else { return false }
                    let c = bytes[i]
                    out.append(c); i += 1
                    if open[open.count - 1] != nil {
                        if c == UInt8(ascii: ",") { guard key() else { return false }; wantValue = true }
                        else if c == UInt8(ascii: "}") { open.removeLast(); path.removeLast() }
                        else { return false }
                    } else {
                        if c == UInt8(ascii: ",") { wantValue = true }
                        else if c == UInt8(ascii: "]") { open.removeLast(); path.removeLast() }
                        else { return false }
                    }
                }
            }
        }

        /// A key and its colon, in the innermost object. False on a repeated key (decoded, so "t" and "t" are the same).
        mutating func key() -> Bool {
            skipSpace()
            guard i < bytes.count, bytes[i] == UInt8(ascii: "\""), let raw = stringToken(),
                  let key = try? JSONSerialization.jsonObject(with: Data(raw), options: .fragmentsAllowed) as? String,
                  open[open.count - 1]!.insert(key).inserted else { return false }
            out.append(contentsOf: raw)
            skipSpace()
            guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { return false }
            out.append(bytes[i]); i += 1
            path[path.count - 1] = .key(key)
            return true
        }

        /// A string, number or literal at the current path.
        mutating func scalar() -> Bool {
            if bytes[i] == UInt8(ascii: "\"") {
                guard let raw = stringToken(), !edit.numbers.contains(path) else { return false }
                if edit.strings.contains(path) {
                    guard let s = try? JSONSerialization.jsonObject(with: Data(raw), options: .fragmentsAllowed) as? String,
                          case let new = edit.rewrite(s),
                          let d = try? JSONSerialization.data(withJSONObject: new, options: [.fragmentsAllowed, .withoutEscapingSlashes]) else { return false }
                    out.append(contentsOf: new == s ? raw : Array(d))
                } else { out.append(contentsOf: raw) }
                return true
            }
            let start = i
            while i < bytes.count, !([0x2C, 0x5D, 0x7D, 0x20, 0x09, 0x0A, 0x0D].contains(bytes[i])) { i += 1 }
            let token = Array(bytes[start..<i])
            guard !token.isEmpty, !edit.strings.contains(path) else { return false }
            if edit.numbers.contains(path) {
                if token == Array("null".utf8) { out.append(contentsOf: token); return true }
                guard let text = String(bytes: token, encoding: .utf8), let v = Double(text), v.isFinite else { return false }
                let moved = edit.transform(v)
                guard moved.isFinite else { return false }
                out.append(contentsOf: Array(String(describing: moved).utf8))
            } else { out.append(contentsOf: token) }
            return true
        }

        /// The raw bytes of the string at `i` (quotes included), copied to nowhere: the caller decides what to write.
        mutating func stringToken() -> [UInt8]? {
            let start = i
            i += 1
            while i < bytes.count {
                if bytes[i] == UInt8(ascii: "\\") { i += 2; continue }
                if bytes[i] == UInt8(ascii: "\"") { i += 1; return Array(bytes[start..<i]) }
                i += 1
            }
            return nil
        }
    }
}
