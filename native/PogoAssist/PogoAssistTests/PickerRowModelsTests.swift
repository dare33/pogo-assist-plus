import XCTest
@testable import PogoAssist
@testable import PogoBox
import PogoReader

/// P1, on Greg's real box of 22 Oct 2026 through the real engine: every picker row the five squad screens would list, Available and Best, carries its CP and IV line
/// and a strength figure, or says why it has none. The rows come from the same builders the screens use.
final class PickerRowModelsTests: XCTestCase {
    private static var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    private static let gm = try! GameMaster.bundled()
    private static let hub = try! HubData.bundled()
    private static let table = try! TierTable.bundled()

    private static let box: (entries: [BoxEntry], advice: BoxAdvice) = {
        let text = try! String(contentsOf: root.appendingPathComponent("fixtures/greg-2026-10-22.box.csv"), encoding: .utf8)
        let entries = BoxCSVReader.entries(csv: text, gm: gm)
        let rows = entries.enumerated().map { i, e in var r = e.row; r.index = i + 1; return r }
        return (entries, BoxAdvice.make(from: try! CoreEngine().advise(rows: rows, scanDate: Date(timeIntervalSince1970: 1_790_000_000)), entries: entries))
    }()

    private func ctx(today: String = "2026-10-26") -> HubContext { HubContext(advice: Self.box.advice, entries: Self.box.entries, gm: Self.gm, hub: Self.hub, table: Self.table, today: today) }

    /// A row with no strength must say why in its spoken label; one with a copy has the CP and IV line; one without a copy is a Pokémon the box lacks (`best`: the screen's
    /// Best rows, which say whether the box has the Pokémon; a species-pick id alone does not, since a Best row whose copy a higher row shows is a species pick too).
    private func check(_ rows: [PickerRowModel], _ what: String, best: [HubSquads.BestRow], ivs: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        for m in rows {
            let reason = m.spoken.contains("not read") || m.spoken.contains("score not known")
            XCTAssertTrue(m.strength != nil || reason, "\(what): \(m.name) has no strength and no reason: \(m.spoken)", file: file, line: line)
            // An owned row (any screen, PvP included) always has its CP and IV line; only a Pokémon the box lacks, whose row id is a species pick, may go without.
            if m.cpIv == nil {
                let lacking = m.id.hasPrefix(squadSpeciesPrefix) && best.contains { $0.entryId == m.id } && !best.contains { $0.entryId == m.id && $0.inBox }
                XCTAssertTrue(lacking, "\(what): \(m.name) is an owned row without its CP and IV line", file: file, line: line)
            }
            XCTAssertFalse(m.spoken.contains(" · "), "\(what): spoken text uses commas: \(m.spoken)", file: file, line: line)
        }
    }

    func testRaidsAndMaxPickersCarryFigures() throws {
        let c = ctx()
        var checked = 0
        for row in Self.hub.rotation where !row.bosses.isEmpty && [.fiveStar, .mega, .shadow, .maxMonday, .maxEvent].contains(row.kind) {
            let screen: SquadScreen = [.maxMonday, .maxEvent].contains(row.kind) ? .max : .raids
            for mode in [SquadMode.available, .best] {
                let slots = EventPickerBuilder(screen: screen, row: row, ctx: c).allSlotRows(mode: mode)
                XCTAssertFalse(slots.isEmpty)
                let best = screen == .raids ? HubSquads.bestRaidRows(row: row, ctx: c) : HubSquads.bestMaxRows(row: row, ctx: c)
                for rows in slots { check(rows, "\(screen) \(row.title) \(mode)", best: best); checked += rows.count }
            }
        }
        XCTAssertGreaterThan(checked, 500)
    }

