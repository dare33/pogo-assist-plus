import XCTest
@testable import PogoBox
import PogoReader

/// Pass 2's Collection numbers (rules 25 and 26, the Showcase replaced by the set strips), on the bundled game master (959 released species: the flag's 951 and the eight it wrongly leaves out).
final class HubCollectionTests: XCTestCase {
    private let gm = P23.gm

    func testTheReleasedSpeciesAreOnePerDexNumberWithoutMegaShadowOrDuplicates() {
        let s = HubCollection.releasedSpecies(gm: gm)
        XCTAssertEqual(s.count, 959)
        XCTAssertEqual(Set(s.map(\.dex)).count, 959, "one per dex number")
        XCTAssertEqual(s.first { $0.dex == 25 }?.id, "pikachu", "the plain species, not pikachu_libre")
        XCTAssertEqual(s.first { $0.dex == 6 }?.id, "charizard", "not charizard_mega_x")
        XCTAssertFalse(s.contains { $0.tags.contains("mega") || $0.tags.contains("shadow") || $0.tags.contains("duplicate") })
        XCTAssertEqual(s.map(\.dex), s.map(\.dex).sorted())
    }

    /// F4 (eyeball check 31 Oct 2026): the game master's `released` flag leaves out 74 dex numbers. 66 of them are unreleased in Pokémon GO (Bulbapedia, "Unreleased
    /// Pokémon", revision 4657810) and stay out; the other eight are in the game and are counted: 959 species, not 951.
    func testTheEightReleasedSpeciesTheFlagLeavesOutAreCountedAndTheSixtySixAreNot() {
        let dex = Set(HubCollection.releasedSpecies(gm: gm).map(\.dex))
        XCTAssertEqual(dex.count, 959)
        let inGo: [Int: String] = [132: "Ditto", 292: "Shedinja", 665: "Spewpa", 774: "Minior", 789: "Cosmog", 790: "Cosmoem", 946: "Bramblin", 947: "Brambleghast"]
        XCTAssertEqual(Set(inGo.keys), HubCollection.releasedInGoDespiteFlag)
        for (d, name) in inGo {
            XCTAssertTrue(dex.contains(d), name)
            XCTAssertTrue(HubCollection.releasedSpecies(gm: gm).first { $0.dex == d }?.name.hasPrefix(name) == true, name)
            XCTAssertNotNil(HubCollection.missingSpecies(entries: [], advice: BoxAdvice(), gm: gm).first { $0.dex == d }, "\(name) is in the Missing list of an empty box")
        }
        let unreleased: [Int] = [489, 490, 493, 746, 771, 772, 773, 801, 833, 834, 868, 869, 871, 875, 878, 879, 880, 881, 882, 883, 896, 897, 898, 902, 951, 952, 953, 954, 963, 964, 967, 976, 981]
            + Array(984...995) + Array(1001...1010) + Array(1014...1018) + Array(1020...1025)
        XCTAssertEqual(unreleased.count, 66)
        for d in unreleased { XCTAssertFalse(dex.contains(d), "dex \(d) is not in Pokémon GO yet") }
        XCTAssertEqual(1025 - dex.count, 66, "every dex number is counted except the 66")
        // A box that holds an unreleased one (a hand-made entry) still counts it, so owned never exceeds the total.
        XCTAssertTrue(HubCollection.releasedSpecies(gm: gm, owned: [489]).map(\.dex).contains(489))
    }

    func testRegionsCoverTheDexRanges() {
        XCTAssertEqual(HubCollection.regions.first?.dex, 1...151)
        XCTAssertEqual(HubCollection.regions.last?.dex, 906...1025)
        XCTAssertEqual(HubCollection.region(ofDex: 151), "Kanto")
        XCTAssertEqual(HubCollection.region(ofDex: 152), "Johto")
        XCTAssertEqual(HubCollection.region(ofDex: 905), "Galar")
        XCTAssertEqual(HubCollection.region(ofDex: 906), "Paldea")
        XCTAssertNil(HubCollection.region(ofDex: 1026))
        XCTAssertNil(HubCollection.region(ofDex: 0))
        XCTAssertEqual(HubCollection.regions.count, 9)
    }

