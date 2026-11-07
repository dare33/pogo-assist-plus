import XCTest
@testable import PogoBox
import PogoReader

/// Pass 2-6 (Greg, D65: "agree c2 for raids", "Agreed top 12"): Raids Best ranks every species by the damage estimate against the boss, top 12 per role, the table's tier shown where it
/// lists the Pokémon. On the real fixtures, as `DamageEstimateRealBoxTests` does.
final class HubSquadsBestDamageTests: XCTestCase {
    private static var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    private static let realBox: (entries: [BoxEntry], advice: BoxAdvice) = {
        let text = try! String(contentsOf: root.appendingPathComponent("fixtures/greg-2026-10-22.box.csv"), encoding: .utf8)
        let box = BoxCSVReader.entries(csv: text, gm: P23.gm)
        let rows = box.enumerated().map { i, e in var r = e.row; r.index = i + 1; return r }
        return (box, BoxAdvice.make(from: try! sharedEngine.advise(rows: rows, scanDate: Date(timeIntervalSince1970: 1_790_000_000)), entries: box))
    }()

    private func sableye() throws -> (HubData.RotationRow, HubContext) {
        let row = try XCTUnwrap(P23.hub.rotation.first { $0.kind == .mega && $0.bosses.contains { $0.speciesId == "sableye_mega" } })
        return (row, HubContext(advice: Self.realBox.advice, entries: Self.realBox.entries, gm: P23.gm, hub: P23.hub, table: try TierTable.bundled(), today: row.from))
    }

    private func damage(_ r: HubSquads.BestRow, row: HubData.RotationRow, ctx: HubContext) throws -> Double {
        let scale = StrengthScale.shared(mode: .raids, bosses: row.bosses, ctx: ctx, pve: try PveMoves.bundled())
        let lacking = HubSquads.lacking(of: r, area: "raids", megaSlot: r.roles == [PogoRules.RaidRole.mega.rawValue], ctx: ctx)
        return try XCTUnwrap(scale.strength(.init(copy: nil, build: nil, built: false, species: lacking)).now)
    }

    private func group(_ rows: [HubSquads.BestRow], _ role: PogoRules.RaidRole) -> [HubSquads.BestRow] { rows.filter { $0.roles == [role.rawValue] } }

    func testTwelveRowsPerRoleInRoleOrderAndDamageOrder() throws {
        let (row, ctx) = try sableye()
        XCTAssertEqual(HubRaidsModel.bring(row: row, hub: ctx.hub), ["fairy"], "Mega Sableye has the one weakness")
        let rows = HubSquads.bestRaidRows(row: row, ctx: ctx)
        for role in PogoRules.RaidRole.allCases { XCTAssertEqual(group(rows, role).count, 12, role.rawValue) }
        XCTAssertEqual(rows.count, 36)
        // Role order: Mega, Heavy hitter, Bulky hitter, each group contiguous.
        XCTAssertEqual(rows.map { $0.roles.first! }, Array(repeating: "Mega", count: 12) + Array(repeating: "Heavy hitter", count: 12) + Array(repeating: "Bulky hitter", count: 12))
        for role in PogoRules.RaidRole.allCases {
            let d = try group(rows, role).map { try damage($0, row: row, ctx: ctx) }
            XCTAssertEqual(d, d.sorted(by: >), "\(role.rawValue) is in damage order")
        }
        XCTAssertEqual(Set(rows.map(\.key)).count, rows.count, "no key twice")
        // The Mega group holds only Megas and Primals; the others none.
        XCTAssertTrue(group(rows, .mega).allSatisfy { $0.speciesId.contains("_mega") || $0.speciesId.contains("_primal") })
        XCTAssertTrue((group(rows, .heavy) + group(rows, .bulky)).allSatisfy { !$0.speciesId.contains("_mega") && !$0.speciesId.contains("_primal") })
        // Not just Fairy: the table would have listed only the Fairy counters; the damage estimate puts a neutral attacker in the Bulky list.
        let bulky = group(rows, .bulky)
        XCTAssertTrue(bulky.contains { !$0.types.contains("fairy") && !ctx.hub.beats($0.types, ["dark", "ghost"]) }, "a neutral, non-Fairy attacker is in the Bulky list: \(bulky.map(\.name))")
    }

