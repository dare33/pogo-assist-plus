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

    // MARK: squad strength (CONCEPTS rule 32) and the fixed suggestion (rule 27), on the real box

    private func figures(_ filled: [FilledSlot], rows: (Int) -> [PickerRowModel], empty: Strength) -> [Strength?] {
        filled.indices.map { i in filled[i].pickId == nil ? nil : (rows(i).first(where: \.ticked)?.strength ?? empty) }
    }

    /// The squad's bar is the mean of the figures its slots' Pokémon show as rows in their pickers, on every screen, in both modes; the squad measure is printed.
    func testSquadStrengthIsTheMeanOfTheSlotsPickerRowFigures() throws {
        let c = ctx()
        var checked = 0
        func same(_ a: SquadStrength, _ b: SquadStrength, _ what: String) {
            XCTAssertEqual(a, b, what)
            XCTAssertEqual(a.total, b.total, what)
            checked += 1
        }
        var times = [String: Double](), counts = [String: Int]()
        func timed(_ name: String, _ work: () -> Void) { let t0 = Date(); work(); times[name, default: 0] += Date().timeIntervalSince(t0) * 1000; counts[name, default: 0] += 1 }
        for mode in [SquadMode.available, .best] {
            for row in Self.hub.rotation where !row.bosses.isEmpty && [.fiveStar, .mega, .shadow, .maxMonday, .maxEvent].contains(row.kind) {
                let screen: SquadScreen = [.maxMonday, .maxEvent].contains(row.kind) ? .max : .raids
                let b = EventPickerBuilder(screen: screen, row: row, ctx: c)
                let (options, filled) = b.resolve(slots: screen == .raids ? HubSquads.defaultRaidSlots() : HubSquads.defaultMaxSlots(), mode: mode)
                let byId = Dictionary(options.flatMap { o in [(o.entryId, o)] + (o.best.map { [(squadSpeciesPrefix + $0.key, o)] } ?? []) }, uniquingKeysWith: { a, _ in a })
                var fast: SquadStrength?
                timed(screen == .raids ? "raids" : "max") { fast = b.squadStrength(filled: filled, options: options, byId: byId, mode: mode) }
                let slow = SquadStrength.of(figures: figures(filled, rows: { b.content(slot: $0, filled: filled, options: options, byId: byId, mode: mode).rows }, empty: Strength(kind: .damage, now: nil, after: nil)))
                same(fast!, slow, "\(screen) \(row.title) \(mode)")
            }
            let g = GymPickerBuilder(ctx: c)
            let r = g.resolve(mode: mode, saved: SquadStore.Saved(slots: HubSquads.defaultGymSlots()))
            let gById = Dictionary(r.options.flatMap { o in [(o.id, o)] + (o.best.map { [(squadSpeciesPrefix + $0.key, o)] } ?? []) }, uniquingKeysWith: { a, _ in a })
            var gFast: SquadStrength?
            timed("gym") { gFast = g.squadStrength(filled: r.filled, options: r.options, byId: gById, mode: mode) }
            same(gFast!, SquadStrength.of(figures: figures(r.filled, rows: { g.content(slot: $0, filled: r.filled, options: r.options, byId: gById, mode: mode).rows }, empty: Strength(kind: .bulk, now: nil, after: nil)), kind: .bulk), "gym \(mode)")
            for leader in Self.hub.leaders {
                let k = RocketPickerBuilder(leader: leader, ctx: c)
                let filled = mode == .best ? HubSquads.bestRocketSquad(leader: leader, ctx: c) : HubSquads.rocketSquad(leader: leader, mode: mode, ctx: c)
                let lists = leader.slots.map { k.entries(for: $0, mode: mode) }
                var kFast: SquadStrength?
                timed("rocket") { kFast = k.squadStrength(filled: filled, lists: lists, mode: mode) }
                same(kFast!, SquadStrength.of(figures: figures(filled, rows: { k.content(slot: $0, filled: filled, lists: lists, mode: mode).rows }, empty: Strength(kind: .damage, now: nil, after: nil))), "rocket \(leader.name) \(mode)")
            }
            for league in LeaguePanel.keys {
                let p = PvPPickerBuilder(league: league, ctx: c, pogoAssist: false)
                let r = p.resolve(mode: mode, slots: HubSquads.defaultPvpSlots())
                var pFast: SquadStrength?
                timed("pvp") { pFast = p.squadStrength(filled: r.filled, candidates: r.candidates, byId: r.byId, best: r.best, mode: mode) }
                same(pFast!, SquadStrength.of(figures: figures(r.filled, rows: { p.content(slot: $0, filled: r.filled, candidates: r.candidates, byId: r.byId, best: r.best, mode: mode).rows }, empty: Strength.scoreNotKnown), kind: .score), "pvp \(league) \(mode)")
            }
        }
        XCTAssertGreaterThan(checked, 20)
        print("P2-4-TIMING squad strength, summed over every event, leader and league in both modes (ms): " + times.sorted { $0.key < $1.key }.map { "\($0.key) \(String(format: "%.0f", $0.value)) over \(counts[$0.key] ?? 0) squads" }.joined(separator: ", "))
    }

    /// The same, one squad: opening a Gym or Rocket screen adds one strength computation; Gym's guard is the picker's own 40 ms per slot.
    func testSquadStrengthDoesNotSlowTheGymScreen() throws {
        let c = ctx()
        let g = GymPickerBuilder(ctx: c)
        let r = g.resolve(mode: .available, saved: SquadStore.Saved(slots: HubSquads.defaultGymSlots()))
        let byId = Dictionary(r.options.flatMap { o in [(o.id, o)] + (o.best.map { [(squadSpeciesPrefix + $0.key, o)] } ?? []) }, uniquingKeysWith: { a, _ in a })
        _ = g.squadStrength(filled: r.filled, options: r.options, byId: byId, mode: .available)   // the first call also loads the game master hash
        let t0 = Date()
        let s = g.squadStrength(filled: r.filled, options: r.options, byId: byId, mode: .available)
        let ms = Date().timeIntervalSince(t0) * 1000
        print("P2-4-TIMING Gym squad strength: \(String(format: "%.0f", ms)) ms, \(s.text), \(s.scoredText ?? "all scored")")
        XCTAssertLessThan(ms, 150)
    }

    /// Rule 27 through the Gym builder: the suggestion is kept at the first change; a box change or a mode switch back and forth then moves nothing; Back restores it.
    func testGymSuggestionIsKeptAtTheFirstChangeAndBackRestoresIt() throws {
        let c = ctx()
        let g = GymPickerBuilder(ctx: c)
        var saved = SquadStore.Saved(slots: HubSquads.defaultGymSlots())
        let first = g.resolve(mode: .best, saved: saved).filled
        XCTAssertEqual(first.count, 6)
        let replacement = try XCTUnwrap(g.resolve(mode: .best, saved: saved).candidates.last?.entryId)
        XCTAssertFalse(first.contains { $0.pickId == replacement })
        saved.choose(replacement, at: 0, shown: first)
        let after = g.resolve(mode: .best, saved: saved).filled
        XCTAssertEqual(after.map(\.pickId), [replacement] + first.dropFirst().map(\.pickId), "only slot 1 changed; the Pokémon it held did not drop into another slot")
        // Another change keeps the rest: a swap of slot 2 and slot 3.
        saved.choose(after[2].pickId, at: 1, shown: after)
        let swapped = g.resolve(mode: .best, saved: saved).filled
        XCTAssertEqual(swapped.map(\.pickId), [after[0].pickId, after[2].pickId, after[1].pickId] + after.dropFirst(3).map(\.pickId))
        saved.backToSuggested(defaults: HubSquads.defaultGymSlots())
        XCTAssertEqual(g.resolve(mode: .best, saved: saved).filled.map(\.pickId), first.map(\.pickId))
        XCTAssertFalse(saved.showsBackToSuggested)
    }

    /// A picker lists the Pokémon of the squad's other slots, marked with their slot, and the slot's own row stays ticked and unmarked (rule 4 as changed with rule 27).
    func testPickersListOtherSlotsPokemonMarkedForTheSwap() throws {
        let c = ctx()
        let g = GymPickerBuilder(ctx: c)
        let r = g.resolve(mode: .available, saved: SquadStore.Saved(slots: HubSquads.defaultGymSlots()))
        let byId = Dictionary(r.options.flatMap { o in [(o.id, o)] }, uniquingKeysWith: { a, _ in a })
        let filled = r.filled
        let first = try XCTUnwrap(filled[0].pickId)
        let rows = g.content(slot: 1, filled: filled, options: r.options, byId: byId, mode: .available).rows
        let held = try XCTUnwrap(rows.first { $0.id == first }, "slot 1's Pokémon is listed in slot 2's picker")
        XCTAssertEqual(held.swapSlot, 1)
        XCTAssertTrue(held.spoken.hasSuffix("in slot 1, choosing it swaps the two"), held.spoken)
        XCTAssertFalse(held.movesHere, "slot 2 holds a Pokémon, so it is a swap")
        XCTAssertFalse(held.ticked)
        XCTAssertNil(rows.first(where: \.ticked)?.swapSlot)
    }

    // MARK: fold round 1 (review of b7071d8), on the real box

    private func eventSquad(_ b: EventPickerBuilder, _ saved: SquadStore.Saved, _ mode: SquadMode) -> (options: [EventOption], byId: [String: EventOption], filled: [FilledSlot]) {
        let (options, filled) = b.resolve(slots: saved.slots, mode: mode)
        let byId = Dictionary(options.flatMap { o in [(o.entryId, o)] + (o.best.map { [(squadSpeciesPrefix + $0.key, o)] } ?? []) }, uniquingKeysWith: { a, _ in a })
        return (options, byId, filled)
    }

    /// Opus F1's probe: Giratina, Available; choosing a marked Pokémon in a slot, twice, loses no Pokémon and empties no slot, and what the player sees is what moved.
    func testChoosingMarkedPokemonTwiceOnGiratinaLosesNothing() throws {
        let c = ctx()
        let row = try XCTUnwrap(Self.hub.rotation.first { [.fiveStar, .mega, .shadow].contains($0.kind) && $0.bosses.contains { $0.speciesId.hasPrefix("giratina") } })
        let b = EventPickerBuilder(screen: .raids, row: row, ctx: c)
        var saved = SquadStore.Saved(slots: HubSquads.defaultRaidSlots())
        for round in 1...2 {
            let r = eventSquad(b, saved, .available)
            let before = r.filled.map(\.pickId)
            XCTAssertEqual(before.compactMap { $0 }.count, 6, "round \(round): six shown")
            // Slot 4 (a Heavy hitter): the first marked row.
            let rows = b.content(slot: 3, filled: r.filled, options: r.options, byId: r.byId, mode: .available).rows
            let marked = try XCTUnwrap(rows.first { $0.swapSlot != nil && !$0.ticked }, "round \(round): a marked row is listed")
            let from = try XCTUnwrap(marked.swapSlot) - 1
            XCTAssertEqual(from == 0, false, "a Heavy hitter slot does not offer the Mega slot's Pokémon unless it can hold it")
            saved.choose(marked.id, at: 3, alsoClearing: [marked.id], shown: r.filled)
            let after = eventSquad(b, saved, .available).filled.map(\.pickId)
            var expected = before; expected[3] = before[from]; expected[from] = before[3]
            XCTAssertEqual(after, expected, "round \(round): the two shown occupants exchanged, nothing else moved")
            XCTAssertEqual(Set(after.compactMap { $0 }).count, 6, "round \(round): no Pokémon lost")
        }
    }

    /// Sol 1: a slot that refills in a changed squad is kept, so a later box change does not move it.
    func testARefilledSlotIsKeptAcrossALaterBoxChange() throws {
        let c = ctx()
        let g = GymPickerBuilder(ctx: c)
        var saved = SquadStore.Saved(slots: HubSquads.defaultGymSlots())
        let first = g.resolve(mode: .best, saved: saved).filled
        saved.choose(try XCTUnwrap(first[2].pickId), at: 0, shown: first)
        var store = SquadStore(); store.gym = saved
        // The copy in slot 4 (if any is owned) leaves the box: use a stored pick that is no longer there.
        store.gym.slots[3].pick = "gone-from-box"
        let reconciled = store.reconciled(boxIds: Set(c.entries.map(\.id))).gym
        let drawn = g.resolve(mode: .best, saved: reconciled).filled
        XCTAssertNotNil(drawn[3].pickId, "the slot refills")
        XCTAssertTrue(reconciled.needsAdopting(drawn))
        var adopted = reconciled; adopted.adoptRefills(drawn)
        XCTAssertEqual(g.resolve(mode: .best, saved: adopted).filled.map(\.pickId), drawn.map(\.pickId))
        // A later box change would have moved an unkept refill; the kept one stays whatever the ranking does (the stored pick is what is placed).
        XCTAssertEqual(adopted.slots[3].pickId, drawn[3].pickId)
    }

    /// A mode switch and back, then an edit: the edit acts on what is shown under the mode being edited, and the Best pick it replaced is not resurrected by the swap.
    func testEditingAfterAModeSwitchActsOnWhatIsShown() throws {
        let c = ctx()
        let g = GymPickerBuilder(ctx: c)
        var saved = SquadStore.Saved(slots: HubSquads.defaultGymSlots())
        let best = g.resolve(mode: .best, saved: saved)
        let notOwned = try XCTUnwrap(best.filled.first { $0.species != nil }, "Best shows a Pokémon the box lacks")
        saved.choose(notOwned.pickId, at: 0, shown: best.filled)
        let avail = g.resolve(mode: .available, saved: saved)
        XCTAssertNotEqual(avail.filled[0].pickId, notOwned.pickId, "Available does not place it")
        let shownAvailable = avail.filled.map(\.pickId)
        let target = try XCTUnwrap(shownAvailable.compactMap { $0 }.first)
        saved.choose(target, at: 1, shown: avail.filled)
        XCTAssertEqual(saved.slots.map(\.pickId).filter { $0 != nil }.count, Set(saved.slots.compactMap(\.pickId)).count, "no Pokémon twice")
        XCTAssertFalse(saved.slots.contains { $0.species == notOwned.species && notOwned.species != nil }, "the unplaced Best pick is replaced by what Available showed")
    }

    /// Sol 3: Rocket lists the other slots' Pokémon even when they do not beat this slot, marked.
    func testRocketListsEveryOtherSlotsPokemon() throws {
        let c = ctx()
        let leader = try XCTUnwrap(Self.hub.leaders.first { $0.name == "Giovanni" } ?? Self.hub.leaders.first)
        let k = RocketPickerBuilder(leader: leader, ctx: c)
        for mode in [SquadMode.available, .best] {
            let filled = mode == .best ? HubSquads.bestRocketSquad(leader: leader, ctx: c) : HubSquads.rocketSquad(leader: leader, mode: mode, ctx: c)
            let lists = leader.slots.map { k.entries(for: $0, mode: mode) }
            for i in filled.indices {
                let rows = k.content(slot: i, filled: filled, lists: lists, mode: mode).rows
                for (j, f) in filled.enumerated() where j != i {
                    guard let id = f.pickId else { continue }
                    let row = try XCTUnwrap(rows.first { $0.id == id }, "\(mode): slot \(j + 1)'s Pokémon is listed in slot \(i + 1)'s picker")
                    XCTAssertEqual(row.swapSlot, j + 1)
                }
            }
        }
    }

    /// Sol 3 / Opus F8: under Best a raid squad's held Mega stays listed for a swap that cannot raise the Mega count (the other slot can hold the edited slot's Pokémon).
    func testAHeldMegaIsListedForAValidSwapUnderBest() throws {
        let c = ctx()
        let row = try XCTUnwrap(Self.hub.rotation.first { $0.kind == .fiveStar && $0.bosses.contains { $0.speciesId == "palkia" } })
        let b = EventPickerBuilder(screen: .raids, row: row, ctx: c)
        let all = SquadStore.Saved(slots: HubSquads.defaultRaidSlots().map { _ in SquadSlot(role: squadRoleAll) })
        let r = eventSquad(b, all, .best)
        let megas = HubSquads.megaRowIds(r.options.compactMap(\.best))
        let holder = try XCTUnwrap(r.filled.firstIndex { $0.ids.contains(where: megas.contains) }, "a Mega is in the squad")
        let editing = holder == 5 ? 4 : 5
        let rows = b.content(slot: editing, filled: r.filled, options: r.options, byId: r.byId, mode: .best).rows
        let held = try XCTUnwrap(rows.first { $0.swapSlot == holder + 1 }, "the held Mega is listed, marked")
        XCTAssertTrue(megas.contains(held.id) || r.filled[holder].ids.contains(held.id))
        XCTAssertEqual(rows.filter { megas.contains($0.id) && $0.swapSlot == nil && !$0.ticked }.count, 0, "no other Mega row is offered")
    }

    /// A swap that cannot happen is not listed: the Mega slot takes Mega candidates only, so a plain copy's Pokémon is not offered the Mega slot's.
    func testASwapThatCannotHappenIsNotListed() throws {
        let c = ctx()
        let row = try XCTUnwrap(Self.hub.rotation.first { $0.kind == .fiveStar && $0.bosses.contains { $0.speciesId == "palkia" } })
        let b = EventPickerBuilder(screen: .raids, row: row, ctx: c)
        let r = eventSquad(b, SquadStore.Saved(slots: HubSquads.defaultRaidSlots()), .available)
        let mega = try XCTUnwrap(r.filled[0].pickId)
        let place = HubSquads.placeable(screen: .raids, mode: .available, ctx: c)
        for i in 1..<6 {
            let rows = b.content(slot: i, filled: r.filled, options: r.options, byId: r.byId, mode: .available).rows
            let offered = rows.contains { $0.id == mega }
            XCTAssertEqual(offered, place(try XCTUnwrap(r.filled[i].pickId), r.filled[0].role), "slot \(i + 1)'s picker offers the Mega slot's Pokémon only if the Mega slot can hold slot \(i + 1)'s")
        }
    }

    /// Strength for a kept species pick and for a pick the picker does not list: each equals the figure the picker row shows.
    func testStrengthForAKeptSpeciesPickAndAnUnlistedPick() throws {
        let c = ctx()
        let g = GymPickerBuilder(ctx: c)
        var saved = SquadStore.Saved(slots: HubSquads.defaultGymSlots())
        let best = g.resolve(mode: .best, saved: saved)
        let species = try XCTUnwrap(best.filled.first { $0.species != nil }?.pickId)
        let unlisted = try XCTUnwrap(c.entries.first { e in !g.resolve(mode: .available, saved: saved).options.contains { $0.id == e.id } }?.id, "a copy no Gym build lists")
        saved.choose(species, at: 0, shown: best.filled)
        saved.choose(unlisted, at: 1, shown: g.resolve(mode: .best, saved: saved).filled)
        for mode in [SquadMode.best, .available] {
            let r = g.resolve(mode: mode, saved: saved)
            let byId = Dictionary(r.options.flatMap { o in [(o.id, o)] + (o.best.map { [(squadSpeciesPrefix + $0.key, o)] } ?? []) }, uniquingKeysWith: { a, _ in a })
            let fast = g.squadStrength(filled: r.filled, options: r.options, byId: byId, mode: mode)
            let slow = SquadStrength.of(figures: figures(r.filled, rows: { g.content(slot: $0, filled: r.filled, options: r.options, byId: byId, mode: mode).rows }, empty: Strength(kind: .bulk, now: nil, after: nil)), kind: .bulk)
            XCTAssertEqual(fast, slow, "\(mode)")
        }
        let r = g.resolve(mode: .best, saved: saved)
        XCTAssertEqual(r.filled[0].pickId, species)
        XCTAssertEqual(r.filled[1].pickId, unlisted)
        let byId = Dictionary(r.options.flatMap { o in [(o.id, o)] + (o.best.map { [(squadSpeciesPrefix + $0.key, o)] } ?? []) }, uniquingKeysWith: { a, _ in a })
        let rows1 = g.content(slot: 1, filled: r.filled, options: r.options, byId: byId, mode: .best).rows
        XCTAssertNotNil(rows1.first(where: \.ticked)?.strength, "the unlisted copy has a figure from its own row")
    }
}