    func testAnEmptyBoxOwnsNothing() {
        let o = HubCollection.overview(entries: [], gm: gm)
        XCTAssertEqual(o.owned, 0); XCTAssertEqual(o.released, 959); XCTAssertEqual(o.percent, 0); XCTAssertEqual(o.canEvolve, 0)
        XCTAssertEqual(o.regions.map(\.name), ["Kanto", "Johto", "Hoenn", "Sinnoh", "Unova", "Kalos", "Alola", "Galar", "Paldea"])
        XCTAssertEqual(o.regions.map(\.total), [151, 100, 135, 104, 156, 72, 83, 80, 78])
        XCTAssertEqual(o.regions.map(\.total).reduce(0, +), 959)
        XCTAssertTrue(o.regions.allSatisfy { $0.owned == 0 })
        XCTAssertEqual(HubCollection.missingSpecies(entries: [], advice: BoxAdvice(), gm: gm).count, 959)
    }

    func testAFormOrAShadowCopyOwnsItsSpeciesAndCopiesAreCountedOnce() {
        let box = [P23.entry("a", "charizard"), P23.entry("b", "charizard", shadow: 1), P23.entry("c", "pikachu_libre"), P23.entry("d", "charizard_mega_x")]
        let o = HubCollection.overview(entries: box, gm: gm)
        XCTAssertEqual(o.owned, 2, "Charizard (three copies, one Shadow, one Mega) and Pikachu (Libre)")
        XCTAssertEqual(o.regions.first?.owned, 2)
        XCTAssertEqual(o.percent, 0, "2 of 959 rounds to 0 per cent")
        XCTAssertEqual(HubCollection.ownedDex(entries: box, gm: gm), [6, 25])
        // A species the game master does not know owns nothing.
        var odd = P23.entry("z", "pikachu"); odd.row.speciesId = "not_a_species"
        XCTAssertEqual(HubCollection.ownedDex(entries: [odd], gm: gm), [])
    }

    func testMissingSpeciesSayWhenYouCanEvolveThem() {
        let missing = HubCollection.missingSpecies(entries: [P23.entry("a", "charmander")], advice: BoxAdvice(), gm: gm)
        let byDex = Dictionary(uniqueKeysWithValues: missing.map { ($0.dex, $0) })
        XCTAssertNil(byDex[4], "owned")
        XCTAssertEqual(byDex[5]?.evolvesFrom, "Charmander")
        XCTAssertEqual(byDex[6]?.evolvesFrom, "Charmander", "two stages up still counts")
        XCTAssertEqual(byDex[5]?.how, "Evolve from Charmander (you have one)")
        XCTAssertNil(byDex[7]?.evolvesFrom, "Squirtle's line has nobody in the box")
        XCTAssertEqual(byDex[7]?.region, "Kanto")
        XCTAssertEqual(byDex[150]?.how, "Legendary")
        XCTAssertEqual(byDex[151]?.how, "Mythical")
        XCTAssertEqual(HubCollection.overview(entries: [P23.entry("a", "charmander")], gm: gm).canEvolve, 2)
        // The research's obtain text is the way to get a species with a gap listed.
        let advice = BoxAdvice(gaps: [P23.gap("Gym", "Squirtle", "squirtle", obtain: "Easy. Wild")])
        XCTAssertEqual(HubCollection.missingSpecies(entries: [], advice: advice, gm: gm).first { $0.dex == 7 }?.how, "Easy. Wild")
        XCTAssertEqual(HubCollection.missingSpecies(entries: [], advice: BoxAdvice(), gm: gm).first { $0.dex == 7 }?.how, "")
    }

    // MARK: Special sets