    func testShadowRowsTierAndAvailabilityFollowTheTable() throws {
        let (row, ctx) = try sableye()
        let table = ctx.table
        // Judged over several bosses so a Shadow row is in at least one list.
        var shadows = [HubSquads.BestRow](), all = [(HubData.RotationRow, [HubSquads.BestRow])]()
        for r in [row] + P23.hub.rotation.filter({ $0.kind == .fiveStar }).prefix(3) {
            let c = HubContext(advice: ctx.advice, entries: ctx.entries, gm: ctx.gm, hub: ctx.hub, table: table, today: r.from)
            let rows = HubSquads.bestRaidRows(row: r, ctx: c)
            all.append((r, rows)); shadows += rows.filter { $0.key.hasSuffix("_shadow") }
        }
        XCTAssertFalse(shadows.isEmpty, "a Shadow row appears")
        for s in shadows {
            let plain = try XCTUnwrap(P23.gm.byId[s.key.replacingOccurrences(of: "_shadow", with: "")], s.key).name
            XCTAssertEqual(s.name, plain + " (Shadow)", "named as the box names a Shadow")
            XCTAssertEqual(s.roles, ["Heavy hitter"], "a Shadow is a Heavy hitter")
        }
        for (r, rows) in all {
            let bring = HubRaidsModel.bring(row: r, hub: ctx.hub)
            for x in rows {
                let listed = table.entries.filter { $0.area == "raids" && HubSquads.bestKey($0) == x.key }
                let expected = listed.filter { bring.contains($0.section.lowercased()) }.map(\.tier).min { PogoRules.tierRank($0) < PogoRules.tierRank($1) } ?? ""
                XCTAssertEqual(x.tier, expected, "\(x.name): the tier is the table's under a bring type, else none")
                // A Pokémon neither in the box, on the schedule nor in the table: Not available now, no reason given.
                if !x.inBox, listed.isEmpty, x.status.kind == .notAvailableNow {
                    XCTAssertEqual(x.status.text, x.rotationLine.map { "Not available now · " + $0 } ?? "Not available now", x.name)
                }
                if !x.inBox, listed.isEmpty, x.rotationLine == nil, x.status.kind != .canGetNow { XCTAssertEqual(x.status.text, "Not available now", x.name) }
                XCTAssertEqual(x.status.kind == .inBox, x.inBox, x.name)
            }
        }
    }

