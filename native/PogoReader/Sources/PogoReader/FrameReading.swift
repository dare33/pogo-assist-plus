import Foundation

/// One frame as the reader saw it. The JSON is the JavaScript reading shape field for field
/// (src/extract/frame.js), so a Node script can hand Swift readings to the JS `finish()`:
/// `fills` are fractions 0..1 per bar; fields the JS leaves undefined until a name matches
/// (baseName, form, speciesIds, nameDistance, nameWeak, nameAttached, cpReads) are omitted here
/// too, and the ones the JS initialises to null are written as null.
public struct FrameReading: Codable, Equatable {
    public var frame: String?
    public var time: Double?
    public var cp: Int?
    public var cpText: String = ""
    public var cpReads: [Int]?
    public var name: String?
    public var baseName: String?
    public var form: String?
    public var speciesIds: [String]?
    public var nameText: String = ""
    public var nameConfidence: Double = 0
    public var nameDistance: Int?
    public var nameWeak: Bool?
    public var nameAttached: Bool?
    public var hp: HP?
    public var hpText: String = ""
    public var ivs: IVs?
    public var ivConfidence: Double = 0
    public var fills: [Double]?
    public var sharpness: Double = 0
    public var flags: [String] = []

    public init(frame: String? = nil, time: Double? = nil) { self.frame = frame; self.time = time }

    private enum Key: String, CodingKey {
        case frame, time, cp, cpText, cpReads, name, baseName, form, speciesIds, nameText, nameConfidence, nameDistance
        case nameWeak, nameAttached, hp, hpText, ivs, ivConfidence, fills, sharpness, flags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        frame = try c.decodeIfPresent(String.self, forKey: .frame)
        time = try c.decodeIfPresent(Double.self, forKey: .time)
        cp = try c.decodeIfPresent(Int.self, forKey: .cp)
        cpText = try c.decodeIfPresent(String.self, forKey: .cpText) ?? ""
        cpReads = try c.decodeIfPresent([Int].self, forKey: .cpReads)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        baseName = try c.decodeIfPresent(String.self, forKey: .baseName)
        form = try c.decodeIfPresent(String.self, forKey: .form)
        speciesIds = try c.decodeIfPresent([String].self, forKey: .speciesIds)
        nameText = try c.decodeIfPresent(String.self, forKey: .nameText) ?? ""
        nameConfidence = try c.decodeIfPresent(Double.self, forKey: .nameConfidence) ?? 0
        nameDistance = try c.decodeIfPresent(Int.self, forKey: .nameDistance)
        nameWeak = try c.decodeIfPresent(Bool.self, forKey: .nameWeak)
        nameAttached = try c.decodeIfPresent(Bool.self, forKey: .nameAttached)
        hp = try c.decodeIfPresent(HP.self, forKey: .hp)
        hpText = try c.decodeIfPresent(String.self, forKey: .hpText) ?? ""
        ivs = try c.decodeIfPresent(IVs.self, forKey: .ivs)
        ivConfidence = try c.decodeIfPresent(Double.self, forKey: .ivConfidence) ?? 0
        fills = try c.decodeIfPresent([Double].self, forKey: .fills)
        sharpness = try c.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0
        flags = try c.decodeIfPresent([String].self, forKey: .flags) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(frame, forKey: .frame)
        try c.encode(time, forKey: .time)
        try c.encode(cp, forKey: .cp)
        try c.encode(cpText, forKey: .cpText)
        try c.encodeIfPresent(cpReads, forKey: .cpReads)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(baseName, forKey: .baseName)
        try c.encodeIfPresent(form, forKey: .form)
        try c.encodeIfPresent(speciesIds, forKey: .speciesIds)
        try c.encode(nameText, forKey: .nameText)
        try c.encode(nameConfidence, forKey: .nameConfidence)
        try c.encodeIfPresent(nameDistance, forKey: .nameDistance)
        try c.encodeIfPresent(nameWeak, forKey: .nameWeak)
        try c.encodeIfPresent(nameAttached, forKey: .nameAttached)
        try c.encode(hp, forKey: .hp)
        try c.encode(hpText, forKey: .hpText)
        try c.encode(ivs, forKey: .ivs)
        try c.encode(ivConfidence, forKey: .ivConfidence)
        try c.encode(fills, forKey: .fills)
        try c.encode(sharpness, forKey: .sharpness)
        try c.encode(flags, forKey: .flags)
    }
}