    func testSpecialSetsCountCopiesAndSpecies() {
        let box = [P23.entry("a", "pikachu", ivs: IVs(atk: 15, def: 15, hp: 15)), P23.entry("b", "registeel"), P23.entry("c", "charizard", shadow: 1),
                   P23.entry("d", "mew"), P23.entry("e", "nihilego"), P23.entry("f", "charizard", ivs: IVs(atk: 15, def: 15, hp: 15))]
        let sets = HubCollection.specialSets(entries: box, gm: gm)
        let by = Dictionary(uniqueKeysWithValues: sets.map { ($0.name, $0) })
        XCTAssertEqual(sets.map(\.name), ["Hundo", "Legendary", "Mythical", "Ultra Beasts", "Mega-capable", "Lucky", "Shadow", "Dynamax", "Gigantamax", "Shiny", "Background"])
        XCTAssertEqual(by["Hundo"]?.owned, 2); XCTAssertNil(by["Hundo"]?.total); XCTAssertEqual(by["Hundo"]?.unit, "copies")
        XCTAssertEqual(by["Legendary"]?.owned, 1); XCTAssertEqual(by["Legendary"]?.total, 52)
        XCTAssertEqual(by["Mythical"]?.owned, 1); XCTAssertEqual(by["Mythical"]?.total, 18)
        XCTAssertEqual(by["Ultra Beasts"]?.owned, 1); XCTAssertEqual(by["Ultra Beasts"]?.total, 12)
        XCTAssertEqual(by["Mega-capable"]?.owned, 1, "Charizard (two copies) is one species"); XCTAssertEqual(by["Mega-capable"]?.total, 58)
        XCTAssertEqual(by["Shadow"]?.owned, 1)
        XCTAssertEqual(by["Shadow"]?.unitWord, "copy", "one copy reads singular")
        XCTAssertEqual(by["Hundo"]?.unitWord, "copies")
        XCTAssertEqual(by["Legendary"]?.unitWord, "species")
        XCTAssertEqual(by["Lucky"]?.note, "Not in your scans yet", "no copy carries a Lucky mark"); XCTAssertNil(by["Lucky"]?.owned)
    }

    func testAShadowSpeciesCopyCountsAsShadowToo() {
        let box = [P23.entry("a", "charizard", shadow: 1), P23.entry("b", "charizard_shadow"), P23.entry("c", "pikachu")]
        let by = Dictionary(uniqueKeysWithValues: HubCollection.specialSets(entries: box, gm: gm).map { ($0.name, $0) })
        XCTAssertEqual(by["Shadow"]?.owned, 2, "a copy marked Shadow and a copy of a _shadow species")
    }

    func testLuckyHasACountOnceACopyCarriesTheMark() {
        let box = [P23.entry("a", "pikachu"), P23.entry("b", "eevee")]
        let sets = HubCollection.specialSets(entries: box, gm: gm, isLucky: { $0.id == "b" })
        XCTAssertEqual(sets.first { $0.name == "Lucky" }?.owned, 1)
        XCTAssertNil(sets.first { $0.name == "Lucky" }?.note)
    }

