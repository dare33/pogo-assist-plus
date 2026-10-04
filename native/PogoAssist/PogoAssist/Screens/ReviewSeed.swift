#if DEBUG
import Foundation
import PogoBox
import PogoReader

/// A review for screenshots and UI tests, in DEBUG builds only: launch with `-uitest-seed-review <variant>` (`full`, `clean` or `partial`).
/// The merge is the real one: the fixture is a small saved box and a list of scanned rows, and `BoxMerge.plan` decides what to ask, which is how the
/// engine's own tests build their cases. Only the scan's `Outcome` is borrowed from the bundled sample scan (it cannot be built outside the engine),
/// with its rows, unmatched cards and duration replaced by the fixture's.
extension AppModel {
    func seedReview(variant: String) {
        if accounts.isEmpty { createAccount("Greg main") }
        guard let name = account, let url = Bundle.main.url(forResource: "sample-scan.replay", withExtension: "jsonl"), let gm = try? GameMaster.bundled() else { return }
        flow = .processing("Reading the scan")
        Task {
            do {
                var outcome = try await worker.run { engine in try ScanPipeline.process(replay: url, engine: engine) }
                let f = ReviewFixture(gm, variant: variant)
                outcome.scan = ScanResult(rows: f.rows, review: [], unmatched: f.unmatched)
                outcome.readings = 1686; outcome.duration = 2040; outcome.notices = []
                let kind: BoxStore.Kind = variant == "partial" ? .partial : .full
                let plan = BoxMerge.plan(scanned: f.rows, unmatched: f.unmatched, into: f.saved, kind: kind, scanDate: Date(), gameMaster: gm)
                var review = Review(account: name, kind: kind, outcome: outcome, plan: plan, base: f.saved, storageCount: nil, signature: "seed", mergeSeconds: 0.1, paging: nil, boxSeq: nil)
                print("seed unsure:", plan.unsure.map { "\($0.scanned):\($0.kind.rawValue):\($0.candidates.count)" }, "new", plan.new.count, "same", plan.same.count, "updated", plan.updated.count)
                review.endedAtListEnd = variant != "partial"
                flow = .review(review)
            } catch { flow = .failed(message: "\(error)", signature: "seed") }
        }
    }
}

/// The scanned rows and the saved box of the fixture.
struct ReviewFixture {
    let gm: GameMaster
    var rows = [ScanRow]()
    var saved = [BoxEntry]()
    var unmatched = [Unmatched]()
    private let day = Date(timeIntervalSince1970: 1_790_000_000)

