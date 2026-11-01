import XCTest
@testable import PogoBox
import PogoReader

/// Phone run 2, P1: the damage estimate behind the picker bars. Hand-computed figures use the bundled game master, move stats and CP multipliers.
final class DamageEstimateTests: XCTestCase {
    private static let pve = try! PveMoves.bundled()
    private static let giratina = P23.boss("giratina_origin", types: ["ghost", "dragon"])

    private func scale(_ mode: StrengthScale.Mode, boss: HubData.Boss = giratina, entries: [BoxEntry] = [], table: [TierTable.Entry] = [], builds: [BoxAdvice.Build] = []) -> StrengthScale {
        StrengthScale(mode: mode, bosses: [boss], ctx: P23.ctx(builds: builds, entries: entries, table: P23.table(table)), pve: Self.pve)
    }

    private func palkia(level: Double = 50, atkIV: Int = 15) -> StrengthScale.Attacker {
        StrengthScale.Attacker(speciesId: "palkia", base: BaseStats(atk: 280, def: 215, hp: 189), types: ["water", "dragon"], shadow: false, level: level, ivs: IVs(atk: atkIV, def: 15, hp: 15))
    }

    // MARK: hand-computed damage

    /// Raids. Palkia (base Attack 280) at level 50 with Attack IV 15 against Giratina (Origin) (base Defence 187, Ghost/Dragon).
    /// attack = (280 + 15) x 0.84029999 = 247.8885; defence = (187 + 15) x 0.7903 (level 40) = 159.6406; ratio 1.55285.
    /// Dragon is Palkia's type (x1.2) and Dragon hits Ghost for 1 and Dragon for 1.6: effectiveness 1.6.
    /// Dragon Breath (power 6, 500 ms, +4 energy): floor(0.5 x 6 x 1.55285 x 1.2 x 1.6) + 1 = floor(8.94) + 1 = 9.
    /// Draco Meteor (power 150, 3500 ms, -100 energy): floor(0.5 x 150 x 1.55285 x 1.2 x 1.6) + 1 = floor(223.6) + 1 = 224.
    /// n = ceil(100 / 4) = 25 fast moves, then the charged one: (25 x 9 + 224) / (25 x 500 + 3500) ms = 449 / 16 s = 28.0625 damage per second.
    func testRaidDpsAgainstGiratinaOrigin() {
        let s = scale(.raids)
        let v = s.value(palkia(), pick: .init(fast: "DRAGON_BREATH", charged: ["DRACO_METEOR"]))
        XCTAssertEqual(try XCTUnwrap(v), 28.0625, accuracy: 1e-9)
        XCTAssertEqual(DamageEstimate.damage(power: 6, attack: 247.88849705, defence: 159.6406, sameType: true, effectiveness: 1.6), 9)
        XCTAssertEqual(DamageEstimate.damage(power: 150, attack: 247.88849705, defence: 159.6406, sameType: true, effectiveness: 1.6), 224)
    }

    /// Max. One Max Attack from a Dragon fast move: power 250 (level 1), same type: floor(0.5 x 250 x 1.55285 x 1.2 x 1.6) + 1 = floor(372.7) + 1 = 373.
    func testMaxMoveDamageAgainstGiratinaOrigin() {
        let v = scale(.max).value(palkia(), pick: .init(fast: "DRAGON_BREATH"))
        XCTAssertEqual(try XCTUnwrap(v), 373, accuracy: 1e-9)
        // A Gigantamax copy uses the G-Max power (350): floor(0.5 x 350 x 1.55285 x 1.2 x 1.6) + 1 = floor(521.8) + 1 = 522.
        XCTAssertEqual(try XCTUnwrap(scale(.max).value(palkia(), gmaxType: "dragon")), 522, accuracy: 1e-9)
    }