    /// A card's count and the list that opens from it are one definition: copies for the copy sets, the owned species (with all their copies) for the species sets.
    func testEachSetsCountIsItsListSize() {
        let hundo = IVs(atk: 15, def: 15, hp: 15)
        let box = [P23.entry("a", "pikachu", ivs: hundo), P23.entry("b", "registeel"), P23.entry("c", "charizard", shadow: 1), P23.entry("d", "mew"),
                   P23.entry("e", "nihilego"), P23.entry("f", "charizard", ivs: hundo), P23.entry("g", "charizard_shadow"), P23.entry("h", "registeel"),
                   P23.entry("i", "eevee")]
        let lucky: (BoxEntry) -> Bool = { ["b", "i"].contains($0.id) }
        let by = Dictionary(uniqueKeysWithValues: HubCollection.specialSets(entries: box, gm: gm, isLucky: lucky).map { ($0.name, $0) })
        for kind in HubCollection.SetKind.allCases where !kind.isComingSoon {
            let list = HubCollection.members(of: kind, entries: box, gm: gm, isLucky: lucky)
            let size = kind.isSpeciesSet ? Set(list.compactMap { gm.byId[$0.row.speciesId]?.dex }).count : list.count
            XCTAssertEqual(by[kind.name]?.owned, size, "\(kind.name): the card counts what the list shows")
        }
        func ids(_ k: HubCollection.SetKind) -> [String] { HubCollection.members(of: k, entries: box, gm: gm, isLucky: lucky).map(\.id) }
        XCTAssertEqual(ids(.hundo), ["a", "f"])
        XCTAssertEqual(ids(.legendary), ["b", "h"], "every copy of an owned species")
        XCTAssertEqual(ids(.megaCapable), ["f"], "a Shadow Charizard cannot Mega Evolve, marked or by its species")
        XCTAssertEqual(ids(.shadow), ["c", "g"])
        XCTAssertEqual(ids(.lucky), ["b", "i"])
        XCTAssertEqual(ids(.mythical), ["d"])
        XCTAssertEqual(ids(.ultraBeasts), ["e"])
        XCTAssertEqual(HubCollection.members(of: .lucky, entries: box, gm: gm), [], "no row carries the Lucky mark")
    }

    /// The hand mark wins: a `_shadow` species marked Purified is Purified, not Shadow; a Shadow mark makes any species a Shadow; no mark leaves it to the species.
    func testTheShadowMarkBeatsTheSpeciesSuffix() {
        let box = [P23.entry("a", "charizard_shadow", shadow: 2), P23.entry("b", "charizard_shadow", shadow: 0), P23.entry("c", "charizard_shadow"),
                   P23.entry("d", "charizard", shadow: 1), P23.entry("e", "charizard", shadow: 2)]
        func ids(_ k: HubCollection.SetKind) -> [String] { HubCollection.members(of: k, entries: box, gm: gm).map(\.id) }
        XCTAssertEqual(ids(.shadow), ["c", "d"])
        XCTAssertEqual(ids(.megaCapable), ["a", "b", "e"], "a Purified (or unmarked-0) copy of Charizard (Shadow) is a Charizard again and can Mega Evolve; a Shadow copy cannot")
        // The Shadow to Purified transition: the same copy leaves the set when its mark changes.
        let before = [P23.entry("x", "charizard", shadow: 1)], after = [P23.entry("x", "charizard", shadow: 2)]
        XCTAssertEqual(HubCollection.members(of: .shadow, entries: before, gm: gm).count, 1)
        XCTAssertEqual(HubCollection.members(of: .shadow, entries: after, gm: gm).count, 0)
        XCTAssertEqual(HubCollection.members(of: .megaCapable, entries: after, gm: gm).count, 1)
    }

    /// Mega-capable is the copy's own species-form: Galarian Slowbro, Armored Mewtwo and Alolan Raichu have no Mega of their own.
    func testMegaCapableIsTheCopysOwnForm() {
        let box = [P23.entry("a", "slowbro"), P23.entry("b", "slowbro_galarian"), P23.entry("c", "mewtwo"), P23.entry("d", "mewtwo_armored"),
                   P23.entry("e", "raichu"), P23.entry("f", "raichu_alolan"), P23.entry("g", "kyogre")]
        XCTAssertEqual(HubCollection.members(of: .megaCapable, entries: box, gm: gm).map(\.id), ["a", "c", "e", "g"])
    }