    private func row(_ id: String, cp: Int, hp: Int? = 100, ivs: IVs? = IVs(atk: 13, def: 12, hp: 15), flags: [String] = [], status: String = "exact") -> ScanRow {
        let nf = GameMaster.nameAndForm(gm.byId[id]?.name ?? id)
        return ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: id, dex: gm.byId[id]?.dex, cp: cp, hp: hp, ivs: ivs, ivsRead: ivs, ivsGuess: nil,
                       level: ivs == nil ? nil : 20, levelMax: ivs == nil ? nil : 20, dust: 1000, solveStatus: ivs == nil ? "unknown-ivs" : status, flags: flags, frames: [])
    }
    private mutating func own(_ id: String, _ cp: Int, _ hp: Int?, _ ivs: IVs?, _ key: String, scanned: Bool = false) {
        let r = row(id, cp: cp, hp: hp, ivs: ivs)
        saved.append(BoxEntry(id: key, row: r, firstSeen: day, lastSeen: day))
        if scanned { rows.append(r) }
    }
    private func iv(_ a: Int, _ d: Int, _ h: Int) -> IVs { IVs(atk: a, def: d, hp: h) }

    init(_ gm: GameMaster, variant: String) {
        self.gm = gm
        // Pokémon the scan read and the box already has: "Same".
        let plain: [(String, Int, Int, IVs)] = [("pidgey", 312, 48, iv(12, 9, 14)), ("eevee", 590, 71, iv(15, 15, 10)), ("rhyhorn", 701, 98, iv(3, 7, 12)), ("hatenna", 288, 52, iv(8, 15, 11)), ("fidough", 344, 66, iv(5, 5, 9)), ("nacli", 512, 80, iv(10, 11, 12))]
        for (i, p) in plain.enumerated() { own(p.0, p.1, p.2, p.3, "same\(i)", scanned: true) }
        // Not in the box: "New".
        rows.append(row("meltan", cp: 421, hp: 70, ivs: iv(3, 7, 12)))
        rows.append(row("combee", cp: 120, hp: 40, ivs: iv(9, 9, 9)))
        if variant != "clean" {
            // Three part reads of a saved Pokémon's CP: one bulk-able group.
            let bad = iv(1, 1, 1)
            own("staraptor", 1951, 140, iv(13, 12, 15), "s1"); rows.append(row("staraptor", cp: 951, hp: 140, ivs: bad, flags: ["no-level-fits"]))
            own("moltres", 1901, 129, iv(13, 12, 15), "s2"); rows.append(row("moltres", cp: 901, hp: 129, ivs: bad, flags: ["no-level-fits"]))
            own("charizard", 1607, 118, iv(13, 12, 15), "s3"); rows.append(row("charizard", cp: 607, hp: 118, ivs: bad, flags: ["no-level-fits"]))
            // Evolved, powered up, other IVs at the same CP and HP.
            own("sobble", 609, 90, iv(13, 13, 14), "evo"); rows.append(row("drizzile", cp: 1060, hp: 105, ivs: iv(13, 13, 14)))
            own("machamp", 1100, 130, iv(13, 11, 12), "pow"); rows.append(row("machamp", cp: 1250, hp: 140, ivs: iv(13, 11, 12)))
            own("tympole", 623, 108, iv(6, 11, 14), "tym"); rows.append(row("tympole", cp: 623, hp: 108, ivs: iv(5, 10, 13)))
            // Two identical rows, one saved.
            own("kakuna", 102, 61, iv(1, 3, 4), "kak"); for _ in 0..<2 { rows.append(row("kakuna", cp: 102, hp: 61, ivs: iv(1, 3, 4))) }
            // A part read with five saved candidates of the same species and HP: ranked, with "Show all".
            for (i, cp) in [1951, 1851, 1751, 1651, 1551].enumerated() { own("garchomp", cp, 160, iv(2 + i, 4 + i, 6 + i), "g\(i)") }
            rows.append(row("garchomp", cp: 951, hp: 160, ivs: bad, flags: ["no-level-fits"]))
            // Unread IVs: several saved Pokémon could be it.
            for i in 0..<4 { own("wooloo", 359, 55, iv(4 + i, 5 + i, 6 + i), "w\(i)") }
            rows.append(row("wooloo", cp: 359, hp: 55, ivs: nil))
            // A Mega pair.
            own("blaziken", 2819, 167, iv(15, 15, 14), "mb"); own("blaziken_mega", 3970, 167, iv(15, 15, 14), "mm"); rows.append(row("blaziken_mega", cp: 3970, hp: 167, ivs: iv(15, 15, 14)))
            // A saved entry read badly before, and an entry first saved as Mega.
            var badRead = row("heatmor", cp: 64, hp: 92, ivs: nil, flags: ["no-level-fits"]); badRead.solveStatus = "none"; badRead.ivsRead = nil
            saved.append(BoxEntry(id: "hm", row: badRead, firstSeen: day, lastSeen: day)); rows.append(row("heatmor", cp: 764, hp: 92, ivs: iv(7, 14, 2)))
            own("garchomp_mega", 4200, 190, iv(14, 13, 15), "gm"); rows.append(row("garchomp", cp: 3000, hp: 190, ivs: iv(14, 13, 15)))
        }
        // To check: each reason.
        rows.append(row("zapdos", cp: 1977, hp: 129, ivs: iv(15, 12, 10), flags: ["cp-computed"], status: "corrected"))
        rows.append(row("weezing", cp: 883, hp: 85, ivs: iv(2, 15, 3), flags: ["cp-computed"], status: "corrected"))
        rows.append(row("rayquaza", cp: 4262, hp: 190, ivs: nil, flags: ["ambiguous-ivs"], status: "ambiguous"))
        rows.append(row("tympole", cp: 381, hp: 83, ivs: iv(6, 10, 11), flags: ["split-by-bars"])); rows.append(row("tympole", cp: 381, hp: 83, ivs: iv(11, 10, 14), flags: ["split-by-bars"]))
        rows.append(row("zubat", cp: 477, hp: 78, ivs: iv(8, 10, 15), flags: ["same-as-previous"]))
        rows.append(row("meowth", cp: 65, hp: 29, ivs: iv(0, 0, 0), flags: ["no-level-fits"]))
        rows.append(row("farfetchd", cp: 153, hp: 37, ivs: iv(0, 0, 0), flags: ["no-level-fits", "hp-unread"]))
        rows.append(row("nidoranf", cp: 200, hp: 44, ivs: iv(5, 6, 7), flags: ["form-ambiguous"], status: "exact"))
        rows.append(row("pikachu", cp: 377, hp: 50, ivs: iv(6, 6, 6), flags: ["level-ambiguous"], status: "exact"))
        // Saved Pokémon the scan did not see ("Not seen").
        let gone: [(String, Int, IVs)] = [("charmander", 455, iv(8, 15, 11)), ("tinkatink", 403, iv(2, 9, 13)), ("wattrel", 96, iv(6, 0, 7)), ("pidgeot", 1210, iv(14, 11, 9)), ("bulbasaur", 288, iv(11, 12, 10)), ("squirtle", 344, iv(9, 9, 15)),
                                         ("snorlax", 2410, iv(15, 14, 13)), ("gengar", 1887, iv(10, 10, 12)), ("lapras", 1590, iv(7, 15, 8)), ("onix", 410, iv(12, 3, 5)), ("magikarp", 55, iv(3, 3, 3)), ("ditto", 280, iv(1, 14, 10))]
        for (i, g) in gone.enumerated() { own(g.0, g.1, 60 + i, g.2, "gone\(i)") }
        // Cards on screen the scan could not read.
        unmatched = (try? JSONDecoder().decode(Unmatched.self, from: Data(#"{"frame":"f1","cp":1966,"nameText":"Mag","frames":3,"reason":"name-not-read"}"#.utf8))).map { [$0] } ?? []
        for i in rows.indices { rows[i].index = i + 1 }
    }
}
#endif
