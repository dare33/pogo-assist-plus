import Foundation

// Port of src/cpm.js: CP multipliers by level (1 to 51 in half steps) and the CP / HP formulas.
// Values are the public game constants.

public struct BaseStats: Equatable, Hashable {
    public var atk: Int, def: Int, hp: Int
    public init(atk: Int, def: Int, hp: Int) { self.atk = atk; self.def = def; self.hp = hp }
}

private let cpmTable: [Double] = [
    0.094, 0.1351374318, 0.16639787, 0.192650919, 0.21573247, 0.2365726613,
    0.25572005, 0.2735303812, 0.29024988, 0.3060573775, 0.3210876, 0.3354450362,
    0.34921268, 0.3624577511, 0.3752356, 0.387592416, 0.39956728, 0.4111935514,
    0.4225, 0.4329264091, 0.44310755, 0.4530599591, 0.4627984, 0.472336093,
    0.48168495, 0.4908558003, 0.49985844, 0.508701765, 0.51739395, 0.5259425113,
    0.5343543, 0.5426357375, 0.5507927, 0.5588305862, 0.5667545, 0.5745691333,
    0.5822789, 0.5898879072, 0.5974, 0.6048236651, 0.6121573, 0.6194041216,
    0.6265671, 0.6336491432, 0.64065295, 0.6475809666, 0.65443563, 0.6612192524,
    0.667934, 0.6745818959, 0.6811649, 0.6876849038, 0.69414365, 0.70054287,
    0.7068842, 0.7131691091, 0.7193991, 0.7255756136, 0.7317, 0.7347410093,
    0.7377695, 0.7407855938, 0.74378943, 0.7467812109, 0.74976104, 0.7527290867,
    0.7556855, 0.7586303683, 0.76156384, 0.7644860647, 0.76739717, 0.7702972656,
    0.7731865, 0.7760649616, 0.77893275, 0.7817900548, 0.784637, 0.7874736075,
    0.7903, 0.792803968, 0.79530001, 0.797800015, 0.8003, 0.802799995,
    0.8053, 0.8078, 0.81029999, 0.812799985, 0.81529999, 0.81779999,
    0.82029999, 0.82279999, 0.82529999, 0.82779999, 0.83029999, 0.83279999,
    0.83529999, 0.83779999, 0.84029999, 0.84279999, 0.84529999,
]

/// Levels 1, 1.5, ... 51.
public let levels: [Double] = (0..<cpmTable.count).map { 1 + Double($0) / 2 }

public func cpm(_ level: Double) -> Double {
    let i = Int(((level - 1) * 2).rounded())
    precondition(i >= 0 && i < cpmTable.count && abs(Double(i) / 2 + 1 - level) < 1e-9, "no CP multiplier for level \(level)")
    return cpmTable[i]
}

/// CP for base stats, IVs and a level.
public func cpAt(_ base: BaseStats, _ ivs: IVs, _ level: Double) -> Int {
    let m = cpm(level)
    let v = (Double(base.atk + ivs.atk) * (Double(base.def + ivs.def)).squareRoot() * (Double(base.hp + ivs.hp)).squareRoot() * m * m) / 10
    return max(10, Int(v.rounded(.down)))
}

/// HP (stamina) for base stats, IVs and a level.
public func hpAt(_ base: BaseStats, _ ivs: IVs, _ level: Double) -> Int {
    max(10, Int((Double(base.hp + ivs.hp) * cpm(level)).rounded(.down)))
}