    /// Against a fire boss: a hand-made table and box on species the damage estimate puts in the lists, so the owners, tiers and availability are pinned row by row.
    func testOwnersTiersAndAvailabilityOfRowsTheTableDoesAndDoesNotList() throws {
        let fire = P23.row("2026-10-20", "2026-10-30", bosses: [P23.boss("charizard", types: ["fire"])])
        let table = P23.table([P23.tierEntry("raids", "Water", "S", "swampert_mega", mega: true, obtain: "Hard. Mega raids"),
                               P23.tierEntry("raids", "Rock", "S", "rhyperior", obtain: "Hard. Past raid"), P23.tierEntry("raids", "Ground", "S", "rhyperior"),
                               P23.tierEntry("raids", "Water", "A", "swampert"),
                               P23.tierEntry("raids", "Water", "B", "kyogre", obtain: "Easy. Wild"),
                               P23.tierEntry("raids", "Fire", "S", "groudon_shadow", shadow: true)])   // Fire is not a bring type for this boss: no tier
        let builds = [P23.build("e2", "swampert", areas: ["Raids"], powerUp: false, viaMega: true), P23.build("s1", "rhyperior_shadow", areas: ["Raids"])]
        let rotation = [fire, P23.row("2026-11-02", "2026-11-02", .maxMonday, title: "Max Monday", bosses: [P23.boss("garchomp_mega", types: ["dragon", "ground"])])]
        let ctx = P23.ctx(builds: builds, entries: [P23.entry("e2", "swampert"), P23.entry("s1", "rhyperior", shadow: 1)], table: table, rotation: rotation)
        let rows = HubSquads.bestRaidRows(row: fire, ctx: ctx)
        func row(_ key: String) throws -> HubSquads.BestRow { try XCTUnwrap(rows.first { $0.key == key }, "\(key) is in the lists: \(rows.map(\.key))") }

        // A Mega Evolve build fills the Mega row and the plain row; the first row asked (the Mega, the lists being in role order) shows the copy, the other says so.
        let mega = try row("swampert_mega"), plain = try row("swampert")
        XCTAssertEqual([mega.tier, plain.tier], ["S", "A"])
        XCTAssertEqual([mega.ownedEntryId, plain.ownedEntryId], ["e2", "e2"])
        XCTAssertEqual(plain.sharedWith, mega.name)
        XCTAssertEqual(mega.name, P23.gm.byId["swampert_mega"]!.name, "a Mega keeps the game master's name")
        XCTAssertEqual(mega.status.kind, .inBox)
        // A Shadow copy fills its Shadow row and the plain row; the Shadow row is named as the box names it and the table lists no Shadow Rhyperior.
        let shadow = try row("rhyperior_shadow"), rhy = try row("rhyperior")
        XCTAssertEqual(shadow.name, "Rhyperior (Shadow)")
        XCTAssertEqual(shadow.tier, "", "the table lists the plain Rhyperior only")
        XCTAssertEqual(rhy.tier, "S")
        XCTAssertEqual([shadow.ownedEntryId, rhy.ownedEntryId], ["s1", "s1"])
        XCTAssertEqual(rhy.sharedWith, "Rhyperior (Shadow)")
        // Listed but off the schedule and not in the box: the table's reason; kyogre's obtain line is Easy but a Legendary comes through events.
        let kyogre = try row("kyogre")
        XCTAssertEqual(kyogre.tier, "B")
        XCTAssertEqual(kyogre.status.text, "Not available now · not on the schedule")
        XCTAssertEqual(kyogre.availability, "Easy. Wild", "the table's obtain text is kept")
        // Not in the table, on the schedule later: the rotation line, no tier; not in the table, not on the schedule: Not available now with no reason.
        let coming = try row("garchomp_mega")
        XCTAssertEqual(coming.tier, "")
        XCTAssertEqual(coming.rotationLine, "Max Monday 2 Nov")
        XCTAssertEqual(coming.status.text, "Not available now · Max Monday 2 Nov")
        let unlisted = try row("groudon_primal")
        XCTAssertEqual(unlisted.tier, ""); XCTAssertEqual(unlisted.availability, ""); XCTAssertNil(unlisted.rotationLine)
        XCTAssertEqual(unlisted.status.text, "Not available now")
        // Fire is not a bring type: Shadow Groudon, listed there, carries no tier.
        let gs = try row("groudon_shadow")
        XCTAssertEqual(gs.tier, ""); XCTAssertEqual(gs.name, "Groudon (Shadow)")
        XCTAssertEqual(gs.status.text, "Not available now · not on the schedule", "listed by the table, so the table's reason")
    }

    /// A Shadow row exists only for a Shadow that exists: the table lists it under some type section, or the box holds a Shadow copy. Shadow Kyogre and Shadow Groudon (tagged shadow
    /// eligible in the game master, not real Shadows) drop out of a list that neither has them.
    func testAShadowRowIsListedOnlyForAShadowThatExists() throws {
        let fire = P23.row("2026-10-20", "2026-10-30", bosses: [P23.boss("charizard", types: ["fire"])])
        let empty = P23.table([P23.tierEntry("raids", "Water", "A", "swampert")])
        let none = HubSquads.bestRaidRows(row: fire, ctx: P23.ctx(builds: [], entries: [P23.entry("e1", "swampert")], table: empty, rotation: [fire]))
        XCTAssertTrue(none.filter { $0.key.hasSuffix("_shadow") }.allSatisfy { !["kyogre_shadow", "groudon_shadow"].contains($0.key) }, "no Shadow Kyogre or Groudon: \(none.map(\.key))")
        XCTAssertFalse(none.contains { $0.key == "kyogre_shadow" })
        // A table that lists Shadow Kyogre under any section (here Fire, not a bring type) gives it a row; so does a Shadow copy in the box.
        let listed = P23.table([P23.tierEntry("raids", "Fire", "S", "kyogre_shadow", shadow: true)])
        XCTAssertTrue(HubSquads.bestRaidRows(row: fire, ctx: P23.ctx(builds: [], entries: [], table: listed, rotation: [fire])).contains { $0.key == "kyogre_shadow" })
        let owned = HubSquads.bestRaidRows(row: fire, ctx: P23.ctx(builds: [], entries: [P23.entry("k1", "kyogre", shadow: 1)], table: empty, rotation: [fire]))
        XCTAssertTrue(owned.contains { $0.key == "kyogre_shadow" }, "the box holds a Shadow Kyogre: \(owned.map(\.key))")
    }