    /// Rocket. PvP stats and the 1.3 bonus. Dragon Breath (power 3, +4 energy, 1 turn): floor(0.5 x 3 x 1.55285 x 1.2 x 1.6 x 1.3) + 1 = floor(5.81) + 1 = 6.
    /// Draco Meteor (power 150, 65 energy): floor(223.6 x 1.3) + 1 = floor(290.7) + 1 = 291. n = ceil(65 / 4) = 17: (17 x 6 + 291) / (17 + 1) = 393 / 18 = 21.8333 per turn.
    func testRocketDamagePerTurn() {
        let v = scale(.rocket).value(palkia(), pick: .init(fast: "DRAGON_BREATH", charged: ["DRACO_METEOR"]))
        XCTAssertEqual(try XCTUnwrap(v), 393.0 / 18.0, accuracy: 1e-9)
    }

    // MARK: the best in the game

    /// Ruling 1: a Mega or Primal is never a Shadow. Against Groudon (and others) a Shadow version of some Mega out-damages the real best, so the old code, which tried a
    /// Shadow of every Shadow-eligible entry, named it; the best must not be a Shadow Mega.
    func testTheBestInTheGameHasNoShadowMega() throws {
        var older = [String]()
        for boss in [P23.boss("groudon", types: ["ground"]), P23.boss("snorlax", types: ["normal"]), P23.boss("kyogre", types: ["water"]), Self.giratina] {
            let s = scale(.raids, boss: boss)
            let best = s.computeBest()
            XCTAssertFalse(best.shadow && (P23.gm.byId[best.who]?.tags.contains("mega") ?? false), "\(boss.speciesId): best \(best.who) shadow \(best.shadow)")
            for sp in P23.gm.ordered where DamageEstimate.eligible(sp, megas: true) && sp.tags.contains("mega") && sp.tags.contains("shadoweligible") {
                let a = StrengthScale.Attacker(speciesId: sp.id, base: sp.baseStats!, types: sp.types, shadow: true, level: 50, ivs: IVs(atk: 15, def: 15, hp: 15))
                if let v = s.value(a), v > best.value { older.append("\(boss.speciesId): \(sp.id)") }
                // A row's figure never gives a Mega form the Shadow multiplier either.
                XCTAssertFalse(try XCTUnwrap(s.attacker(sp.id, shadow: true, level: 50, ivs: IVs(atk: 15, def: 15, hp: 15))).shadow)
            }
        }
        XCTAssertFalse(older.isEmpty, "some Shadow Mega would have beaten the best: the old code's answer")
        print("P1-OLD-CODE would have named a Shadow Mega best against: \(older.prefix(6))")
    }

    /// Ruling 3: the Max best in the game covers only the sourced Dynamax-capable and Gigantamax species, and every id in the lists is in the game master.
    func testMaxBestInTheGameIsOverTheSourcedSpecies() throws {
        for id in MaxBattleSpecies.capable { XCTAssertNotNil(P23.gm.byId[id], "\(id) is in the game master") }
        XCTAssertTrue(Set(MaxBattleSpecies.gigantamax.keys).isSubset(of: MaxBattleSpecies.capable))
        XCTAssertEqual(MaxBattleSpecies.gigantamax.count, 17)
        let s = scale(.max)
        let best = s.computeBest()
        XCTAssertTrue(MaxBattleSpecies.capable.contains(best.who), best.who)
        // Mewtwo is not Dynamax-capable: even if it out-damaged everything, it is not on the Max scale.
        let m = P23.gm.byId["mewtwo"]!
        let mewtwo = StrengthScale.Attacker(speciesId: "mewtwo", base: m.baseStats!, types: m.types, shadow: false, level: 50, ivs: IVs(atk: 15, def: 15, hp: 15))
        XCTAssertNotEqual(best.who, "mewtwo")
        XCTAssertNotNil(s.value(mewtwo))
        XCTAssertGreaterThanOrEqual(best.value, try XCTUnwrap(s.value(gmaxAttacker("machamp"), gmaxType: "fighting")))
    }

    private func gmaxAttacker(_ id: String, level: Double = 50) -> StrengthScale.Attacker {
        let g = P23.gm.byId[id]!
        return StrengthScale.Attacker(speciesId: id, base: g.baseStats!, types: g.types, shadow: false, level: level, ivs: IVs(atk: 15, def: 15, hp: 15))
    }

