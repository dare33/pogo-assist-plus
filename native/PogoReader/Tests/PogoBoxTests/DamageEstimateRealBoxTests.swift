import XCTest
@testable import PogoBox
import PogoReader

/// P1 on Greg's own box of 22 Oct 2026 through the real engine: the picker's figures for Giratina (Origin) and Palkia, and how long a picker takes to open.
final class DamageEstimateRealBoxTests: XCTestCase {
    private static var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    private static let realBox: (entries: [BoxEntry], advice: BoxAdvice) = {
        let text = try! String(contentsOf: root.appendingPathComponent("fixtures/greg-2026-10-22.box.csv"), encoding: .utf8)
        let box = BoxCSVReader.entries(csv: text, gm: P23.gm)
        let rows = box.enumerated().map { i, e in var r = e.row; r.index = i + 1; return r }
        return (box, BoxAdvice.make(from: try! sharedEngine.advise(rows: rows, scanDate: Date(timeIntervalSince1970: 1_790_000_000)), entries: box))
    }()

    func testRaidPickerFiguresOnGregsRealBox() throws {
        let box = Self.realBox
        let table = try TierTable.bundled(), pve = try PveMoves.bundled()
        for species in ["giratina_origin", "palkia"] {
            let row = try XCTUnwrap(P23.hub.rotation.first { $0.kind == .fiveStar && $0.bosses.contains { $0.speciesId == species } })
            let ctx = HubContext(advice: box.advice, entries: box.entries, gm: P23.gm, hub: P23.hub, table: table, today: row.from)
            let start = Date()
            let scale = StrengthScale.shared(mode: .raids, bosses: row.bosses, ctx: ctx, pve: pve)
            let cands = HubSquads.raidCandidates(row: row, mode: .available, ctx: ctx)
            var lines = [String](), n = 0
            for c in cands {
                let copy = ctx.entry(c.entryId)
                let plain = scale.strength(.init(copy: copy, build: c.build, built: c.built))
                var mega: Strength?
                if let m = c.mega { mega = scale.strength(.init(copy: copy, build: m.build, built: m.built, megaSlot: true)) }
                for s in [plain, mega].compactMap({ $0 }) {
                    n += 1
                    XCTAssertTrue((0...1).contains(s.barEnd))
                    if let a = s.after, let now = s.now { XCTAssertGreaterThanOrEqual(a, now) }
                }
                if lines.count < 12 {
                    func p(_ s: Strength?) -> String { s.map { "now \($0.now.map { String(Int(($0 * 100).rounded())) } ?? "-") after \($0.after.map { String(Int(($0 * 100).rounded())) } ?? "-")" } ?? "-" }
                    lines.append("\(copy?.row.title ?? c.entryId) (\(c.build.targetName), \(c.role.rawValue), tier \(c.tier.isEmpty ? "-" : c.tier)\(c.built ? ", full" : "")): \(p(plain))" + (mega.map { "  | Mega slot: \(p($0))" } ?? ""))
                }
            }
            let ms = Date().timeIntervalSince(start) * 1000
            print("P1-REAL-BOX \(species): best in game DPS \(String(format: "%.2f", scale.bestInGame)), \(cands.count) candidates, \(n) figures, scale + all rows in \(String(format: "%.0f", ms)) ms\n" + lines.joined(separator: "\n"))
        }
    }