    func testGymRocketAndPvPPickersCarryFigures() throws {
        let c = ctx()
        var checked = 0
        for mode in [SquadMode.available, .best] {
            for rows in GymPickerBuilder(ctx: c).allSlotRows(mode: mode) { check(rows, "gym \(mode)", best: HubSquads.bestGymRows(ctx: c)); checked += rows.count }
            for leader in Self.hub.leaders {
                for rows in RocketPickerBuilder(leader: leader, ctx: c).allSlotRows(mode: mode) { check(rows, "rocket \(leader.name) \(mode)", best: leader.slots.flatMap { HubSquads.bestRocketRows(options: $0, ctx: c) }); checked += rows.count }
            }
            for league in LeaguePanel.keys {
                for rows in PvPPickerBuilder(league: league, ctx: c, pogoAssist: false).allSlotRows(mode: mode) { check(rows, "pvp \(league) \(mode)", best: HubSquads.bestPvpRows(league: league, ctx: c)); checked += rows.count }
            }
        }
        XCTAssertGreaterThan(checked, 300)
    }

    /// Gym and PvP rows say the new words in their spoken label ("percent of the best", "score N" or "score not known"), not only words the rows already had.
    func testGymAndPvPRowsSayTheNewFigureWords() throws {
        let c = ctx()
        let gym = GymPickerBuilder(ctx: c).allSlotRows(mode: .available).flatMap { $0 }
        XCTAssertFalse(gym.isEmpty)
        for m in gym where m.cpIv != nil && m.strength != nil { XCTAssertTrue(m.spoken.contains("percent of the best"), m.spoken) }
        let pvp = PvPPickerBuilder(league: "ul", ctx: c, pogoAssist: false).allSlotRows(mode: .best).flatMap { $0 }
        XCTAssertFalse(pvp.isEmpty)
        for m in pvp { XCTAssertTrue(m.spoken.contains("score"), m.spoken) }
        XCTAssertTrue(pvp.contains { $0.cpIv == nil }, "a Best row the box lacks has no CP line")
        XCTAssertTrue(pvp.allSatisfy { $0.cpIv == nil || $0.cpIv!.contains("/") || $0.cpIv!.contains("IVs not read") }, "PvP rows show IVs too")
    }

    /// The Gym picker opens without a visible delay: the best Gym bulk hashes the whole game master, so the builder works it out once per picker, not once per row.
    func testGymPickerOpensQuicklyOnTheRealBox() throws {
        let c = ctx()
        let b = GymPickerBuilder(ctx: c)
        let t0 = Date()
        let slots = b.allSlotRows(mode: .available)
        let perSlot = Date().timeIntervalSince(t0) * 1000 / Double(max(slots.count, 1))
        print("P1-TIMING Gym picker content: \(slots.count) slots, \(String(format: "%.0f", perSlot)) ms each, \(slots.first?.count ?? 0) rows")
        XCTAssertGreaterThan(slots.first?.count ?? 0, 5)
        XCTAssertLessThan(perSlot, 40, "one game master hash per picker, not one per row")
    }