    /// Ruling 3: a Gigantamax copy's Max Attack is its G-Max move (type from the list, power 350), not its fast move's type.
    func testAGigantamaxCopyUsesItsGMaxMove() throws {
        let boss = P23.boss("snorlax", types: ["normal"])
        var plain = P23.entry("a", "gengar", ivs: IVs(atk: 15, def: 15, hp: 15), level: 40)
        var giga = plain; giga.row.gigantamax = true; giga.row.dynamax = true
        plain.row.details = CopyDetails(fastMove: "LICK")   // a Ghost fast move: the Max Attack would be Ghost too, at 250
        giga.row.details = CopyDetails(fastMove: "SUCKER_PUNCH")   // a Dark fast move: the G-Max move is still Ghost, at 350
        let s = scale(.max, boss: boss)
        let g = try XCTUnwrap(s.strength(.init(copy: giga, build: nil, built: true)).now), p = try XCTUnwrap(s.strength(.init(copy: plain, build: nil, built: true)).now)
        XCTAssertEqual(g, try XCTUnwrap(s.value(gmaxAttacker("gengar", level: 40), gmaxType: "ghost")) / s.bestInGame, accuracy: 1e-12)
        XCTAssertGreaterThan(g, p, "350 against 250 base power")
    }

    /// Ruling 4: a Gigantamax Best row the box lacks is valued with its G-Max move: the same as an owned level 50, 15/15/15 Gigantamax copy.
    func testAGigantamaxBestRowTheBoxLacksEqualsAnOwnedMaxedCopy() throws {
        let s = scale(.max, boss: P23.boss("snorlax", types: ["normal"]))
        let lacking = s.strength(.init(copy: nil, build: nil, built: false, species: .init(speciesId: "machamp", shadow: false, moves: nil, gigantamax: true)))
        var owned = P23.entry("m", "machamp", ivs: IVs(atk: 15, def: 15, hp: 15), level: 50)
        owned.row.gigantamax = true
        let have = s.strength(.init(copy: owned, build: nil, built: true))
        XCTAssertEqual(try XCTUnwrap(lacking.now), try XCTUnwrap(have.now), accuracy: 1e-12)
        let notGiga = s.strength(.init(copy: nil, build: nil, built: false, species: .init(speciesId: "machamp", shadow: false, moves: nil)))
        XCTAssertNotEqual(notGiga.now, lacking.now)
    }

    func testTheKeyChangesWithWhatTheBestDependsOn() {
        let a = scale(.raids), b = scale(.rocket), c = scale(.raids, boss: P23.boss("groudon", types: ["ground"]))
        XCTAssertEqual(Set([a.key, b.key, c.key]).count, 3)
        let stronger = PveMoves(moves: Self.pve.moves, maxAttackPower: Self.pve.maxAttackPower, gmaxPower: Self.pve.gmaxPower + 100)
        let d = StrengthScale(mode: .raids, bosses: [Self.giratina], ctx: P23.ctx(), pve: stronger)
        XCTAssertNotEqual(a.key, d.key, "a change to the move stats is a different scale")
        XCTAssertTrue(StrengthScale.shared(mode: .raids, bosses: [Self.giratina], ctx: P23.ctx(), pve: Self.pve) === StrengthScale.shared(mode: .raids, bosses: [Self.giratina], ctx: P23.ctx(), pve: Self.pve))
    }

    // MARK: the mean over several bosses and over the Rocket slot's options

    func testTheFigureIsTheMeanOverTheBosses() throws {
        let other = P23.boss("groudon", types: ["ground"])
        let pick = DamageEstimate.Pick(fast: "DRAGON_BREATH", charged: ["DRACO_METEOR"])
        for mode in [StrengthScale.Mode.raids, .rocket] {
            let one = try XCTUnwrap(scale(mode).value(palkia(), pick: pick)), two = try XCTUnwrap(scale(mode, boss: other).value(palkia(), pick: pick))
            let both = try XCTUnwrap(StrengthScale(mode: mode, bosses: [Self.giratina, other], ctx: P23.ctx(), pve: Self.pve).value(palkia(), pick: pick))
            XCTAssertEqual(both, (one + two) / 2, accuracy: 1e-9, "\(mode)")
            XCTAssertNotEqual(one, two)
        }
    }