    /// A species set counts species while the list can hold a species' forms: Giratina Altered and Origin are one species (one dex number).
    func testASpeciesSetCountsFormsAsOneSpecies() {
        let box = [P23.entry("a", "giratina_altered"), P23.entry("b", "giratina_origin"), P23.entry("c", "giratina_origin")]
        let by = Dictionary(uniqueKeysWithValues: HubCollection.specialSets(entries: box, gm: gm).map { ($0.name, $0) })
        XCTAssertEqual(by["Legendary"]?.owned, 1)
        XCTAssertEqual(HubCollection.members(of: .legendary, entries: box, gm: gm).count, 3)
    }

    func testAnEmptyBoxHasEmptySets() {
        let sets = HubCollection.specialSets(entries: [], gm: gm)
        XCTAssertEqual(sets.map { $0.owned ?? -1 }, [0, 0, 0, 0, 0, -1, 0, 0, 0, -1, -1])
        XCTAssertEqual(sets[1].total, 52)
    }

    // MARK: Dynamax, Gigantamax, Shiny and Background (eyeball check C2)

    func testDynamaxAndGigantamaxSetsReadTheMarksTheBoxHas() {
        var g = P23.entry("g", "charizard"); g.row.gigantamax = true
        var both = P23.entry("b", "lapras", dynamax: true); both.row.gigantamax = true
        let box = [P23.entry("d", "snorlax", dynamax: true), g, both, P23.entry("n", "pikachu", dynamax: false)]
        func ids(_ k: HubCollection.SetKind) -> [String] { HubCollection.members(of: k, entries: box, gm: gm).map(\.id) }
        XCTAssertEqual(ids(.dynamax), ["d", "b"]); XCTAssertEqual(ids(.gigantamax), ["g", "b"])
        let by = Dictionary(uniqueKeysWithValues: HubCollection.specialSets(entries: box, gm: gm).map { ($0.name, $0) })
        XCTAssertEqual(by["Dynamax"]?.owned, 2); XCTAssertEqual(by["Gigantamax"]?.owned, 2)
        XCTAssertEqual(by["Dynamax"]?.unit, "copies"); XCTAssertNil(by["Dynamax"]?.note)
    }

    func testShinyAndBackgroundSayComingSoonAndHaveNoMembers() {
        let box = [P23.entry("a", "pikachu")]
        let by = Dictionary(uniqueKeysWithValues: HubCollection.specialSets(entries: box, gm: gm).map { ($0.name, $0) })
        for name in ["Shiny", "Background"] {
            XCTAssertEqual(by[name]?.note, "Coming soon"); XCTAssertNil(by[name]?.owned); XCTAssertNil(by[name]?.total)
        }
        XCTAssertTrue(HubCollection.SetKind.shiny.isComingSoon && HubCollection.SetKind.background.isComingSoon)
        XCTAssertEqual(HubCollection.SetKind.allCases.filter(\.isComingSoon).count, 2)
        XCTAssertEqual(HubCollection.members(of: .shiny, entries: box, gm: gm), [])
    }

    // MARK: the strips (eyeball check C4)

    private func fit(_ area: String, _ tag: BoxAdvice.Fit.Tag, _ tier: String?) -> BoxAdvice.Fit {
        BoxAdvice.Fit(area: area, tag: tag, asName: "X", tier: tier, reason: tag == .weak ? BoxAdvice.Fit.Reason.none : nil, species: nil, ivPercent: 90)
    }
    private func advice(_ fits: [String: [String: BoxAdvice.Fit]]) -> BoxAdvice { var a = BoxAdvice(); a.fit = fits; return a }

    func testEachSetIsRankedByItsOwnActivity() {
        XCTAssertEqual(HubCollection.rankingActivity(.dynamax), .max); XCTAssertEqual(HubCollection.rankingActivity(.gigantamax), .max)
        for k in [HubCollection.SetKind.shadow, .legendary, .mythical, .ultraBeasts, .megaCapable] { XCTAssertEqual(HubCollection.rankingActivity(k), .raids, k.name) }
        for k in [HubCollection.SetKind.hundo, .lucky, .shiny, .background] { XCTAssertNil(HubCollection.rankingActivity(k), k.name) }
    }

