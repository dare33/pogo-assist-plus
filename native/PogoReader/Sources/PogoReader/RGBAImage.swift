import Foundation

/// A plain RGBA8 pixel buffer (R, G, B, A byte order, rows packed). The reader's routines work on
/// this so the extension, the Mac tool and the tests share them; no CoreGraphics in the hot paths.
public struct RGBAImage {
    public let width: Int
    public let height: Int
    public var bytes: [UInt8]

    public init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
        self.bytes = [UInt8](repeating: 0, count: self.width * self.height * 4)
    }

    public init(width: Int, height: Int, bytes: [UInt8]) {
        precondition(bytes.count == width * height * 4, "RGBAImage: byte count does not match size")
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    @inline(__always) public func index(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }

    @inline(__always) public func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let i = (y * width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2])
    }

    /// Luma of the pixel at (x, y).
    @inline(__always) public func luma(_ x: Int, _ y: Int) -> Double {
        let i = (y * width + x) * 4
        return 0.299 * Double(bytes[i]) + 0.587 * Double(bytes[i + 1]) + 0.114 * Double(bytes[i + 2])
    }

    /// Fill a rectangle with one colour (used by tests and the synthetic frame to draw screens).
    public mutating func fill(_ rect: Rect, _ colour: (UInt8, UInt8, UInt8)) {
        let x0 = max(0, jsRound(rect.x)), y0 = max(0, jsRound(rect.y))
        let x1 = min(width, jsRound(rect.x + rect.w)), y1 = min(height, jsRound(rect.y + rect.h))
        guard x0 < x1, y0 < y1 else { return }
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = (y * width + x) * 4
                bytes[i] = colour.0; bytes[i + 1] = colour.1; bytes[i + 2] = colour.2; bytes[i + 3] = 255
            }
        }
    }
}

/// JavaScript's Math.round (halves go up), so the ports crop exactly where the JS does.
@inline(__always) public func jsRound(_ v: Double) -> Int { Int((v + 0.5).rounded(.down)) }

/// A rectangle in pixels of a frame, fractional (regions derived from fractions of the frame).
public struct Rect: Equatable {
    public var x: Double, y: Double, w: Double, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
}

/// A whole-pixel rectangle (the content rectangle of a frame).
public struct PixelRect: Equatable {
    public var x: Int, y: Int, w: Int, h: Int
    public init(x: Int, y: Int, w: Int, h: Int) { self.x = x; self.y = y; self.w = w; self.h = h }
}