    // MARK: now and after

    func testAPowerUpOnlyBuildHasAfterAtLeastNow() throws {
        let copy = P23.entry("a", "palkia", ivs: IVs(atk: 12, def: 13, hp: 14), level: 30)
        let b = P23.build("a", "palkia", areas: ["Raids"], built: false, targetLevel: 40)
        let st = scale(.raids, entries: [copy]).strength(.init(copy: copy, build: b, built: false))
        let now = try XCTUnwrap(st.now), after = try XCTUnwrap(st.after)
        XCTAssertGreaterThanOrEqual(after, now)
        XCTAssertTrue(st.hasFaint)
        XCTAssertTrue((0...1).contains(after))
    }

    func testAFullStrengthRowHasNoFaintPart() throws {
        let copy = P23.entry("a", "palkia", level: 40)
        let st = scale(.raids, entries: [copy]).strength(.init(copy: copy, build: P23.build("a", "palkia", areas: ["Raids"], built: true), built: true))
        XCTAssertNotNil(st.now)
        XCTAssertNil(st.after)
        XCTAssertFalse(st.hasFaint)
    }

    func testMegaOnlyInTheMegaSlot() throws {
        let copy = P23.entry("a", "charizard", level: 40)
        let b = P23.build("a", "charizard", areas: ["Raids"], built: false, viaMega: true, targetLevel: 40, steps: [.init(kind: "megaEvolve")])
        let s = scale(.raids, entries: [copy])
        let inMegaSlot = s.strength(.init(copy: copy, build: b, built: false, megaSlot: true))
        let elsewhere = s.strength(.init(copy: copy, build: b, built: false, megaSlot: false))
        XCTAssertGreaterThan(try XCTUnwrap(inMegaSlot.after), try XCTUnwrap(elsewhere.after ?? elsewhere.now))
        XCTAssertNil(elsewhere.after, "outside the Mega slot the plain form is judged: no Mega gain to show")
        XCTAssertEqual(Set(s.megaSpecies(of: "charizard")), ["charizard_mega_x", "charizard_mega_y"])
    }

    func testACopyWithUnreadMovesUsesTheBuildsMoves() throws {
        let copy = P23.entry("a", "palkia", level: 40)
        let build = P23.build("a", "palkia", areas: ["Raids"], built: true)
        let table = [P23.tierEntry("raids", "Dragon", "A", "palkia", moves: "Dragon Breath / Hydro Pump")]
        let s = scale(.raids, entries: [copy], table: table)
        let fromBuild = s.strength(.init(copy: copy, build: build, built: true))
        let expected = s.value(StrengthScale.Attacker(speciesId: "palkia", base: BaseStats(atk: 280, def: 215, hp: 189), types: ["water", "dragon"], shadow: false, level: 40, ivs: IVs(atk: 10, def: 10, hp: 10)),
                               pick: .init(fast: "DRAGON_BREATH", charged: ["HYDRO_PUMP"])).map { $0 / s.bestInGame }
        XCTAssertEqual(try XCTUnwrap(fromBuild.now), try XCTUnwrap(expected), accuracy: 1e-9)
        // The copy's own moves, when read, win over the build's.
        var own = copy
        own.row.details = CopyDetails(fastMove: "DRAGON_TAIL", chargedMove: "DRACO_METEOR")
        let fromCopy = s.strength(.init(copy: own, build: build, built: true))
        XCTAssertNotEqual(fromCopy.now, fromBuild.now)
    }

