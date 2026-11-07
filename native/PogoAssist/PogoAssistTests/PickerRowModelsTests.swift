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

    /// H4: Raids Best rows are worked out in a background task and cached; the view only looks them up. The ranking never runs on the main thread, a read is not a computation, and a box
    /// change drops what was ranked.
    @MainActor
    func testRaidsBestRowsAreRankedOffTheMainThreadAndOnlyReadFromTheCache() async throws {
        final class Probe: @unchecked Sendable {
            private let lock = NSLock()
            private var onMain = 0, total = 0
            func hit() { lock.lock(); total += 1; if Thread.isMainThread { onMain += 1 }; lock.unlock() }
            var counts: (onMain: Int, total: Int) { lock.lock(); defer { lock.unlock() }; return (onMain, total) }
        }
        let c = ctx()
        let row = try XCTUnwrap(Self.hub.rotation.first { $0.kind == .fiveStar && $0.bosses.contains { $0.speciesId == "palkia" } })
        let keeper = SquadKeeper(), probe = Probe()
        keeper.computeRaidRows = { r, context in probe.hit(); return HubSquads.bestRaidRows(row: r, ctx: context) }
        let key = keeper.raidRowsKey(row, style: .balanced, today: c.today)
        XCTAssertNil(keeper.cachedRaidRows(key), "nothing is ranked until asked")
        XCTAssertEqual(probe.counts.total, 0, "a read is a lookup")
        keeper.prefetchRaidRows([row], style: .balanced, ctx: c)
        var waited = 0
        while keeper.cachedRaidRows(key) == nil && waited < 600 { try await Task.sleep(nanoseconds: 100_000_000); waited += 1 }
        let rows = try XCTUnwrap(keeper.cachedRaidRows(key), "the ranking arrives")
        XCTAssertFalse(rows.isEmpty)
        XCTAssertEqual(probe.counts.onMain, 0, "the ranking was never entered on the main thread")
        XCTAssertEqual(probe.counts.total, 1)
        for _ in 0..<5 { _ = keeper.cachedRaidRows(key) }
        keeper.prefetchRaidRows([row], style: .balanced, ctx: c)
        XCTAssertEqual(probe.counts.total, 1, "reading the cache, and asking again, rank nothing more")
        // The screen's builder reads the rows it is given and does not rank (given none it would list the whole ranking).
        let given = EventPickerBuilder(screen: .raids, row: row, ctx: c, raidRows: [])
        XCTAssertTrue(given.resolve(slots: HubSquads.defaultRaidSlots(), mode: .best).options.isEmpty, "the injected rows are the Best list")
        XCTAssertFalse(EventPickerBuilder(screen: .raids, row: row, ctx: c, raidRows: rows).resolve(slots: HubSquads.defaultRaidSlots(), mode: .best).options.isEmpty)
        // A change to the box or its advice drops what was ranked.
        keeper.boxChanged()
        XCTAssertNil(keeper.cachedRaidRows(keeper.raidRowsKey(row, style: .balanced, today: c.today)))
        XCTAssertNil(keeper.cachedRaidRows(key))
    }

    /// J1: the Raids Best rows are needed (and the squad waits for the cache) whenever the body resolves a squad that holds a species pick, the Current included, never otherwise under Available.
    func testTheBodyNeedsTheRaidRowsForAnySquadItResolvesWithASpeciesPick() {
        let plain = [SquadSlot(role: "Mega", pick: "a"), SquadSlot(role: "Heavy hitter")]
        let species = [SquadSlot(role: "Mega"), SquadSlot(role: "Heavy hitter", species: "palkia")]
        XCTAssertTrue(EventSquadView.needsRaidRows(mode: .available, shown: plain, current: species), "the pill draws the Current, which holds a species pick")
        XCTAssertFalse(EventSquadView.needsRaidRows(mode: .available, shown: plain, current: plain), "no species picks under Available: nothing to wait for")
        XCTAssertFalse(EventSquadView.needsRaidRows(mode: .available, shown: plain, current: nil))
        XCTAssertTrue(EventSquadView.needsRaidRows(mode: .available, shown: species, current: nil), "the shown tab's own species pick")
        XCTAssertTrue(EventSquadView.needsRaidRows(mode: .best, shown: plain, current: nil), "Best always")
    }

    /// J1: the builder the view makes never ranks. With no rows it lists none and the ranking is not entered; the default (tests, background callers) still ranks on the spot.
    func testABuilderThatMayNotRankOnTheSpotListsNoRowsAndDoesNotRank() throws {
        let c = ctx()
        let row = try XCTUnwrap(Self.hub.rotation.first { $0.kind == .fiveStar && $0.bosses.contains { $0.speciesId == "palkia" } })
        final class Counter: @unchecked Sendable { private let lock = NSLock(); private var n = 0; func hit() { lock.lock(); n += 1; lock.unlock() }; var count: Int { lock.lock(); defer { lock.unlock() }; return n } }
        let counter = Counter()
        var b = EventPickerBuilder(screen: .raids, row: row, ctx: c)
        b.rank = { r, context in counter.hit(); return HubSquads.bestRaidRows(row: r, ctx: context) }
        b.rowsOnTheSpot = false
        XCTAssertTrue(b.bestRows().isEmpty)
        XCTAssertTrue(b.resolve(slots: HubSquads.defaultRaidSlots(), mode: .best).options.isEmpty)
        XCTAssertEqual(b.reference(style: .balanced).compactMap { $0 }.count, 0, "and the strength reference works nothing out")
        XCTAssertEqual(counter.count, 0, "the ranking was never called")
        b.rowsOnTheSpot = true
        XCTAssertFalse(b.bestRows().isEmpty, "a builder that may rank still does")
        XCTAssertEqual(counter.count, 1)
        // Max has a table, not a ranking: the flag does not touch it.
        var max = EventPickerBuilder(screen: .max, row: row, ctx: c)
        max.rowsOnTheSpot = false
        XCTAssertEqual(max.bestRows().count, EventPickerBuilder(screen: .max, row: row, ctx: c).bestRows().count)
    }

    /// J2: a tap that waits for the Best rows can tell the box moved: the keeper's generation changes with the box, and the ranking finished for the old box is not stored.
    @MainActor
    func testABoxChangeDuringARankingMovesTheGenerationAndTheOldResultIsNotStored() async throws {
        let row = try XCTUnwrap(Self.hub.rotation.first { !$0.bosses.isEmpty })
        let c = ctx(today: row.from)
        let keeper = SquadKeeper()
        let before = keeper.boxGeneration
        let key = keeper.raidRowsKey(row, style: .balanced, today: c.today)
        keeper.computeRaidRows = { _, _ in
            // The box changes while the ranking is being worked out (the main actor is free: the caller is suspended).
            DispatchQueue.main.sync { MainActor.assumeIsolated { keeper.boxChanged() } }
            return []
        }
        _ = await keeper.raidRowsNow(row, style: .balanced, ctx: c)
        XCTAssertNotEqual(keeper.boxGeneration, before, "the caller sees that the box moved")
        XCTAssertNil(keeper.cachedRaidRows(key), "the result for the old box is not stored")
        XCTAssertNil(keeper.cachedRaidRows(keeper.raidRowsKey(row, style: .balanced, today: c.today)))
    }

    /// H3: the name a store remembers, and a history disc shows, is the build of the screen's own area, so a disc's letter matches the slot card.
    func testARememberedNameTakesTheBuildOfTheScreensOwnArea() throws {
        let c = ctx()
        let b = try XCTUnwrap(c.advice.builds.first { $0.areas.contains("Raids") })
        var gym = b; gym.targetName = "Gym Target"; gym.areas = ["Gym"]
        var raids = b; raids.targetName = "Raids Target"; raids.areas = ["Raids"]
        let builds = [gym, raids]
        XCTAssertEqual(squadPickNames(entries: c.entries, builds: builds, screen: .raids)[b.entryId], "Raids Target")
        XCTAssertEqual(squadPickNames(entries: c.entries, builds: builds, screen: .gym)[b.entryId], "Gym Target")
        XCTAssertEqual(squadPickName(b.entryId, entries: c.entries, builds: builds, screen: .raids), "Raids Target")
        let title = try XCTUnwrap(c.entry(b.entryId)).row.title
        XCTAssertEqual(squadPickNames(entries: c.entries, builds: [gym], screen: .max)[b.entryId], SquadWords.boxName(title), "no build of the area: the box title")
        XCTAssertNil(squadPickName("not-in-the-box", entries: c.entries, builds: builds, screen: .raids))
    }

    /// J4: a copy's remembered name is per screen. Attaching Raids and then Gym keeps both names, and each screen reads its own (a departed copy's history disc included).
    @MainActor
    func testARememberedNameIsKeptPerScreen() throws {
        let c = ctx()
        let row = try XCTUnwrap(Self.hub.rotation.first { $0.kind == .fiveStar })
        let b = try XCTUnwrap(c.advice.builds.first { $0.areas.contains("Raids") })
        var gym = b; gym.targetName = "Gym Target"; gym.areas = ["Gym"]
        var raids = b; raids.targetName = "Raids Target"; raids.areas = ["Raids"]
        let builds = [gym, raids]
        let account = "Picker Row Test Names"
        defer { UserDefaults.standard.removeObject(forKey: SquadKeeper.key(account)) }
        let ids = Set(c.entries.map(\.id))
        let keeper = SquadKeeper()
        func attach(_ screen: SquadScreen) {
            keeper.attach(account: account, today: row.from, rotation: [row], boxIds: ids, names: squadPickNames(entries: c.entries, builds: builds, screen: screen), screen: screen)
        }
        attach(.raids)
        keeper.update { s in
            var r = s.eventSquad(row, screen: .raids); r.choose(b.entryId, at: 0); r.isSet = true; s.saveEventSquad(r, row: row, screen: .raids)
            s.gym.choose(b.entryId, at: 0)
        }
        attach(.raids)
        attach(.gym)
        XCTAssertEqual(keeper.store.pickName(for: b.entryId, area: "raids"), SquadWords.boxName("Raids Target"), "opening Gym did not replace the Raids name")
        XCTAssertEqual(keeper.store.pickName(for: b.entryId, area: "gym"), SquadWords.boxName("Gym Target"))
        // The copy leaves the box: each screen's history disc names it as that screen did.
        XCTAssertEqual(keeper.store.pickNames.count, 2)
        let back = SquadKeeper.load(account)
        XCTAssertEqual(back.pickName(for: b.entryId, area: "raids"), SquadWords.boxName("Raids Target"))
        XCTAssertEqual(back.pickName(for: b.entryId, area: "gym"), SquadWords.boxName("Gym Target"))
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
        // (Slice 1 ranks by species from the game master, which names a Mega "Rayquaza (Mega)", a Primal "Groudon (Primal)"; the rows write them in front, "Mega Rayquaza" (H3).)
        func isMega(_ name: String) -> Bool { name.hasPrefix("Mega ") || name.hasSuffix("(Mega)") || name.hasSuffix("(Mega X)") || name.hasSuffix("(Mega Y)") }
        func isMegaOrPrimal(_ name: String) -> Bool { isMega(name) || name.hasPrefix("Primal ") || name.hasSuffix("(Primal)") }
        let megaRows = rows.filter { isMega($0.name) && $0.cpIv != nil }
        let m = try XCTUnwrap(megaRows.first, "the real box has an owned Mega row under Best")
        let o = try XCTUnwrap(options.first(where: { $0.id == m.id }))
        let build = try XCTUnwrap(o.build)
        let scale = try XCTUnwrap(b.strengthScale())
        let plain = scale.strength(.init(copy: c.entry(build.entryId), build: build, built: m.mark == .fullStrength, megaSlot: false))
        XCTAssertEqual(m.strength, plain, "a Mega row in an All slot is judged on the plain form")
        // A Mega or Primal entry the box lacks is judged as the plain Pokémon outside the Mega slot too, and as the Mega form in it.
        let lackingForms = rows.filter { isMegaOrPrimal($0.name) && $0.cpIv == nil }
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
            .filter { isMegaOrPrimal($0.name) && $0.cpIv == nil }
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

    /// The squad's bar is built from the figures its slots' Pokémon show as rows in their pickers (over the Best squad's), on every screen, in both modes; the squad measure is printed.
    func testSquadStrengthIsBuiltFromTheSlotsPickerRowFigures() throws {
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
                timed(screen == .raids ? "raids" : "max") { fast = b.squadStrength(filled: filled, options: options, byId: byId, mode: mode, reference: b.reference(style: .balanced)) }
                let slow = SquadStrength.against(figures: figures(filled, rows: { b.content(slot: $0, filled: filled, options: options, byId: byId, mode: mode).rows }, empty: Strength(kind: .damage, now: nil, after: nil)), reference: b.reference(style: .balanced))
                same(fast!, slow, "\(screen) \(row.title) \(mode)")
            }
            let g = GymPickerBuilder(ctx: c)
            let r = g.resolve(mode: mode, saved: SquadStore.Saved(slots: HubSquads.defaultGymSlots()))
            let gById = Dictionary(r.options.flatMap { o in [(o.id, o)] + (o.best.map { [(squadSpeciesPrefix + $0.key, o)] } ?? []) }, uniquingKeysWith: { a, _ in a })
            var gFast: SquadStrength?
            timed("gym") { gFast = g.squadStrength(filled: r.filled, options: r.options, byId: gById, mode: mode) }
            same(gFast!, SquadStrength.against(figures: figures(r.filled, rows: { g.content(slot: $0, filled: r.filled, options: r.options, byId: gById, mode: mode).rows }, empty: Strength(kind: .bulk, now: nil, after: nil)), reference: g.reference(), kind: .bulk), "gym \(mode)")
            for leader in Self.hub.leaders {
                let k = RocketPickerBuilder(leader: leader, ctx: c)
                let filled = mode == .best ? HubSquads.bestRocketSquad(leader: leader, ctx: c) : HubSquads.rocketSquad(leader: leader, mode: mode, ctx: c)
                let lists = leader.slots.map { k.entries(for: $0, mode: mode) }
                var kFast: SquadStrength?
                timed("rocket") { kFast = k.squadStrength(filled: filled, lists: lists, mode: mode) }
                same(kFast!, SquadStrength.against(figures: figures(filled, rows: { k.content(slot: $0, filled: filled, lists: lists, mode: mode).rows }, empty: Strength(kind: .damage, now: nil, after: nil)), reference: k.reference()), "rocket \(leader.name) \(mode)")
            }
            for league in LeaguePanel.keys {
                let p = PvPPickerBuilder(league: league, ctx: c, pogoAssist: false)
                let r = p.resolve(mode: mode, slots: HubSquads.defaultPvpSlots())
                var pFast: SquadStrength?
                timed("pvp") { pFast = p.squadStrength(filled: r.filled, candidates: r.candidates, byId: r.byId, best: r.best, mode: mode) }
                same(pFast!, SquadStrength.against(figures: figures(r.filled, rows: { p.content(slot: $0, filled: r.filled, candidates: r.candidates, byId: r.byId, best: r.best, mode: mode).rows }, empty: Strength.scoreNotKnown), reference: p.reference(), kind: .score), "pvp \(league) \(mode)")
            }
        }
        XCTAssertGreaterThan(checked, 20)
        print("P2-5-TIMING squad strength, summed over every event, leader and league in both modes (ms): " + times.sorted { $0.key < $1.key }.map { "\($0.key) \(String(format: "%.0f", $0.value)) over \(counts[$0.key] ?? 0) squads" }.joined(separator: ", "))
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
        print("P2-5-TIMING Gym squad strength: \(String(format: "%.0f", ms)) ms, \(s.text), \(s.scoredText ?? "all scored")")
        XCTAssertLessThan(ms, 150)
    }

    /// Rule 27 through the Gym builder: the suggestion is kept at the first change; a box change or a mode switch back and forth then moves nothing; Delete current squad restores it.
    func testGymSuggestionIsKeptAtTheFirstChangeAndDeleteCurrentRestoresIt() throws {
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
        XCTAssertTrue(saved.hasCurrent)
        // Delete current squad: the squad keeps nothing and the suggestion returns.
        var store = SquadStore()
        store.setCurrent(saved, .gym)
        store.deleteCurrent(.gym)
        XCTAssertNil(store.current(.gym))
        XCTAssertEqual(g.resolve(mode: .best, saved: store.gym).filled.map(\.pickId), first.map(\.pickId))
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

    /// Sol 1: a slot that refills in a changed squad is kept, so a later change of the box does not move it. (The engine-only version is
    /// `SquadFixingTests.testARefillInAChangedSquadIsKeptSoALaterBoxChangeDoesNotMoveIt`.)
    func testARefilledSlotIsKeptAcrossALaterBoxChange() throws {
        let c = ctx()
        let g = GymPickerBuilder(ctx: c)
        var saved = SquadStore.Saved(slots: HubSquads.defaultGymSlots())
        let first = g.resolve(mode: .best, saved: saved).filled
        saved.choose(try XCTUnwrap(first[2].pickId), at: 0, shown: first)
        var store = SquadStore(); store.gym = saved
        store.gym.slots[3].pick = "gone-from-box"
        let reconciled = store.reconciled(boxIds: Set(c.entries.map(\.id))).gym
        let drawn = g.resolve(mode: .best, saved: reconciled).filled
        XCTAssertNotNil(drawn[3].pickId, "the slot refills")
        XCTAssertTrue(reconciled.needsAdopting(drawn))
        var adopted = reconciled; adopted.adoptRefills(drawn)
        // The box changes later: another copy leaves it and the advice is re-read from the smaller box, so the ranking can differ.
        let kept = Set(adopted.slots.compactMap(\.pick))
        let leaving = try XCTUnwrap(c.entries.first { !kept.contains($0.id) })
        let smaller = HubContext(advice: c.advice, entries: c.entries.filter { $0.id != leaving.id }, gm: c.gm, hub: c.hub, table: c.table, today: c.today)
        let later = GymPickerBuilder(ctx: smaller).resolve(mode: .best, saved: adopted).filled
        XCTAssertEqual(later[3].pickId, drawn[3].pickId, "the refilled slot did not move")
        XCTAssertEqual(later.map(\.pickId), drawn.map(\.pickId))
        // An unkept refill (the squad never adopted it) is the contrast: it follows the box.
        XCTAssertNotNil(GymPickerBuilder(ctx: smaller).resolve(mode: .best, saved: reconciled).filled[3].pickId)
    }

    /// A mode switch Best -> Available -> Best, then an edit: the edit acts on what is shown under the mode being edited.
    func testEditingAfterAModeSwitchActsOnWhatIsShown() throws {
        let c = ctx()
        let g = GymPickerBuilder(ctx: c)
        var saved = SquadStore.Saved(slots: HubSquads.defaultGymSlots())
        let best = g.resolve(mode: .best, saved: saved)
        let notOwned = try XCTUnwrap(best.filled.first { $0.species != nil }, "Best shows a Pokémon the box lacks")
        saved.choose(notOwned.pickId, at: 0, shown: best.filled)
        // Best -> Available: that pick is not placed there, so the slot shows Available's suggestion.
        let avail = g.resolve(mode: .available, saved: saved)
        XCTAssertNotEqual(avail.filled[0].pickId, notOwned.pickId)
        // Available -> Best: the pick returns, nothing was lost by looking.
        let backInBest = g.resolve(mode: .best, saved: saved)
        // (Choosing it for slot 1 swapped it with the slot that showed it, so those two exchanged.)
        var swappedAtOnce = best.filled.map(\.pickId)
        let from = try XCTUnwrap(swappedAtOnce.firstIndex { $0 == notOwned.pickId })
        swappedAtOnce.swapAt(0, from)
        XCTAssertEqual(backInBest.filled.map(\.pickId), swappedAtOnce)
        // Edit under Best: slot 2 takes slot 1's Pokémon (a swap of the two shown): both exchange, the rest stay.
        let shown = backInBest.filled
        saved.choose(shown[0].pickId, at: 1, alsoClearing: [], shown: shown)
        let after = g.resolve(mode: .best, saved: saved).filled.map(\.pickId)
        var expected = shown.map(\.pickId); expected[1] = shown[0].pickId; expected[0] = shown[1].pickId
        XCTAssertEqual(after, expected, "the swap exchanged what Best showed, and no Best pick resurfaced or was lost")
        // The same edit made under Available acts on what Available shows (the unplaced Best pick is replaced by it).
        var other = SquadStore.Saved(slots: saved.slots, isSet: false, changed: true)
        let shownAvailable = g.resolve(mode: .available, saved: other).filled
        let target = try XCTUnwrap(shownAvailable.compactMap(\.pickId).first)
        other.choose(target, at: 5, shown: shownAvailable)
        XCTAssertEqual(Set(other.slots.compactMap(\.pickId)).count, other.slots.compactMap(\.pickId).count, "no Pokémon twice")
    }

    /// G7: a kept suggestion's "listed for <role>" marker survives the species pick reading as a copy.
    func testResolvingASpeciesPickKeepsTheFallbackMarker() throws {
        let c = ctx()
        let row = try XCTUnwrap(Self.hub.rotation.first { $0.kind == .fiveStar && $0.bosses.contains { $0.speciesId == "palkia" } })
        let rows = HubSquads.bestRaidRows(row: row, ctx: c)
        let owned = try XCTUnwrap(rows.first { $0.ownedEntryId != nil })
        let out = HubSquads.resolvingSpecies([SquadSlot(role: "Heavy hitter", species: owned.key, fallback: true)], rows: rows)
        XCTAssertEqual(out[0].fallback, true)
        XCTAssertEqual(out[0].pick, owned.ownedEntryId)
    }

    /// Sol 3 and fold 2 G1: Rocket lists the other slots' Pokémon even when they do not beat this slot, and each such row SAYS what the slot being edited needs: its type flags,
    /// "beats n of 3" line and spoken "hits this slot" are worked out against that slot's lineup, as a native row's are.
    func testRocketListsEveryOtherSlotsPokemonDescribedForTheSlotBeingEdited() throws {
        let c = ctx()
        var checked = 0
        for leader in Self.hub.leaders {
            let k = RocketPickerBuilder(leader: leader, ctx: c)
            for mode in [SquadMode.available, .best] {
                let filled = mode == .best ? HubSquads.bestRocketSquad(leader: leader, ctx: c) : HubSquads.rocketSquad(leader: leader, mode: mode, ctx: c)
                let lists = leader.slots.map { k.entries(for: $0, mode: mode) }
                for i in filled.indices {
                    let slot = leader.slots[i]
                    let rows = k.content(slot: i, filled: filled, lists: lists, mode: mode).rows
                    for (j, f) in filled.enumerated() where j != i {
                        guard let id = f.pickId else { continue }
                        let row = try XCTUnwrap(rows.first { $0.id == id }, "\(leader.name) \(mode): slot \(j + 1)'s Pokémon is listed in slot \(i + 1)'s picker")
                        XCTAssertEqual(row.swapSlot, j + 1)
                    }
                    // Every row that draws type flags draws them against THIS slot, and says "hits this slot" exactly when one hits.
                    for row in rows where !row.types.isEmpty && row.cpIv != nil || row.swapSlot != nil && !row.types.isEmpty {
                        for t in row.types { XCTAssertEqual(t.grey, !slot.contains { c.hub.beats([t.type], $0.types) }, "\(leader.name) slot \(i + 1) \(row.name) \(t.type)") }
                        let hitting = row.types.filter { !$0.grey }
                        XCTAssertEqual(row.spoken.contains("hits this slot"), !hitting.isEmpty, "\(row.name): \(row.spoken)")
                        checked += 1
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 30)
    }

    /// G1, the named cases: Giovanni under Available, Lucario offered in the Zekrom slot does not claim Fighting hits it, and Rayquaza offered in slot 1 does not claim Flying hits it.
    func testRocketOtherSlotRowsDoNotClaimATypeThatDoesNotHit() throws {
        let c = ctx()
        let leader = try XCTUnwrap(Self.hub.leaders.first { $0.name == "Giovanni" })
        let k = RocketPickerBuilder(leader: leader, ctx: c)
        let filled = HubSquads.rocketSquad(leader: leader, mode: .available, ctx: c)
        let lists = leader.slots.map { k.entries(for: $0, mode: .available) }
        func rowsOf(_ name: String, in i: Int) -> [PickerRowModel] { k.content(slot: i, filled: filled, lists: lists, mode: .available).rows.filter { $0.name.contains(name) && $0.swapSlot != nil } }
        var seen = 0
        for (i, slot) in leader.slots.enumerated() {
            for (name, type) in [("Lucario", "fighting"), ("Rayquaza", "flying")] {
                for r in rowsOf(name, in: i) {
                    let hits = slot.contains { c.hub.beats([type], $0.types) }
                    if let t = r.types.first(where: { $0.type == type }) { XCTAssertEqual(!t.grey, hits, "\(name) in slot \(i + 1): \(type)") }
                    if !hits && r.types.allSatisfy({ $0.grey }) { XCTAssertFalse(r.spoken.contains("hits this slot"), r.spoken) }
                    seen += 1
                }
            }
        }
        XCTAssertGreaterThan(seen, 0, "Giovanni's Available squad offers Lucario or Rayquaza across slots")
    }

    /// G2: a kept Pokémon that no slot's counter list holds (a copy kept under the other mode) is still offered in the other slots' pickers, marked.
    func testRocketOffersAKeptPokemonNoCounterListHolds() throws {
        let c = ctx()
        let leader = try XCTUnwrap(Self.hub.leaders.first { $0.name == "Giovanni" })
        let k = RocketPickerBuilder(leader: leader, ctx: c)
        let lists = leader.slots.map { k.entries(for: $0, mode: .best) }
        let listed = Set(lists.flatMap { $0.rows + $0.next }.flatMap { [$0.id] + ($0.best?.ids ?? []) })
        let stray = try XCTUnwrap(c.entries.first { !listed.contains($0.id) }, "a copy in no counter list")
        var saved = SquadStore.Saved(slots: HubSquads.defaultRocketSlots())
        saved.choose(stray.id, at: 2, shown: HubSquads.bestRocketSquad(leader: leader, ctx: c))
        let filled = HubSquads.bestRocketSquad(leader: leader, slots: saved.slots, ctx: c)
        XCTAssertEqual(filled[2].pickId, stray.id)
        let rows = k.content(slot: 0, filled: filled, lists: lists, mode: .best).rows
        XCTAssertEqual(rows.first { $0.id == stray.id }?.swapSlot, 3, "slot 3's kept Pokémon is offered in slot 1")
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
            let slow = SquadStrength.against(figures: figures(r.filled, rows: { g.content(slot: $0, filled: r.filled, options: r.options, byId: byId, mode: mode).rows }, empty: Strength(kind: .bulk, now: nil, after: nil)), reference: g.reference(), kind: .bulk)
            XCTAssertEqual(fast, slow, "\(mode)")
        }
        let r = g.resolve(mode: .best, saved: saved)
        XCTAssertEqual(r.filled[0].pickId, species)
        XCTAssertEqual(r.filled[1].pickId, unlisted)
        let byId = Dictionary(r.options.flatMap { o in [(o.id, o)] + (o.best.map { [(squadSpeciesPrefix + $0.key, o)] } ?? []) }, uniquingKeysWith: { a, _ in a })
        let rows1 = g.content(slot: 1, filled: r.filled, options: r.options, byId: byId, mode: .best).rows
        XCTAssertNotNil(rows1.first(where: \.ticked)?.strength, "the unlisted copy has a figure from its own row")
    }

    // MARK: pass 2-5

    /// Rule 33: Max damage is a Mega and five Heavy hitters; Balanced is today's squad. Both are made of the slots' roles alone, and the five Heavy hitter slots fill on the real box.
    func testMaxDamageStyleMakesFiveHeavyHitterSlots() throws {
        let c = ctx()
        let row = try XCTUnwrap(Self.hub.rotation.first { [.fiveStar, .mega, .shadow].contains($0.kind) && $0.bosses.contains { $0.speciesId.hasPrefix("giratina") } })
        let b = EventPickerBuilder(screen: .raids, row: row, ctx: c)
        for mode in [SquadMode.available, .best] {
            let max = b.resolve(slots: HubSquads.defaultRaidSlots(style: .maxDamage), mode: mode).filled
            XCTAssertEqual(max.map(\.role), ["Mega"] + Array(repeating: "Heavy hitter", count: 5), "\(mode)")
            XCTAssertEqual(max.filter { $0.role == "Heavy hitter" && $0.pickId != nil }.count, 5, "\(mode): all five Heavy hitter slots are filled (other roles' listed counters fill in when heavy hitters run out)")
            let balanced = b.resolve(slots: HubSquads.defaultRaidSlots(style: .balanced), mode: mode).filled
            XCTAssertEqual(balanced.map(\.role), ["Mega", "Heavy hitter", "Heavy hitter", "Heavy hitter", "Bulky hitter", "Bulky hitter"], "\(mode)")
            XCTAssertNotEqual(max.map(\.pickId), balanced.map(\.pickId), "\(mode): the style changes the suggestion")
            // The reference follows the style: six figures, each a share of the best in the game.
            let reference = b.reference(style: .maxDamage)
            XCTAssertEqual(reference.count, 6)
            XCTAssertTrue(reference.compactMap { $0 }.allSatisfy { (0...1).contains($0) })
        }
    }

    /// Rule 27.4: Current is drawn as kept. A species pick the box lacks, kept from Best, is not hidden by Available's placement rule: it is drawn as its Best row, and no picker offers
    /// that row. Drawn as Available (a draft), the same pick is not placed.
    func testCurrentDrawsAKeptSpeciesPickAsItsBestRow() throws {
        let c = ctx()
        let row = try XCTUnwrap(Self.hub.rotation.first { [.fiveStar, .mega, .shadow].contains($0.kind) && $0.bosses.contains { $0.speciesId.hasPrefix("giratina") } })
        let plain = EventPickerBuilder(screen: .raids, row: row, ctx: c)
        let rows = HubSquads.bestRaidRows(row: row, ctx: c)
        let lacking = try XCTUnwrap(rows.first { !$0.inBox && $0.roles.contains("Heavy hitter") }, "the table lists a Heavy hitter the box lacks")
        var slots = HubSquads.defaultRaidSlots()
        slots[1].species = lacking.key
        let asAvailable = plain.resolve(slots: slots, mode: .available)
        XCTAssertNotEqual(asAvailable.filled[1].species, lacking.key, "Available places only what the box has")
        var kept = plain; kept.kept = true
        let asCurrent = kept.resolve(slots: slots, mode: .available)
        XCTAssertEqual(asCurrent.filled[1].species, lacking.key, "Current is drawn as kept")
        let extra = try XCTUnwrap(asCurrent.options.first { $0.extra })
        XCTAssertEqual(extra.best?.key, lacking.key)
        let byId = Dictionary(asCurrent.options.flatMap { o in [(o.entryId, o)] + (o.best.map { [(squadSpeciesPrefix + $0.key, o)] } ?? []) }, uniquingKeysWith: { a, _ in a })
        XCTAssertNotNil(byId[squadSpeciesPrefix + lacking.key], "so the slot can be drawn as the Best row it is")
        for i in asCurrent.filled.indices {
            let listed = kept.content(slot: i, filled: asCurrent.filled, options: asCurrent.options, byId: byId, mode: .available).rows
            XCTAssertEqual(listed.filter { $0.id == extra.id }.count, i == 1 ? 1 : 0, "slot \(i + 1): the kept row appears only as the slot's own, ticked row")
            if i == 1 { XCTAssertTrue(try XCTUnwrap(listed.first { $0.id == extra.id }).ticked) }
        }
        // Its strength is a figure like any not-owned row's.
        let strength = kept.squadStrength(filled: asCurrent.filled, options: asCurrent.options, byId: byId, mode: .available, reference: kept.reference(style: .balanced))
        XCTAssertNotNil(strength.now)
        XCTAssertLessThanOrEqual(strength.now ?? 2, 1)
    }

    /// Rule 32: a squad is measured against the Best squad's full-build figures. The Best squad's own slots, each taken at its full build, equal the reference by definition; a squad of
    /// nothing reads 0%; no screen's value ever passes 100%.
    func testStrengthIsMeasuredAgainstTheBestSquad() throws {
        let c = ctx()
        let row = try XCTUnwrap(Self.hub.rotation.first { [.fiveStar, .mega, .shadow].contains($0.kind) && $0.bosses.contains { $0.speciesId.hasPrefix("giratina") } })
        let b = EventPickerBuilder(screen: .raids, row: row, ctx: c)
        let reference = b.reference(style: .balanced)
        XCTAssertEqual(reference.count, 6)
        XCTAssertTrue(reference.allSatisfy { $0 != nil && $0! > 0 }, "the Best squad's six slots each have a figure: \(reference)")
        let empty = SquadStrength.against(figures: Array(repeating: nil, count: 6), reference: reference)
        XCTAssertEqual(empty.now, 0)
        // The squad drawn from the table with every slot at the reference figure matches it exactly.
        let atReference = SquadStrength.against(figures: reference.map { Strength(kind: .damage, now: $0, after: nil) }, reference: reference)
        XCTAssertTrue(atReference.matchesBest)
        XCTAssertEqual(atReference.text, "Squad strength 100%")
        for mode in [SquadMode.available, .best] {
            let (options, filled) = b.resolve(slots: HubSquads.defaultRaidSlots(), mode: mode)
            let byId = Dictionary(options.flatMap { o in [(o.entryId, o)] + (o.best.map { [(squadSpeciesPrefix + $0.key, o)] } ?? []) }, uniquingKeysWith: { a, _ in a })
            let s = b.squadStrength(filled: filled, options: options, byId: byId, mode: mode, reference: reference)
            XCTAssertLessThanOrEqual(s.now ?? 0, 1, "\(mode)")
            XCTAssertLessThanOrEqual(s.after ?? 0, 1, "\(mode)")
            XCTAssertTrue(s.text.hasSuffix("of best") || s.matchesBest, "\(mode): \(s.text)")
        }
    }

    /// Rule 27.4 on Gym, Rocket and PvP: Current is drawn as kept. A species pick the box lacks is placed, shown as its Best row with its own ticked picker row and a strength figure;
    /// drawn as Available (a draft) the same pick is not placed.
    func testCurrentDrawsAKeptSpeciesPickOnGymRocketAndPvP() throws {
        let c = ctx()
        // Gym.
        let gym = GymPickerBuilder(ctx: c)
        let gymRow = try XCTUnwrap(HubSquads.bestGymRows(ctx: c).first { !$0.inBox })
        var gSaved = SquadStore.Saved(slots: HubSquads.defaultGymSlots())
        gSaved.slots[1].species = gymRow.key
        XCTAssertNotEqual(gym.resolve(mode: .available, saved: gSaved).filled[1].species, gymRow.key, "Available does not place a species pick")
        var gymKept = gym; gymKept.kept = true
        let g = gymKept.resolve(mode: .available, saved: gSaved)
        XCTAssertEqual(g.filled[1].species, gymRow.key)
        XCTAssertTrue(g.options.contains { $0.extra && $0.best?.key == gymRow.key })
        let gById = Dictionary(g.options.flatMap { o in [(o.id, o)] + (o.best.map { [(squadSpeciesPrefix + $0.key, o)] } ?? []) }, uniquingKeysWith: { a, _ in a })
        for i in g.filled.indices {
            let rows = gymKept.content(slot: i, filled: g.filled, options: g.options, byId: gById, mode: .available).rows
            XCTAssertEqual(rows.filter { $0.id == gymRow.entryId }.count, i == 1 ? 1 : 0, "gym slot \(i + 1)")
        }
        let gStrength = gymKept.squadStrength(filled: g.filled, options: g.options, byId: gById, mode: .available)
        XCTAssertNotNil(gStrength.now)
        XCTAssertGreaterThanOrEqual(gStrength.scored, 1)

        // Rocket.
        let leader = try XCTUnwrap(Self.hub.leaders.first)
        var rocket = RocketPickerBuilder(leader: leader, ctx: c)
        let rRow = try XCTUnwrap(HubSquads.bestRocketRows(options: leader.slots[1], ctx: c).first { !$0.inBox })
        var rSlots = HubSquads.defaultRocketSlots()
        rSlots[1].species = rRow.key
        XCTAssertNotEqual(HubSquads.rocketSquad(leader: leader, slots: rSlots, mode: .available, ctx: c)[1].species, rRow.key)
        let rFilled = HubSquads.rocketSquad(leader: leader, slots: rSlots, mode: .available, kept: true, ctx: c)
        XCTAssertEqual(rFilled[1].species, rRow.key)
        rocket.kept = true
        let lists = leader.slots.map { rocket.entries(for: $0, mode: .available) }
        let ownRows = rocket.content(slot: 1, filled: rFilled, lists: lists, mode: .available).rows
        let ticked = try XCTUnwrap(ownRows.first(where: \.ticked), "the kept species pick is listed, ticked, in its own slot")
        XCTAssertEqual(ticked.id, rRow.entryId)
        XCTAssertNotNil(ticked.strength)
        XCTAssertNotNil(rocket.keptEntry(rFilled[1], slot: 1)?.best)
        XCTAssertNil(RocketPickerBuilder(leader: leader, ctx: c).keptEntry(rFilled[1], slot: 1), "a draft draws no kept entry")
        XCTAssertNotNil(rocket.squadStrength(filled: rFilled, lists: lists, mode: .available).now)

        // PvP, Master League (the box has no Great League candidates).
        var pvp = PvPPickerBuilder(league: "ml", ctx: c, pogoAssist: false)
        let pRow = try XCTUnwrap(HubSquads.bestPvpRows(league: "ml", ctx: c).first { !$0.inBox })
        var pSlots = HubSquads.defaultPvpSlots()
        pSlots[0].species = pRow.key
        XCTAssertNotEqual(pvp.resolve(mode: .available, slots: pSlots).filled[0].species, pRow.key)
        pvp.kept = true
        let p = pvp.resolve(mode: .available, slots: pSlots)
        XCTAssertEqual(p.filled[0].species, pRow.key)
        XCTAssertEqual(p.best.map(\.key), [pRow.key], "only the kept species' Best row is read under Current")
        let pRows = pvp.content(slot: 0, filled: p.filled, candidates: p.candidates, byId: p.byId, best: p.best, mode: .available).rows
        XCTAssertEqual(pRows.first(where: \.ticked)?.id, pRow.entryId)
        XCTAssertEqual(pRows.filter { $0.id == pRow.entryId }.count, 1)
        XCTAssertNotNil(pvp.squadStrength(filled: p.filled, candidates: p.candidates, byId: p.byId, best: p.best, mode: .available).now)
    }

    /// H3: a kept species pick and an owned copy of that species are the same Pokémon. While the pick holds the species, no other slot of the kept squad refills with that copy
    /// (Raids, Max, Gym and Rocket), so the squad never shows it twice and its strength never counts it twice.
    func testAKeptSpeciesPickHoldsItsOwnedCopyOnRaidsMaxGymAndRocket() throws {
        let c = ctx()
        // No other slot holds the copy, nor the species the pick holds.
        func others(_ filled: [FilledSlot], except i: Int, copy: String, species: String) -> Bool {
            filled.enumerated().allSatisfy { $0.offset == i || ($0.element.entryId != copy && $0.element.species != species) }
        }
        // Raids and Max: the first event of each kind.
        for screen in [SquadScreen.raids, .max] {
            let row = try XCTUnwrap(Self.hub.rotation.first { !$0.bosses.isEmpty && (screen == .raids ? [.fiveStar, .mega, .shadow] : [.maxMonday, .maxEvent]).contains($0.kind) })
            var b = EventPickerBuilder(screen: screen, row: row, ctx: c); b.kept = true
            let rows = screen == .raids ? HubSquads.bestRaidRows(row: row, ctx: c) : HubSquads.bestMaxRows(row: row, ctx: c)
            let owned = try XCTUnwrap(rows.first { $0.ownedEntryId != nil && !$0.roles.contains("Mega") }, "\(screen): the table lists a Pokémon the box has")
            var slots = screen == .raids ? HubSquads.defaultRaidSlots() : HubSquads.defaultMaxSlots()
            slots[1].species = owned.key
            let filled = b.resolve(slots: slots, mode: .available).filled
            XCTAssertEqual(filled[1].species, owned.key, "\(screen): the species pick is kept")
            XCTAssertTrue(others(filled, except: 1, copy: owned.ownedEntryId!, species: owned.key), "\(screen): no other slot refills with the copy the pick holds")
        }
        // Gym.
        var g = GymPickerBuilder(ctx: c); g.kept = true
        let gRow = try XCTUnwrap(HubSquads.bestGymRows(ctx: c).first { $0.ownedEntryId != nil })
        var gs = SquadStore.Saved(slots: HubSquads.defaultGymSlots()); gs.slots[2].species = gRow.key
        let gFilled = g.resolve(mode: .available, saved: gs).filled
        XCTAssertEqual(gFilled[2].species, gRow.key)
        XCTAssertTrue(others(gFilled, except: 2, copy: gRow.ownedEntryId!, species: gRow.key), "gym")
        // Rocket.
        for leader in Self.hub.leaders {
            var k = RocketPickerBuilder(leader: leader, ctx: c); k.kept = true
            guard let r = leader.slots.indices.lazy.compactMap({ i in HubSquads.bestRocketRows(options: leader.slots[i], ctx: c).first { $0.ownedEntryId != nil }.map { (i, $0) } }).first else { continue }
            var slots = HubSquads.defaultRocketSlots(); slots[r.0].species = r.1.key
            let filled = HubSquads.rocketSquad(leader: leader, slots: slots, mode: .available, kept: true, copyOf: k.keptCopyOf(slots: slots), ctx: c)
            XCTAssertEqual(filled[r.0].species, r.1.key, "rocket \(leader.name)")
            XCTAssertTrue(others(filled, except: r.0, copy: r.1.ownedEntryId!, species: r.1.key), "rocket \(leader.name)")
            return
        }
        XCTFail("no Rocket leader slot lists a Pokémon the box has")
    }

    /// J4: an unowned Best row that fills a slot from another role (Max damage under Best runs out of Heavy hitters) says so on its card, visibly and spoken, as an owned one does.
    func testAnUnownedBestFallbackRowSaysWhichRoleItIsListedFor() throws {
        let c = ctx()
        let row = try XCTUnwrap(Self.hub.rotation.first { [.fiveStar, .mega, .shadow].contains($0.kind) && $0.bosses.contains { $0.speciesId.hasPrefix("giratina") } })
        let b = EventPickerBuilder(screen: .raids, row: row, ctx: c)
        let (options, filled) = b.resolve(slots: HubSquads.defaultRaidSlots(style: .maxDamage), mode: .best)
        let byId = Dictionary(options.flatMap { o in [(o.entryId, o)] + (o.best.map { [(squadSpeciesPrefix + $0.key, o)] } ?? []) }, uniquingKeysWith: { a, _ in a })
        // The first slot that holds a Pokémon the box lacks, marked as a fallback (the test box may not run out of Heavy hitters by itself).
        let i = try XCTUnwrap(filled.indices.first { idx in filled[idx].role != "Mega" && (filled[idx].pickId.flatMap { byId[$0] }?.best.map { !$0.inBox } ?? false) })
        var f = filled[i]; f.fallback = true; f.chosen = false
        let card = b.card(i, f, byId: byId, count: filled.count, mode: .best)
        let line = SquadWords.otherRoleLine([b.roleWord(try XCTUnwrap(byId[f.pickId!]), role: f.role, mode: .best)])
        XCTAssertTrue(card.lines.contains(line), "visible: \(card.lines)")
        XCTAssertTrue(card.spoken.contains(line), "and spoken: \(card.spoken)")
        f.fallback = false; f.chosen = true
        XCTAssertFalse(b.card(i, f, byId: byId, count: filled.count, mode: .best).lines.contains(line), "a slot that took its own role's row says nothing")
    }

    /// J5: a kept species pick of a Pokémon the box owns fits a role through the copy that stands for it (Raids and PvP).
    func testAKeptSpeciesPickOfAnOwnedPokemonFitsItsRolesThroughItsCopy() throws {
        let c = ctx()
        // Raids.
        let row = try XCTUnwrap(Self.hub.rotation.first { [.fiveStar, .mega, .shadow].contains($0.kind) && $0.bosses.contains { $0.speciesId.hasPrefix("giratina") } })
        var b = EventPickerBuilder(screen: .raids, row: row, ctx: c); b.kept = true
        let owned = try XCTUnwrap(HubSquads.bestRaidRows(row: row, ctx: c).first { $0.ownedEntryId != nil && !$0.roles.contains("Mega") })
        var slots = HubSquads.defaultRaidSlots(); slots[1].species = owned.key
        let r = b.resolve(slots: slots, mode: .available)
        let rows = r.options.compactMap(\.best)
        let role = try XCTUnwrap(r.options.first { $0.best?.key == owned.key }?.roles.first)
        XCTAssertTrue(HubSquads.fitsThrough(squadSpeciesPrefix + owned.key, role: role, in: r.options, rows: rows), "the species id is read through its copy")
        XCTAssertFalse(HubSquads.fits(squadSpeciesPrefix + owned.key, role: role, in: r.options), "which the species id alone cannot be")
        XCTAssertFalse(HubSquads.fitsThrough(squadSpeciesPrefix + owned.key, role: "No such role", in: r.options, rows: rows))
        // PvP, the first league whose table lists a Pokémon the box owns.
        let box = c
        let owned2 = ["gl", "ul", "ml"].compactMap { l in HubSquads.bestPvpRows(league: l, ctx: c).first(where: { $0.inBox && !$0.roles.isEmpty }).map { (l, $0) } }.first
        let (league, pRow) = try XCTUnwrap(owned2, "the box has an owned Pokémon the PvP tables list for a role")
        var pvp = PvPPickerBuilder(league: league, ctx: box, pogoAssist: false)
        var pSlots = HubSquads.defaultPvpSlots(); pSlots[0].species = pRow.key
        pvp.kept = true
        let p = pvp.resolve(mode: .available, slots: pSlots)
        XCTAssertTrue(HubSquads.fitsThrough(squadSpeciesPrefix + pRow.key, role: pRow.roles[0], in: p.best, rows: p.best), "pvp: the owned species is listed for its role through its copy")
    }
}
