import Foundation
import PogoReader

/// The app's own box export (and a Poke Genie storage CSV, which has the same columns) read back into box entries: species by dex number and form, CP, HP, IVs,
/// level and dust. For tests and the DEBUG seeding of a big box (`-uitest-seed-box`); a scan never goes through here.
public enum BoxCSVReader {
    public static func entries(csv text: String, gm: GameMaster, seen: Date = Date(timeIntervalSince1970: 1_790_000_000)) -> [BoxEntry] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard !lines.isEmpty else { return [] }
        let head = lines.removeFirst().split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        func col(_ n: String) -> Int? { head.firstIndex(of: n) }
        guard let cDex = col("Pokemon Number"), let cForm = col("Form"), let cCP = col("CP"), let cHP = col("HP"), let cA = col("Atk IV"), let cD = col("Def IV"), let cS = col("Sta IV") else { return [] }
        let cLo = col("Level Min"), cHi = col("Level Max"), cDust = col("Dust")
        let bySpecies = Dictionary(grouping: gm.byId.values, by: { $0.dex })
        var out = [BoxEntry]()
        for (i, l) in lines.enumerated() {
            let f = l.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard f.count > cS, let dex = Int(f[cDex]) else { continue }
            let form = f[cForm]
            guard let sp = bySpecies[dex]?.sorted(by: { $0.id < $1.id }).first(where: { s in let nf = GameMaster.nameAndForm(s.name).form; return nf == form || (form.isEmpty && (nf.isEmpty || nf == "Normal")) }) else { continue }
            let nf = GameMaster.nameAndForm(sp.name)
            let iv: IVs? = Int(f[cA]).flatMap { a in Int(f[cD]).flatMap { d in Int(f[cS]).map { IVs(atk: a, def: d, hp: $0) } } }
            let r = ScanRow(index: i + 1, name: nf.name, display: nf.name, form: nf.form, speciesId: sp.id, dex: sp.dex, cp: Int(f[cCP]) ?? 0, hp: Int(f[cHP]), ivs: iv, ivsRead: iv, ivsGuess: nil,
                            level: cLo.flatMap { Double(f[$0]) }, levelMax: cHi.flatMap { Double(f[$0]) }, dust: cDust.flatMap { Int(f[$0]) }.flatMap { $0 > 0 ? $0 : nil },
                            solveStatus: "exact", flags: [], frames: [])
            out.append(BoxEntry(id: "b\(i)", row: r, firstSeen: seen, lastSeen: seen))
        }
        return out
    }
}