    func testUnreadLevelLeavesOnlyTheFaintPartAndUnreadIVsLeaveNothing() throws {
        let b = P23.build("a", "palkia", areas: ["Raids"], built: false, targetLevel: 40)
        var noLevel = P23.entry("a", "palkia", level: nil)
        var st = scale(.raids, entries: [noLevel]).strength(.init(copy: noLevel, build: b, built: false))
        XCTAssertNil(st.now)
        XCTAssertNotNil(st.after)
        XCTAssertEqual(st.barSolid, 0)
        XCTAssertTrue(st.spoken!.hasPrefix("estimated damage now not read"))
        noLevel = P23.entry("a", "palkia", ivs: nil, level: 30)
        st = scale(.raids, entries: [noLevel]).strength(.init(copy: noLevel, build: b, built: false))
        XCTAssertTrue(st.isEmpty)
        XCTAssertEqual(st.spoken, "estimated damage not read")
    }

    func testAShadowCopyHits20PercentHarder() throws {
        let plain = P23.entry("a", "mewtwo", level: 40), shadow = P23.entry("b", "mewtwo", level: 40, shadow: 1)
        let s = scale(.raids, entries: [plain, shadow])
        let p = try XCTUnwrap(s.strength(.init(copy: plain, build: nil, built: true)).now), h = try XCTUnwrap(s.strength(.init(copy: shadow, build: nil, built: true)).now)
        XCTAssertGreaterThan(h, p)
    }

    func testAPokemonTheBoxLacksIsOneBarAtLevel50With15s() throws {
        let s = scale(.raids)
        let st = s.strength(.init(copy: nil, build: nil, built: false, species: .init(speciesId: "palkia", shadow: false, moves: nil)))
        XCTAssertTrue(st.assumed)
        XCTAssertNil(st.after)
        let v = try XCTUnwrap(s.value(palkia(atkIV: 15)))
        XCTAssertEqual(try XCTUnwrap(st.now), v / s.bestInGame, accuracy: 1e-9)
        XCTAssertTrue(st.spoken!.hasSuffix("at level 50 with 15, 15, 15"))
    }

    // MARK: moves, words, Gym and PvP

    // MARK: moves follow the boss (ruling 2)

    /// Rhyperior against Mega Charizard Y (Fire/Flying): the table gives it a Ground line (tier S) and a Rock line (tier B). Rock is double super effective here and
    /// Ground is not, so the figure after the build is the Rock line's, not the best tier's.
    func testTheMovesFollowTheBossNotTheBestTier() throws {
        let boss = P23.boss("charizard_mega_y", types: ["fire", "flying"])
        let table = [P23.tierEntry("raids", "Ground", "S", "rhyperior", moves: "Mud-Slap / Earthquake"), P23.tierEntry("raids", "Rock", "B", "rhyperior", moves: "Smack Down / Stone Edge")]
        let copy = P23.entry("r", "rhyperior", ivs: IVs(atk: 15, def: 15, hp: 15), level: 40)
        let build = P23.build("r", "rhyperior", areas: ["Raids"], built: false, targetLevel: 50)
        let s = scale(.raids, boss: boss, entries: [copy], table: table)
        let rhy = P23.gm.byId["rhyperior"]!
        func at(_ level: Double) -> StrengthScale.Attacker { StrengthScale.Attacker(speciesId: "rhyperior", base: rhy.baseStats!, types: rhy.types, shadow: false, level: level, ivs: IVs(atk: 15, def: 15, hp: 15)) }
        let ground = try XCTUnwrap(s.value(at(50), pick: .init(fast: "MUD_SLAP", charged: ["EARTHQUAKE"]))), rock = try XCTUnwrap(s.value(at(50), pick: .init(fast: "SMACK_DOWN", charged: ["STONE_EDGE"])))
        XCTAssertGreaterThan(rock, ground)
        let st = s.strength(.init(copy: copy, build: build, built: false))
        XCTAssertEqual(try XCTUnwrap(st.after), rock / s.bestInGame, accuracy: 1e-12)
        // Now is judged on the same lines for the copy as it is (level 40), so it is the Rock line too.
        XCTAssertEqual(try XCTUnwrap(st.now), try XCTUnwrap(s.value(at(40), pick: .init(fast: "SMACK_DOWN", charged: ["STONE_EDGE"]))) / s.bestInGame, accuracy: 1e-12)
    }

