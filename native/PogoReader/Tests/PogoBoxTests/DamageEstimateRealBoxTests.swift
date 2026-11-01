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
        print("P1-TIMING first cold scale \(String(format: "%.0f", coldMs)) ms; slowest picker (scale + all rows) \(String(format: "%.0f", worst)) ms; \(rows) rows in total")
        XCTAssertLessThan(worst, 500)
    }
}
