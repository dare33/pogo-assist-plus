import Foundation

/// Rewrites a JSON document's TEXT, changing only the numbers and strings at the paths it is given and copying every other byte as it was. Needed because reading a
/// document into `JSONSerialization` objects and writing it out again can change a number it was not asked to touch (Foundation parses 17-digit text to a neighbouring
/// Double for some values), and decoding into model types normalises fields. A path is the keys from the top joined by "/", with "[]" for any array element
/// ("rows/[]/frames/[]/time"). The input must be well-formed JSON (callers have already parsed it); anything this cannot follow returns nil.
struct JSONTextEdit {
    /// Number paths: the value is replaced by `transform(value)`. A path whose value is null is left alone; any other type there makes the edit fail.
    var numbers: Set<String> = []
    var transform: (Double) -> Double = { $0 }
    /// String paths: the value is replaced by `rewrite(string)`. Another type there makes the edit fail.
    var strings: Set<String> = []
    var rewrite: (String) -> String = { $0 }

    func apply(to data: Data) -> Data? {
        var run = Run(bytes: [UInt8](data), edit: self)
        guard run.value(path: []), run.skipSpace(), run.i == run.bytes.count else { return nil }
        return Data(run.out)
    }

    private struct Run {
        let bytes: [UInt8]
        let edit: JSONTextEdit
        var i = 0
        var out = [UInt8]()
        init(bytes: [UInt8], edit: JSONTextEdit) { self.bytes = bytes; self.edit = edit; out.reserveCapacity(bytes.count + 64) }

        /// Copies white space; true always (so it can sit in a guard chain).
        @discardableResult mutating func skipSpace() -> Bool {
            while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { out.append(bytes[i]); i += 1 }
            return true
        }

        mutating func value(path: [String]) -> Bool {
            skipSpace()
            guard i < bytes.count else { return false }
            let here = path.joined(separator: "/")
            switch bytes[i] {
            case UInt8(ascii: "{"): return object(path)
            case UInt8(ascii: "["): return array(path)
            case UInt8(ascii: "\""):
                guard let raw = stringToken(), !edit.numbers.contains(here) else { return false }
                if edit.strings.contains(here) {
                    guard let s = try? JSONSerialization.jsonObject(with: Data(raw), options: .fragmentsAllowed) as? String,
                          let d = try? JSONSerialization.data(withJSONObject: edit.rewrite(s), options: [.fragmentsAllowed, .withoutEscapingSlashes]) else { return false }
                    out.append(contentsOf: d)
                } else { out.append(contentsOf: raw) }
                return true
            default:
                let start = i
                while i < bytes.count, !([0x2C, 0x5D, 0x7D, 0x20, 0x09, 0x0A, 0x0D].contains(bytes[i])) { i += 1 }
                let token = Array(bytes[start..<i])
                guard !token.isEmpty, !edit.strings.contains(here) else { return false }
                if edit.numbers.contains(here) {
                    if token == Array("null".utf8) { out.append(contentsOf: token); return true }
                    guard let text = String(bytes: token, encoding: .utf8), let v = Double(text), v.isFinite else { return false }
                    let moved = edit.transform(v)
                    guard moved.isFinite else { return false }
                    out.append(contentsOf: Array(String(describing: moved).utf8))
                } else { out.append(contentsOf: token) }
                return true
            }
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

        mutating func object(_ path: [String]) -> Bool {
            out.append(bytes[i]); i += 1
            skipSpace()
            if i < bytes.count, bytes[i] == UInt8(ascii: "}") { out.append(bytes[i]); i += 1; return true }
            while true {
                skipSpace()
                guard i < bytes.count, bytes[i] == UInt8(ascii: "\""), let raw = stringToken(),
                      let key = try? JSONSerialization.jsonObject(with: Data(raw), options: .fragmentsAllowed) as? String else { return false }
                out.append(contentsOf: raw)
                skipSpace()
                guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { return false }
                out.append(bytes[i]); i += 1
                guard value(path: path + [key]) else { return false }
                skipSpace()
                guard i < bytes.count else { return false }
                out.append(bytes[i]); i += 1
                if bytes[i - 1] == UInt8(ascii: "}") { return true }
                guard bytes[i - 1] == UInt8(ascii: ",") else { return false }
            }
        }

        mutating func array(_ path: [String]) -> Bool {
            out.append(bytes[i]); i += 1
            skipSpace()
            if i < bytes.count, bytes[i] == UInt8(ascii: "]") { out.append(bytes[i]); i += 1; return true }
            while true {
                guard value(path: path + ["[]"]) else { return false }
                skipSpace()
                guard i < bytes.count else { return false }
                out.append(bytes[i]); i += 1
                if bytes[i - 1] == UInt8(ascii: "]") { return true }
                guard bytes[i - 1] == UInt8(ascii: ",") else { return false }
            }
        }
    }
}
