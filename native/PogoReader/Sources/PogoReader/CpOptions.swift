import Foundation

public struct CpOptionsResult: Equatable {
    public var options: [Int]
    public var supported: [Int]
    /// For each supported CP, the partial read that is its tail.
    public var tailOf: [Int: Int]
}

/// Port of `cpOptions` (pipeline.js). The CPs a Pokémon could have, from what a model in front of
/// the CP text cannot hide: its HP and its settled bars. Each level whose HP matches gives one CP.
/// `reads` are the partial CP reads (the model usually covers the leading digits, so a read is the
/// tail of the real number). Returns every CP that fits, those a partial read is the tail of, and
/// for each of those the read that supports it. `hp` is the max HP.
public func cpOptions(_ species: [Species], hp: Int?, ivs: IVs?, ivConfidence: Double = 1, reads: [Int] = []) -> CpOptionsResult {
    guard let hp = hp, let ivs = ivs, ivConfidence >= SETTLED else { return CpOptionsResult(options: [], supported: [], tailOf: [:]) }
    var options = Set<Int>()
    for sp in species {
        for level in levels where hpAt(sp.baseStats, ivs, level) == hp { options.insert(cpAt(sp.baseStats, ivs, level)) }
    }
    let tails = reads.filter { $0 >= 10 }.map(String.init)
    let all = options.sorted()
    var tailOf = [Int: Int]()
    var supported = [Int]()
    for cp in all {
        let s = String(cp)
        if let t = tails.first(where: { $0.count < s.count && s.hasSuffix($0) }) { tailOf[cp] = Int(t)!; supported.append(cp) }
    }
    return CpOptionsResult(options: all, supported: supported, tailOf: tailOf)
}

/// Whether a read CP can be reconciled with the HP and bars: some level of one of the species
/// gives that CP and HP with IVs within one unit of the bars (the JS solver's tier 0 or 1). With no
/// bars read nothing can be checked, so this returns nil (no evidence either way).
public func cpFits(_ species: [Species], cp: Int, hp: Int?, ivs: IVs?) -> Bool? {
    guard let ivs = ivs else { return nil }
    for sp in species {
        for da in -1...1 { for dd in -1...1 { for dh in -1...1 {
            let c = IVs(atk: ivs.atk + da, def: ivs.def + dd, hp: ivs.hp + dh)
            if c.atk < 0 || c.atk > 15 || c.def < 0 || c.def > 15 || c.hp < 0 || c.hp > 15 { continue }
            for level in levels {
                let v = cpAt(sp.baseStats, c, level)
                if v > cp { break }
                if v != cp { continue }
                if let hp = hp, hpAt(sp.baseStats, c, level) != hp { continue }
                return true
            }
        } } }
    }
    return false
}
