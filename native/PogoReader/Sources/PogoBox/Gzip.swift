import Compression
import Foundation

/// gzip (RFC 1952) over Apple's Compression framework: no third-party code. Compression's `.zlib` is raw DEFLATE, so the header and the
/// CRC-32 and length trailer are written here.
public enum Gzip {
    public enum Failure: Error, LocalizedError, Equatable {
        case notGzip, corrupt(String)
        public var errorDescription: String? { "The data is not valid gzip." }
    }

    public static func compress(_ data: Data) throws -> Data {
        let deflated = try (data as NSData).compressed(using: .zlib) as Data
        var out = Data([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xff])   // no flags, no time stamp, unknown OS
        out.append(deflated)
        out.append(contentsOf: le32(crc32(data)))
        out.append(contentsOf: le32(UInt32(truncatingIfNeeded: data.count)))
        return out
    }

    public static func decompress(_ data: Data) throws -> Data {
        let b = [UInt8](data)
        guard b.count >= 18, b[0] == 0x1f, b[1] == 0x8b, b[2] == 0x08, b[3] == 0 else { throw Failure.notGzip }
        let body = Data(b[10..<(b.count - 8)])
        let out: Data
        do { out = try (body as NSData).decompressed(using: .zlib) as Data } catch { throw Failure.corrupt("\(error)") }
        let crc = UInt32(b[b.count - 8]) | UInt32(b[b.count - 7]) << 8 | UInt32(b[b.count - 6]) << 16 | UInt32(b[b.count - 5]) << 24
        let size = UInt32(b[b.count - 4]) | UInt32(b[b.count - 3]) << 8 | UInt32(b[b.count - 2]) << 16 | UInt32(b[b.count - 1]) << 24
        guard crc == crc32(out), size == UInt32(truncatingIfNeeded: out.count) else { throw Failure.corrupt("checksum or length does not match") }
        return out
    }

    private static func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)] }

    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for byte in data { c = table[Int((c ^ UInt32(byte)) & 0xff)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }
}