    /// A line the Pokemon cannot learn is skipped: Deino now cannot use Hydreigon's lines, so it is judged on its own best moves.
    func testALineThePokemonCannotLearnIsSkipped() throws {
        let copy = P23.entry("d", "deino", ivs: IVs(atk: 15, def: 15, hp: 15), level: 30)
        let table = [P23.tierEntry("raids", "Dark", "B", "hydreigon", moves: "Bite / Brutal Swing")]
        let build = P23.build("d", "hydreigon", areas: ["Raids"], built: false, targetLevel: 40)
        let s = scale(.raids, table: table)
        let st = s.strength(.init(copy: copy, build: build, built: false))
        let deino = P23.gm.byId["deino"]!
        let a = StrengthScale.Attacker(speciesId: "deino", base: deino.baseStats!, types: deino.types, shadow: false, level: 30, ivs: IVs(atk: 15, def: 15, hp: 15))
        XCTAssertEqual(try XCTUnwrap(st.now), try XCTUnwrap(s.value(a)) / s.bestInGame, accuracy: 1e-12)
    }

    // MARK: reading the table's move lines

    func testTheTablesMoveLinesReadAsMoveIds() {
        let gm = P23.gm
        XCTAssertEqual(DamageEstimate.parseLines("Shadow Claw / Shadow Force (Elite)", gm: gm).picks, [.init(fast: "SHADOW_CLAW", charged: ["SHADOW_FORCE"])])
        XCTAssertEqual(DamageEstimate.parseLines("Fire Spin / Mystical Fire+", gm: gm).picks, [.init(fast: "FIRE_SPIN", charged: ["MYSTICAL_FIRE"])])
        XCTAssertEqual(DamageEstimate.parseLines("Fire Spin or Wing Attack / Dragon Claw + Blast Burn", gm: gm).picks,
                       [.init(fast: "FIRE_SPIN", charged: ["DRAGON_CLAW", "BLAST_BURN"]), .init(fast: "WING_ATTACK", charged: ["DRAGON_CLAW", "BLAST_BURN"])])
        XCTAssertEqual(DamageEstimate.parseLines("Double Kick / Rock Slide; Counter / Dynamic Punch", gm: gm).picks.map(\.fast), ["DOUBLE_KICK", "COUNTER"])
        XCTAssertEqual(DamageEstimate.parseLines("Dragon Tail / Max Strike", gm: gm).picks, [.init(fast: "DRAGON_TAIL", charged: [])])
        let unreadable = DamageEstimate.parseLines("G-Max Wildfire / Stun Shock / Resonance", gm: gm)
        XCTAssertEqual(unreadable.picks, [])
        XCTAssertEqual(unreadable.unparsed, 1)
        XCTAssertEqual(DamageEstimate.parseLines(nil, gm: gm).picks, [])
    }

    /// Ruling 8: a name that two ids share resolves by rule (no _PLUS, then the shortest, then the first alphabetically), not by dictionary order.
    func testNameToIdIsDeterministic() {
        let names = DamageEstimate.moveIdsByName(P23.gm)
        for _ in 0..<5 { XCTAssertEqual(DamageEstimate.moveIdsByName(P23.gm), names) }
        XCTAssertEqual(names["auraWheel".lowercased()], "AURA_WHEEL_DARK")
        XCTAssertEqual(names["airslash"], "AIR_SLASH")
        XCTAssertEqual(names["surf"], "SURF")
        XCTAssertFalse(names.values.contains { $0.hasPrefix("AEGISLASH_CHARGE") && $0 != names["aegislashcharge"] } && names["airslash"]!.hasPrefix("AEGISLASH"))
    }

    /// How many lines of the real tables name no known move (they are skipped, never guessed).
    func testUnparsedLinesInTheRealTables() throws {
        let n = DamageEstimate.unparsedLineCount(table: try TierTable.bundled(), gm: P23.gm)
        print("P1-UNPARSED move lines in tiers.json: \(n)")
        XCTAssertLessThan(n, 60)
    }