    /// Ruling 2 on the real box against Palkia: Rayquaza in the Mega slot gains from Mega Rayquaza's stats and Dragon moves, so after is above now without help from the
    /// "never worse" clamp (the unclamped value is checked directly); Charizard in the Mega slot is judged on Mega X's Dragon line, the better form against a Dragon/Water boss.
    func testMegaSlotRowsFollowTheBossOnTheRealBox() throws {
        let box = Self.realBox
        let table = try TierTable.bundled(), pve = try PveMoves.bundled()
        let row = try XCTUnwrap(P23.hub.rotation.first { $0.kind == .fiveStar && $0.bosses.contains { $0.speciesId == "palkia" } })
        let ctx = HubContext(advice: box.advice, entries: box.entries, gm: P23.gm, hub: P23.hub, table: table, today: row.from)
        let scale = StrengthScale.shared(mode: .raids, bosses: row.bosses, ctx: ctx, pve: pve)
        let cands = HubSquads.raidCandidates(row: row, mode: .available, ctx: ctx)
        func megaRow(_ species: String) throws -> (BoxEntry, HubSquads.MegaView) {
            let c = try XCTUnwrap(cands.first { ctx.entry($0.entryId)?.row.speciesId == species && $0.mega != nil }, "\(species) is a Mega candidate")
            return (try XCTUnwrap(ctx.entry(c.entryId)), try XCTUnwrap(c.mega))
        }
        // Rayquaza.
        let (ray, rayMega) = try megaRow("rayquaza")
        let r = scale.strength(.init(copy: ray, build: rayMega.build, built: false, megaSlot: true))
        let rNow = try XCTUnwrap(r.now), rAfter = try XCTUnwrap(r.after)
        XCTAssertGreaterThan(rAfter, rNow)
        let form = P23.gm.byId["rayquaza_mega"]!
        let unclamped = scale.bestOver(try XCTUnwrap(scale.attacker("rayquaza_mega", shadow: false, level: rayMega.build.targetLevel ?? ray.row.level, ivs: ray.row.ivs)),
                                       lines: scale.lines(scale.entries(of: "rayquaza", mega: true, shadow: false).filter { $0.speciesId == "rayquaza_mega" }))?.value
        XCTAssertEqual(rAfter, try XCTUnwrap(unclamped) / scale.bestInGame, accuracy: 1e-9, "the figure is Mega Rayquaza's own, not the clamp (\(form.name))")
        // Charizard.
        let (zard, zardMega) = try megaRow("charizard")
        let c = scale.strength(.init(copy: zard, build: zardMega.build, built: false, megaSlot: true))
        func v(_ id: String) -> Double? {
            scale.attacker(id, shadow: false, level: zardMega.build.targetLevel ?? zard.row.level, ivs: zard.row.ivs).flatMap { scale.bestOver($0, lines: scale.lines(scale.entries(of: "charizard", mega: true, shadow: false).filter { $0.speciesId == id }))?.value }
        }
        let x = try XCTUnwrap(v("charizard_mega_x")), y = try XCTUnwrap(v("charizard_mega_y"))
        XCTAssertGreaterThan(x, y, "against a Dragon/Water boss Mega X (Dragon) beats Mega Y (Fire)")
        XCTAssertEqual(try XCTUnwrap(c.after), x / scale.bestInGame, accuracy: 1e-9)
        let xs = try XCTUnwrap(P23.gm.byId["charizard_mega_x"])
        let found = try XCTUnwrap(scale.bestOver(try XCTUnwrap(scale.attacker("charizard_mega_x", shadow: false, level: zardMega.build.targetLevel ?? zard.row.level, ivs: zard.row.ivs)), lines: []))
        XCTAssertTrue(xs.types.contains("dragon"))
        XCTAssertTrue([found.fast, found.charged].compactMap { $0 }.contains { P23.gm.moves[$0]?.type == "dragon" }, "judged on a Dragon-type line: \(found)")
    }