    func testAStatusFollowsTheBoxAndTheRotation() throws {
        let (row, ctx) = try sableye()
        let rows = HubSquads.bestRaidRows(row: row, ctx: ctx)
        let boxIds = Set(ctx.entries.map(\.id))
        XCTAssertTrue(rows.contains { $0.inBox }, "the fixture box has some of them")
        for r in rows {
            if let id = r.ownedEntryId { XCTAssertTrue(boxIds.contains(id), r.name) }
            if r.inBox {
                XCTAssertEqual(r.status.kind, .inBox)
                XCTAssertEqual(r.status.needsUpgrade, r.build.map { !HubSquads.isFullStrength($0, screen: .raids, ctx: ctx) } ?? true, r.name)
                XCTAssertEqual(r.availability, "")
            } else if let info = HubSquads.rotationInfo(of: P23.tierEntry("raids", "", "", r.speciesId, shadow: r.key.hasSuffix("_shadow")), ctx: ctx), info.now {
                XCTAssertEqual(r.status, HubSquads.BestStatus(kind: .canGetNow, needsUpgrade: false, detail: info.line), r.name)
            } else {
                XCTAssertNotEqual(r.status.kind, .inBox)
            }
        }
    }

    func testBestSquadsFillByStyle() throws {
        let (row, ctx) = try sableye()
        let rows = HubSquads.bestRaidRows(row: row, ctx: ctx)
        func roles(_ style: RaidStyle) -> [String] {
            let filled = HubSquads.bestSquad(slots: HubSquads.defaultRaidSlots(style: style), rows: rows, fallback: true, oneMega: true)
            XCTAssertTrue(filled.allSatisfy { $0.pickId != nil }, "every slot is filled")
            return filled.map { f in rows.first { $0.ids.contains(f.pickId!) }!.roles[0] }
        }
        XCTAssertEqual(roles(.balanced), ["Mega", "Heavy hitter", "Heavy hitter", "Heavy hitter", "Bulky hitter", "Bulky hitter"])
        XCTAssertEqual(roles(.maxDamage), ["Mega"] + Array(repeating: "Heavy hitter", count: 5))
        let balanced = HubSquads.bestSquad(slots: HubSquads.defaultRaidSlots(style: .balanced), rows: rows, fallback: true, oneMega: true)
        XCTAssertEqual(Set(balanced.compactMap(\.pickId)).count, 6, "six different Pokémon")
    }

    /// The cost of one boss's list on this Mac, cold and again with the scale warm; printed for the report.
    func testTheCostOfAListIsMeasured() throws {
        let (row0, ctx) = try sableye()
        // A boss no other test uses, so the scale is not already warm.
        var row = row0
        row.bosses = [P23.boss("snorlax", types: ["normal"])]
        row.title = "Cost probe"
        DamageEstimate.clearCache()
        HubSquads.clearRaidRankCache()
        let t0 = Date()
        let cold = HubSquads.bestRaidRows(row: row, ctx: ctx)
        let coldMs = Date().timeIntervalSince(t0) * 1000
        let t1 = Date()
        let warm = HubSquads.bestRaidRows(row: row, ctx: ctx)
        let warmMs = Date().timeIntervalSince(t1) * 1000
        print("BEST-RAID-ROWS-COST cold \(String(format: "%.0f", coldMs)) ms, repeated \(String(format: "%.0f", warmMs)) ms, \(cold.count) rows")
        XCTAssertEqual(cold.map(\.key), warm.map(\.key))
        XCTAssertEqual(cold.count, 36)
    }
}