    func testMaxSetsRankByMaxFitNotByRaids() {
        // "a" is the better raid copy, "b" the better Max one; the Dynamax strip puts b first and the Shadow strip a first.
        var a = P23.entry("a", "snorlax", dynamax: true), b = P23.entry("b", "snorlax", dynamax: true); a.row.shadow = 1; b.row.shadow = 1
        let adv = advice(["a": ["raids": fit("raids", .strong, "S"), "max": fit("max", .weak, nil)], "b": ["raids": fit("raids", .ok, "B"), "max": fit("max", .strong, "A")]])
        XCTAssertEqual(HubCollection.strip(kind: .dynamax, members: [a, b], gm: gm, advice: adv).map(\.entry.id), ["b", "a"])
        XCTAssertEqual(HubCollection.strip(kind: .shadow, members: [a, b], gm: gm, advice: adv).map(\.entry.id), ["a", "b"])
    }

    func testTierBreaksATieInTagAndIVsBreakTheRest() {
        let hi = IVs(atk: 15, def: 15, hp: 15), lo = IVs(atk: 10, def: 10, hp: 10)
        let box = [P23.entry("a", "snorlax", ivs: lo), P23.entry("b", "snorlax", ivs: hi), P23.entry("c", "snorlax", ivs: lo), P23.entry("d", "snorlax", ivs: nil)]
        let adv = advice(["a": ["raids": fit("raids", .ok, "A")], "b": ["raids": fit("raids", .ok, "B")], "c": ["raids": fit("raids", .ok, "A")], "d": ["raids": fit("raids", .ok, "A")]])
        XCTAssertEqual(HubCollection.strip(kind: .hundo, members: box, gm: gm, advice: adv).map(\.entry.id), ["a", "c", "d", "b"],
                       "A tier before B tier; a and c tie on IVs and CP so the id decides; the unread IVs come last of the A tier")
    }

    func testTheAnyActivityRankTakesTheBestActivity() {
        let box = [P23.entry("a", "pikachu"), P23.entry("b", "pikachu"), P23.entry("c", "pikachu")]
        let adv = advice(["a": ["gym": fit("gym", .ok, "B")], "b": ["rocket": fit("rocket", .strong, "S")], "c": ["raids": fit("raids", .weak, nil)]])
        let strip = HubCollection.strip(kind: .lucky, members: box, gm: gm, advice: adv)
        XCTAssertEqual(strip.map(\.entry.id), ["b", "a", "c"])
        XCTAssertEqual(strip.map(\.rank.words), ["Rocket S", "Gym B", "Raids Weak"])
        // With no advice yet every copy is unranked and the IVs order them.
        XCTAssertEqual(HubCollection.strip(kind: .lucky, members: box, gm: gm, advice: BoxAdvice()).map(\.entry.id), ["a", "b", "c"])
    }

    private func league(_ id: String, score: Double?, pct: Double = 97, rankPct: Double = 95) -> BoxAdvice.LeagueRating {
        BoxAdvice.LeagueRating(options: [.init(speciesId: id, name: id.capitalized, isSelf: false, genderLocked: nil, strength: score.map { .init(score: $0, rank: 10, of: 1152) }, moves: nil, needs: nil,
                                               iv: .init(rank: 100, pct: pct, rankPct: rankPct, level: 20, cp: 1490), overCap: false, cost: nil)])
    }