    /// Ruling 9: a Mega entry is judged as a Mega only in the raid Mega slot. Under Best a Mega row listed under another role's slot (the All chip) is the plain Pokémon.
    func testAMegaIsJudgedAsMegaOnlyInTheMegaSlot() throws {
        let c = ctx()
        let row = try XCTUnwrap(Self.hub.rotation.first { $0.kind == .fiveStar && $0.bosses.contains { $0.speciesId == "palkia" } })
        let b = EventPickerBuilder(screen: .raids, row: row, ctx: c)
        let mega = BoxAdvice.Build(entryId: "x", title: "", cp: 0, level: 30, ivs: nil, targetId: "gengar", targetName: "Gengar", powerUp: true, formChange: false, viaMega: true, needsDynamax: false,
                                   spares: 0, areas: ["Raids"], tier: "S", targetLevel: 40, dust: 0, candy: 0, xl: 0, pvp: nil, score: 0, steps: [.init(kind: "megaEvolve")])
        let opt = EventOption(build: mega, best: nil, name: "Mega Gengar", tier: "S", roles: ["Mega"], types: ["ghost", "poison"], id: "x")
        XCTAssertTrue(b.judgesAsMega(build: mega, role: PogoRules.RaidRole.mega.rawValue, mode: .best, option: opt))
        XCTAssertFalse(b.judgesAsMega(build: mega, role: squadRoleAll, mode: .best, option: opt), "the All chip is not the Mega slot")
        XCTAssertFalse(b.judgesAsMega(build: mega, role: PogoRules.RaidRole.heavy.rawValue, mode: .best, option: opt))
        XCTAssertFalse(b.judgesAsMega(build: mega, role: squadRoleAll, mode: .available, option: opt))
        // The rows of an All-role slot under Best: a Mega row there equals the plain judgement of the same build.
        let slots = [SquadSlot(role: squadRoleAll)]
        let (options, filled) = b.resolve(slots: slots, mode: .best)
        let byId = Dictionary(options.flatMap { o in [(o.entryId, o)] + (o.best.map { [(squadSpeciesPrefix + $0.key, o)] } ?? []) }, uniquingKeysWith: { a, _ in a })
        let rows = b.content(slot: 0, filled: filled, options: options, byId: byId, mode: .best).rows
        let megaRows = rows.filter { $0.name.hasPrefix("Mega ") && $0.cpIv != nil }
        let m = try XCTUnwrap(megaRows.first, "the real box has an owned Mega row under Best")
        let o = try XCTUnwrap(options.first(where: { $0.id == m.id }))
        let build = try XCTUnwrap(o.build)
        let scale = try XCTUnwrap(b.strengthScale())
        let plain = scale.strength(.init(copy: c.entry(build.entryId), build: build, built: m.mark == .fullStrength, megaSlot: false))
        XCTAssertEqual(m.strength, plain, "a Mega row in an All slot is judged on the plain form")
        // A Mega or Primal entry the box lacks is judged as the plain Pokémon outside the Mega slot too, and as the Mega form in it.
        let lackingForms = rows.filter { ($0.name.hasPrefix("Mega ") || $0.name.hasPrefix("Primal ")) && $0.cpIv == nil }
        XCTAssertFalse(lackingForms.isEmpty, "Best lists a Mega or Primal entry the box lacks")
        for r in lackingForms {
            let best = try XCTUnwrap(options.compactMap(\.best).first { $0.entryId == r.id }, r.name)
            let asPlain = HubSquads.lacking(of: best, area: "raids", megaSlot: false, ctx: c)
            XCTAssertNotEqual(asPlain.speciesId, best.speciesId, "\(r.name) is judged as its base species")
            let expected = scale.strength(.init(copy: nil, build: nil, built: false, species: asPlain))
            XCTAssertEqual(r.strength, expected, "\(r.name) in an All slot is judged as the plain Pokémon")
        }
        // The raid Mega slot itself, built by the picker: the same entries the box lacks are judged as the Mega or Primal form there.
        let (megaOptions, megaFilled) = b.resolve(slots: [SquadSlot(role: PogoRules.RaidRole.mega.rawValue)], mode: .best)
        let megaById = Dictionary(megaOptions.flatMap { o in [(o.entryId, o)] + (o.best.map { [(squadSpeciesPrefix + $0.key, o)] } ?? []) }, uniquingKeysWith: { a, _ in a })
        let inMegaSlot = b.content(slot: 0, filled: megaFilled, options: megaOptions, byId: megaById, mode: .best).rows
            .filter { ($0.name.hasPrefix("Mega ") || $0.name.hasPrefix("Primal ")) && $0.cpIv == nil }
        XCTAssertFalse(inMegaSlot.isEmpty, "the Mega slot lists a Mega or Primal entry the box lacks")
        var differs = false
        for r in inMegaSlot {
            let best = try XCTUnwrap(megaOptions.compactMap(\.best).first { $0.entryId == r.id }, r.name)
            let asForm = scale.strength(.init(copy: nil, build: nil, built: false, species: HubSquads.lacking(of: best, area: "raids", megaSlot: true, ctx: c)))
            let asPlain = scale.strength(.init(copy: nil, build: nil, built: false, species: HubSquads.lacking(of: best, area: "raids", megaSlot: false, ctx: c)))
            XCTAssertEqual(r.strength, asForm, "\(r.name) in the Mega slot is judged as the Mega or Primal form")
            if asForm != asPlain { differs = true }
        }
        XCTAssertTrue(differs, "at least one Mega entry's figure differs from its plain Pokémon's, so the slot's judgement is tested")
    }
}