    /// Ruling 1 on the real box: a Mega form is judged on the best of its Mega lines, the plain lines and the copy's own moves. Against Palkia, Metagross in the Mega slot is
    /// worth at least what it is in a plain slot; against Giratina (Origin), Lucario in the Mega slot shows a gain; a Mega Garchomp the box lacks, against Palkia, is
    /// judged on its Dragon line.
    func testMegaFormsAreJudgedOnTheirBestLine() throws {
        let box = Self.realBox
        let table = try TierTable.bundled(), pve = try PveMoves.bundled()
        func setup(_ boss: String) throws -> (HubContext, StrengthScale, [HubSquads.RaidCandidate]) {
            let row = try XCTUnwrap(P23.hub.rotation.first { $0.kind == .fiveStar && $0.bosses.contains { $0.speciesId == boss } })
            let ctx = HubContext(advice: box.advice, entries: box.entries, gm: P23.gm, hub: P23.hub, table: table, today: row.from)
            return (ctx, StrengthScale.shared(mode: .raids, bosses: row.bosses, ctx: ctx, pve: pve), HubSquads.raidCandidates(row: row, mode: .available, ctx: ctx))
        }
        // Metagross against Palkia.
        var (ctx, scale, cands) = try setup("palkia")
        let metagross = try XCTUnwrap(cands.first { ctx.entry($0.entryId)?.row.speciesId == "beldum" && $0.mega != nil })
        let copy = try XCTUnwrap(ctx.entry(metagross.entryId))
        let inMegaSlot = scale.strength(.init(copy: copy, build: try XCTUnwrap(metagross.mega).build, built: false, megaSlot: true))
        let inPlainSlot = scale.strength(.init(copy: copy, build: metagross.build, built: false, megaSlot: false))
        let megaAfter = try XCTUnwrap(inMegaSlot.after ?? inMegaSlot.now), plainAfter = try XCTUnwrap(inPlainSlot.after ?? inPlainSlot.now)
        print("P1-MEGA builds: mega \(String(describing: metagross.mega?.build.targetLevel)) \(String(describing: metagross.mega?.build.climbLevel)) plain \(String(describing: metagross.build.targetLevel)) level now \(String(describing: copy.row.level)) steps \(String(describing: metagross.mega?.build.steps?.map(\.kind))) vs \(String(describing: metagross.build.steps?.map(\.kind)))")
        print("P1-MEGA metagross vs palkia: Mega slot \(megaAfter), plain slot \(plainAfter)")
        XCTAssertGreaterThanOrEqual(megaAfter, plainAfter)
        // Lucario against Giratina (Origin).
        (ctx, scale, cands) = try setup("giratina_origin")
        let lucario = try XCTUnwrap(cands.first { ctx.entry($0.entryId)?.row.speciesId == "lucario" && $0.mega != nil })
        let lcopy = try XCTUnwrap(ctx.entry(lucario.entryId))
        let l = scale.strength(.init(copy: lcopy, build: try XCTUnwrap(lucario.mega).build, built: false, megaSlot: true))
        print("P1-MEGA lucario builds: mega \(String(describing: lucario.mega?.build.steps?.map(\.kind))) lvl \(String(describing: lucario.mega?.build.targetLevel)) now level \(String(describing: lcopy.row.level)) plain \(String(describing: lucario.build.steps?.map(\.kind))) built \(lucario.built)")
        print("P1-MEGA lucario vs giratina: now \(String(describing: l.now)) after \(String(describing: l.after))")
        XCTAssertNotNil(l.after, "Lucario in the Mega slot shows a gain")
        XCTAssertGreaterThan(try XCTUnwrap(l.after), try XCTUnwrap(l.now))
        // A Mega Garchomp the box lacks, against Palkia: every line of the species, so the Dragon line is there to be chosen.
        (ctx, scale, _) = try setup("palkia")
        let best = HubSquads.BestRow(key: "garchomp_mega", name: "Mega Garchomp", speciesId: "garchomp_mega", tier: "S", roles: [], types: ["dragon", "ground"], availability: "")
        let lines = HubSquads.tableMoves(of: best, area: "raids", ctx: ctx)
        XCTAssertGreaterThanOrEqual(lines.count, 2)
        let g = try XCTUnwrap(scale.attacker("garchomp_mega", shadow: false, level: 50, ivs: IVs(atk: 15, def: 15, hp: 15)))
        let found = try XCTUnwrap(scale.bestOver(g, lines: lines.flatMap(scale.picks(forText:))))
        XCTAssertTrue([found.fast, found.charged].compactMap { $0 }.contains { P23.gm.moves[$0]?.type == "dragon" }, "judged on a Dragon line: \(found)")
        let st = scale.strength(.init(copy: nil, build: nil, built: false, species: .init(speciesId: "garchomp_mega", shadow: false, moves: lines)))
        XCTAssertEqual(try XCTUnwrap(st.now), found.value / scale.bestInGame, accuracy: 1e-12)
        // Outside the raid Mega slot the same entry is the plain Pokémon (ruling 9): Garchomp's own base stats and table lines, a lower figure than as a Mega.
        let lackMega = HubSquads.lacking(of: best, area: "raids", megaSlot: true, ctx: ctx), lackPlain = HubSquads.lacking(of: best, area: "raids", megaSlot: false, ctx: ctx)
        XCTAssertEqual(lackMega.speciesId, "garchomp_mega")
        XCTAssertEqual(lackPlain.speciesId, "garchomp")
        let megaNow = try XCTUnwrap(scale.strength(.init(copy: nil, build: nil, built: false, species: lackMega)).now)
        let plainNow = try XCTUnwrap(scale.strength(.init(copy: nil, build: nil, built: false, species: lackPlain)).now)
        print("P1-MEGA lacking Mega Garchomp vs palkia: Mega slot \(megaNow), lackPlain \(plainNow)")
        XCTAssertLessThan(plainNow, megaNow)
        let plainBest = HubSquads.BestRow(key: "garchomp", name: "Garchomp", speciesId: "garchomp", tier: "S", roles: [], types: ["dragon", "ground"], availability: "")
        let plainJudged = scale.strength(.init(copy: nil, build: nil, built: false, species: .init(speciesId: "garchomp", shadow: false, moves: HubSquads.tableMoves(of: plainBest, area: "raids", ctx: ctx))))
        XCTAssertEqual(plainNow, try XCTUnwrap(plainJudged.now), accuracy: 1e-12, "judged exactly as the plain Garchomp row is")
        // In the Mega slot it is judged as an owned copy's Mega is: the best of its Mega line and the plain Pokémon's lines, and, since plain Garchomp has no raid line, its
        // species' best moves too. Its own Mega line (Outrage) alone gives less than its best moves (Breaking Swipe) against Palkia.
        XCTAssertTrue(lackMega.speciesBestToo)
        let megaLineOnly = try XCTUnwrap(scale.strength(.init(copy: nil, build: nil, built: false, species: .init(speciesId: "garchomp_mega", shadow: false, moves: HubSquads.tableMoves(of: best, area: "raids", ctx: ctx)))).now)
        let megaSpeciesBest = try XCTUnwrap(scale.strength(.init(copy: nil, build: nil, built: false, species: .init(speciesId: "garchomp_mega", shadow: false, moves: []))).now)
        print("P1-MEGA lacking Mega Garchomp in the Mega slot: Mega line only \(megaLineOnly), species best \(megaSpeciesBest), judged \(megaNow)")
        XCTAssertEqual(megaNow, max(megaLineOnly, megaSpeciesBest), accuracy: 1e-12)
        XCTAssertGreaterThan(megaNow, megaLineOnly, "the species' best moves beat the Mega line here, so the test sees the rule")
        // A Primal entry is a Mega-kind form too.
        let primal = HubSquads.BestRow(key: "kyogre_primal", name: "Primal Kyogre", speciesId: "kyogre_primal", tier: "S", roles: [], types: ["water"], availability: "")
        XCTAssertEqual(HubSquads.lacking(of: primal, area: "raids", megaSlot: false, ctx: ctx).speciesId, "kyogre")
        XCTAssertEqual(HubSquads.lacking(of: primal, area: "raids", megaSlot: true, ctx: ctx).speciesId, "kyogre_primal")
    }

