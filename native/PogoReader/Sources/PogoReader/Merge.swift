import Foundation

// Port of the small pure parts of src/extract/merge.js.

/// Two CP reads that could be the same number: equal, one digit different, or one digit dropped.
public func cpSimilar(_ a: Int, _ b: Int) -> Bool {
    let x = Array(String(a)), y = Array(String(b))
    if x == y { return true }
    if x.count == y.count && x.count >= 3 {
        var d = 0
        for i in 0..<x.count where x[i] != y[i] { d += 1 }
        return d <= 1
    }
    let (s, l) = x.count < y.count ? (x, y) : (y, x)
    if l.count - s.count != 1 || s.count < 2 { return false }
    for i in 0..<l.count {
        var cut = l
        cut.remove(at: i)
        if cut == s { return true }
    }
    return false
}

/// Bars settle to whole units; a read far from whole units is mid-animation and says nothing.
public let SETTLED = 0.7

/// Two bar reads agree when either is unsettled, or both are settled and equal.
public func ivsCompatible(_ a: IVs?, _ b: IVs?, _ ca: Double = 1, _ cb: Double = 1) -> Bool {
    guard let a = a, let b = b, ca >= SETTLED, cb >= SETTLED else { return true }
    return a == b
}