    /// The PvP rank path: the best Great or Ultra League card's worth is the level and its own tier (S, A, B) the tier, so a Great League S copy is not ranked behind a Raids B one.
    func testPvPRanksByTheLeagueCardsWorthAndTier() {
        let box = [P23.entry("s", "pikachu"), P23.entry("a", "pikachu"), P23.entry("none", "pikachu")]
        var adv = advice([:])
        adv.leagues = ["s": ["gl": league("pikachu", score: 94)], "a": ["ul": league("pikachu", score: 90.5)]]
        let s = HubCollection.rank(box[0], in: .pvp, advice: adv), a = HubCollection.rank(box[1], in: .pvp, advice: adv)
        XCTAssertEqual(s.level, 3); XCTAssertEqual(s.tier, 0); XCTAssertEqual(s.words, "PvP Top")
        XCTAssertEqual(a.level, 2); XCTAssertEqual(a.tier, 1); XCTAssertEqual(a.words, "PvP Good")
        XCTAssertEqual(HubCollection.rank(box[2], in: .pvp, advice: adv), .none, "no league card: not in PvP")
        XCTAssertGreaterThan(s, a)
        // Master League is left out, as TOP PVP leaves it out.
        adv.leagues["none"] = ["ml": league("pikachu", score: 99)]
        XCTAssertEqual(HubCollection.rank(box[2], in: .pvp, advice: adv), .none)
    }

    func testTheAnyActivityRankComparesPvPWithRaids() {
        let box = [P23.entry("pvp", "pikachu"), P23.entry("raid", "pikachu"), P23.entry("pvpB", "pikachu")]
        var adv = advice(["raid": ["raids": fit("raids", .strong, "B")]])
        adv.leagues = ["pvp": ["gl": league("pikachu", score: 94)]]
        // A Strong Great League S copy beats a Strong Raids B copy: same level, better tier.
        XCTAssertEqual(HubCollection.strip(kind: .hundo, members: box, gm: gm, advice: adv).map(\.entry.id).prefix(2), ["pvp", "raid"])
        XCTAssertEqual(HubCollection.rank(box[0], for: .hundo, advice: adv).words, "PvP Top")
        XCTAssertEqual(HubCollection.rank(box[1], for: .hundo, advice: adv).words, "Raids B")
    }

    func testASpeciesSetStripShowsEachSpeciesOnceAndACopySetShowsCopies() {
        let box = [P23.entry("a", "registeel", cp: 1000), P23.entry("b", "registeel", cp: 2000), P23.entry("c", "mewtwo", cp: 500)]
        XCTAssertEqual(HubCollection.strip(kind: .legendary, members: box, gm: gm, advice: BoxAdvice()).map(\.entry.id), ["b", "c"], "one card per species, its best copy")
        XCTAssertEqual(HubCollection.strip(kind: .hundo, members: box, gm: gm, advice: BoxAdvice()).map(\.entry.id), ["b", "a", "c"], "a set of copies lists copies")
        XCTAssertEqual(HubCollection.strip(kind: .hundo, members: box, gm: gm, advice: BoxAdvice(), limit: 2).count, 2)
        XCTAssertEqual(HubCollection.strip(kind: .shiny, members: [], gm: gm, advice: BoxAdvice()), [])
    }

    // MARK: the Missing summary (eyeball check C3)

    func testMissingSummaryCountsAndBreaksDown() {
        let missing = HubCollection.missingSpecies(entries: [P23.entry("a", "charmander")], advice: BoxAdvice(), gm: gm)
        let s = HubCollection.missingSummary(missing)
        XCTAssertEqual(s.count, missing.count)
        XCTAssertEqual(s.canEvolve, 2, "Charmeleon and Charizard")
        XCTAssertEqual(s.legendary, missing.filter { $0.tags.contains("legendary") }.count); XCTAssertGreaterThan(s.legendary, 40)
        XCTAssertEqual(s.mythical, missing.filter { $0.tags.contains("mythical") }.count); XCTAssertGreaterThan(s.mythical, 10)
        XCTAssertEqual(s.topRegion?.name, "Unova", "156 species, the most of any region")
        XCTAssertEqual(s.parts.first, "2 you can evolve now")
        XCTAssertTrue(s.parts.last?.hasPrefix("most in Unova (") == true, s.parts.description)
        let none = HubCollection.missingSummary([])
        XCTAssertEqual(none.count, 0); XCTAssertNil(none.topRegion); XCTAssertEqual(none.parts, [])
    }
}