    /// The move lines in the tables that name no move the game master knows, and which of them sit on the raid, Max and Rocket tables a picker reads.
    func testListUnparsedLinesOfThePickerTables() throws {
        let table = try TierTable.bundled()
        var picker = [String](), other = [String]()
        for e in table.entries {
            let r = DamageEstimate.parseLines(e.moves, gm: P23.gm)
            guard r.unparsed > 0 else { continue }
            let line = "\(e.area) | \(e.name) | \(e.moves ?? "")"
            if ["raids", "max", "rocket"].contains(e.area) { picker.append(line) } else { other.append(line) }
        }
        print("P1-UNPARSED total \(picker.count + other.count); on raid, Max and Rocket tables \(picker.count):\n" + picker.joined(separator: "\n") + "\nelsewhere (PvP leagues, Gym): \(other.count)")
    }

    /// A picker opens without a visible delay: a cold scale (the best in the game worked out) plus every row of the box, for every raid and Max boss on the schedule.
    func testPickerOpenTimeOnTheRealBox() throws {
        let box = Self.realBox
        let table = try TierTable.bundled(), pve = try PveMoves.bundled()
        var worst = 0.0, coldMs = 0.0, rows = 0
        DamageEstimate.clearCache()
        for r in P23.hub.rotation where !r.bosses.isEmpty && [.fiveStar, .mega, .shadow, .maxMonday, .maxEvent].contains(r.kind) {
            let ctx = HubContext(advice: box.advice, entries: box.entries, gm: P23.gm, hub: P23.hub, table: table, today: r.from)
            let isMax = [HubData.Kind.maxMonday, .maxEvent].contains(r.kind)
            let t0 = Date()
            let scale = StrengthScale(mode: isMax ? .max : .raids, bosses: r.bosses, ctx: ctx, pve: pve)  // a fresh one each time: a cold figure
            _ = scale.bestInGame
            let cold = Date().timeIntervalSince(t0) * 1000
            if coldMs == 0 { coldMs = cold }
            let builds = isMax ? HubSquads.maxCandidates(row: r, mode: .available, ctx: ctx).map(\.build) : HubSquads.raidCandidates(row: r, mode: .available, ctx: ctx).map(\.build)
            for b in builds { _ = scale.strength(.init(copy: ctx.entry(b.entryId), build: b, built: false)); rows += 1 }
            worst = max(worst, Date().timeIntervalSince(t0) * 1000)
        }
        // The Gym picker: the best Gym bulk is hashed once for the picker (cold), then every row of the box is scored.
        DamageEstimate.clearCache()
        let gymCtx = HubContext(advice: box.advice, entries: box.entries, gm: P23.gm, hub: P23.hub, table: table, today: P23.hub.rotation.first?.from ?? "2026-10-26")
        let g0 = Date()
        let bestBulk = DamageEstimate.bestGymBulk(gm: P23.gm)
        let gymRows = HubSquads.gymRows(mode: .available, ctx: gymCtx)
        for r in gymRows {
            let a = DamageEstimate.gymStrength(copy: gymCtx.entry(r.build.entryId), row: r, speciesId: nil, gm: P23.gm, bestBulk: bestBulk)
            XCTAssertEqual(a, DamageEstimate.gymStrength(copy: gymCtx.entry(r.build.entryId), row: r, speciesId: nil, gm: P23.gm), "passing the best bulk in changes no figure")
        }
        XCTAssertFalse(gymRows.isEmpty)
        // The same rows working the best bulk out per call (the hash per row a picker must not pay), timed as the yardstick on this machine.
        let u0 = Date()
        for r in gymRows { _ = DamageEstimate.gymStrength(copy: gymCtx.entry(r.build.entryId), row: r, speciesId: nil, gm: P23.gm) }
        let unpassedMs = Date().timeIntervalSince(u0) * 1000
        // Time only the passed-in path: a picker's rows.
        let g1 = Date()
        for r in gymRows { _ = DamageEstimate.gymStrength(copy: gymCtx.entry(r.build.entryId), row: r, speciesId: nil, gm: P23.gm, bestBulk: bestBulk) }
        let gymMs = Date().timeIntervalSince(g1) * 1000
        print("P1-TIMING Gym picker: best bulk + \(gymRows.count) rows; rows alone \(String(format: "%.0f", gymMs)) ms, per-row hashing \(String(format: "%.0f", unpassedMs)) ms (whole section \(String(format: "%.0f", Date().timeIntervalSince(g0) * 1000)) ms)")
        XCTAssertLessThan(gymMs, unpassedMs / 4, "no per-row hashing of the game master: the picker's rows cost a small part of hashing per row on this machine")
        print("P1-TIMING first cold scale \(String(format: "%.0f", coldMs)) ms; slowest picker (scale + all rows) \(String(format: "%.0f", worst)) ms; \(rows) rows in total")
        XCTAssertLessThan(worst, 500)
    }
}