    func testCpAndIvLine() {
        let e = P23.entry("a", "palkia", ivs: IVs(atk: 15, def: 14, hp: 15), cp: 3412)
        XCTAssertEqual(DamageEstimate.cpIvLine(e).text, "CP 3,412 · 15/14/15")
        XCTAssertEqual(DamageEstimate.cpIvLine(e).spoken, "CP 3412, IVs 15, 14, 15")
        XCTAssertEqual(DamageEstimate.cpIvLine(e, ivs: false).text, "CP 3,412")
        XCTAssertEqual(DamageEstimate.cpIvLine(P23.entry("a", "palkia", ivs: nil, cp: 0)).text, "CP not read · IVs not read")
    }

    func testTheSpokenWords() {
        XCTAssertEqual(Strength(kind: .damage, now: 0.62, after: 0.85).spoken, "estimated damage 62 percent of the best, 85 percent after upgrade")
        XCTAssertEqual(Strength(kind: .damage, now: 0.62, after: nil).spoken, "estimated damage 62 percent of the best")
        XCTAssertEqual(Strength(kind: .bulk, now: 0.5, after: 0.7).spoken, "bulk 50 percent of the best, 70 percent after upgrade")
        XCTAssertEqual(Strength.score(87.2).spoken, "score 87")
    }

    func testGymBulkScaleAndShares() throws {
        let gm = P23.gm
        let best = DamageEstimate.bestGymBulk(gm: gm)
        // Blissey is the highest bulk in the game at level 50 with 15/15/15: (59 + 15)... its own figure is the scale.
        let top = P23.entry("t", "blissey", ivs: IVs(atk: 15, def: 15, hp: 15), level: 50)
        XCTAssertEqual(try XCTUnwrap(DamageEstimate.gymStrength(copy: top, row: nil, speciesId: nil, gm: gm).now), 1, accuracy: 1e-12)
        let low = P23.entry("l", "blissey", ivs: IVs(atk: 0, def: 0, hp: 0), level: 20)
        let b = P23.build("l", "blissey", areas: ["Gym"], built: false, targetLevel: 40)
        let ctx = P23.ctx(builds: [b], entries: [low])
        let row = HubSquads.gymRow(b, ctx: ctx)
        let st = DamageEstimate.gymStrength(copy: low, row: row, speciesId: nil, gm: gm)
        let now = try XCTUnwrap(st.now), after = try XCTUnwrap(st.after)
        XCTAssertLessThan(now, after)
        XCTAssertLessThanOrEqual(after, 1)
        XCTAssertEqual(now, try XCTUnwrap(PogoRules.bulk(target: "blissey", ivs: IVs(atk: 0, def: 0, hp: 0), level: 20, gm: gm).value) / best, accuracy: 1e-12)
        let lacking = DamageEstimate.gymStrength(copy: nil, row: nil, speciesId: "blissey", gm: gm)
        XCTAssertTrue(lacking.assumed)
        XCTAssertEqual(try XCTUnwrap(lacking.now), 1, accuracy: 1e-12)
    }

    /// Ruling 5: a PvP Best row with no copy takes the species' PvPoke league score from the data the app already has.
    func testPvpScoresComeFromTheBundledRankings() throws {
        let scores = try PvpScores.bundled()
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("data/pvp-rankings.json"))) as! [String: Any]
        let ul = ((raw["leagues"] as! [String: Any])["ul"] as! [[String: Any]])[0]
        let id = ul["speciesId"] as! String, score = ul["score"] as! Double
        XCTAssertEqual(try XCTUnwrap(scores.score(speciesId: id, league: "ul")), score, accuracy: 1e-9)
        XCTAssertNil(scores.score(speciesId: "no_such_species", league: "ul"))
        XCTAssertNil(scores.score(speciesId: id, league: "xx"))
        XCTAssertEqual(Strength.score(score).barSolid, score / 100, accuracy: 1e-12)
    }

    func testPvpScoreIsOneBarWithNoFaintPart() {
        let s = Strength.score(87)
        XCTAssertEqual(s.barSolid, 0.87, accuracy: 1e-12)
        XCTAssertFalse(s.hasFaint)
        XCTAssertEqual(Strength.score(130).barEnd, 1)
    }
}
