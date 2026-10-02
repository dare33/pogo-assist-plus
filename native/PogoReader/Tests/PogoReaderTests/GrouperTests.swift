import XCTest
@testable import PogoReader

private let moltres = table.byId["moltres"]!
private let IVS = IVs(atk: 11, def: 14, hp: 11)
private let LEVEL = 25.0
private let CP = cpAt(moltres.baseStats, IVS, LEVEL), HPV = hpAt(moltres.baseStats, IVS, LEVEL)

/// A reading as FrameReader returns it, for a real species so the checks have stats to work with.
private func frame(_ cp: Int?, hp: Int? = HPV, ivs: IVs? = IVS, name: String = "Moltres", n: Int = 0, conf: Double = 0.95, weak: Bool = false) -> FrameReading {
    var r = FrameReading(frame: "f\(n)", time: Double(n) / 5)
    r.name = name; r.nameText = name; r.baseName = name; r.form = ""; r.speciesIds = candidate(name).speciesIds
    r.cp = cp; r.cpReads = cp.map { [$0] } ?? []; r.cpText = cp.map(String.init) ?? ""
    r.hp = hp.map { HP(current: $0, max: $0) }; r.ivs = ivs; r.ivConfidence = ivs == nil ? 0 : conf
    r.nameWeak = weak
    r.flags = cp == nil ? ["no-cp-text"] : []
    return r
}
private func swipe() -> FrameReading { var r = FrameReading(frame: "swipe"); r.flags = ["mid-swipe"]; return r }
/// What a real swipe leaves: a mid-swipe frame then frames with no anchors (3 to 7 of them on the marathon clips).
private func swipes(_ n: Int = 4) -> [FrameReading] { (0..<n).map { _ in swipe() } }

/// Readings in order, one every 0.2 s (the frame numbers in `n` only label them).
private func groupAll(_ readings: [FrameReading]) -> [LiveRow] {
    var g = LiveGrouper(species: table)
    for (i, var r) in readings.enumerated() { r.time = Double(i) * 0.2; g.add(r) }
    g.finish()
    return g.rows
}

final class GrouperTests: XCTestCase {
    func testOnePokemonAcrossAnUnreadableFrameAndAGarbledCpIsOneRow() {
        let rows = groupAll([frame(3028, hp: 145, ivs: IVs(atk: 15, def: 14, hp: 15), name: "Xurkitree", n: 1), swipe(),
                        frame(3023, hp: 145, ivs: IVs(atk: 15, def: 14, hp: 15), name: "Xurkitree", n: 3),
                        frame(3028, hp: 145, ivs: IVs(atk: 15, def: 14, hp: 15), name: "Xurkitree", n: 4),
                        frame(2692, hp: 137, ivs: IVs(atk: 13, def: 12, hp: 14), name: "Zamazenta", n: 5)])
        XCTAssertEqual(rows.map(\.name), ["Xurkitree", "Zamazenta"])
        XCTAssertEqual(rows[0].frames, 3)
        XCTAssertEqual(rows[0].cp, 3028)
        XCTAssertEqual(rows.map(\.index), [1, 2])
    }

    func testADifferentHpSplitsEvenWithTheSameNameAndCp() {
        let m1 = IVs(atk: 12, def: 4, hp: 15), m2 = IVs(atk: 1, def: 1, hp: 1)
        let rows = groupAll((1...4).map { frame(14, hp: 13, ivs: m1, name: "Meltan", n: $0) } + (5...8).map { frame(14, hp: 12, ivs: m2, name: "Meltan", n: $0) })
        XCTAssertEqual(rows.count, 2)
    }

    func testTwoAdjacentPokemonStayApartWhenBothCpAndSettledBarsDiffer() {
        let a = IVs(atk: 10, def: 5, hp: 12), b = IVs(atk: 12, def: 6, hp: 12)
        let rows = groupAll([frame(135, hp: 49, ivs: a, name: "Pidgey"), frame(135, hp: 49, ivs: a, name: "Pidgey"), frame(135, hp: 49, ivs: a, name: "Pidgey")] + swipes()
                        + [frame(139, hp: 49, ivs: b, name: "Pidgey"), frame(139, hp: 49, ivs: b, name: "Pidgey"), frame(139, hp: 49, ivs: b, name: "Pidgey")])
        XCTAssertEqual(rows.map(\.cp), [135, 139])
    }

    func testVotesTheCpTheHpAndTheSettledBars() {
        let rows = groupAll([frame(1614, hp: 94, ivs: IVs(atk: 8, def: 4, hp: 8), name: "Hitmonlee", conf: 0.58),
                        frame(1614, hp: 94, ivs: IVs(atk: 8, def: 1, hp: 8), name: "Hitmonlee", conf: 0.92),
                        frame(1641, hp: 94, ivs: IVs(atk: 8, def: 1, hp: 8), name: "Hitmonlee", conf: 0.92),
                        frame(1614, hp: nil, ivs: IVs(atk: 8, def: 1, hp: 8), name: "Hitmonlee", conf: 0.92)])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].cp, 1614)
        XCTAssertEqual(rows[0].hp, 94)
        XCTAssertEqual(rows[0].ivs, IVs(atk: 8, def: 1, hp: 8))
        XCTAssertEqual(rows[0].frames, 4)
    }

    func testUnsettledBarsAreTheFallbackAndFlagged() {
        let rows = groupAll([frame(1970, hp: 132, ivs: IVs(atk: 6, def: 6, hp: 6), name: "Zapdos", conf: 0.1), frame(1970, hp: 132, ivs: IVs(atk: 11, def: 12, hp: 13), name: "Zapdos", conf: 0.3)])
        XCTAssertEqual(rows[0].ivs, IVs(atk: 11, def: 12, hp: 13))
        XCTAssertTrue(rows[0].flags.contains("bars-unsettled"))
    }

    func testSameCpWithAChanceSettledMidAnimationReadStaysOneRowAndFlagsTheDisagreement() {
        let rows = groupAll([frame(492, hp: 74, ivs: IVs(atk: 13, def: 14, hp: 6), name: "Meltan", conf: 0.9), frame(492, hp: 74, ivs: IVs(atk: 8, def: 14, hp: 1), name: "Meltan", conf: 0.9), frame(492, hp: 74, ivs: IVs(atk: 8, def: 14, hp: 1), name: "Meltan", conf: 0.9)])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].ivs, IVs(atk: 8, def: 14, hp: 1))
        XCTAssertTrue(rows[0].flags.contains("ivs-disagree"))
    }

    /// Fault 3: the leading digit is behind the model; the CP is worked out from HP, bars and the digits read.
    func testACpWhoseLeadingDigitIsHiddenIsRecoveredFromHpBarsAndTheTail() {
        let tail = CP % 1000
        XCTAssertTrue(CP >= 1000 && tail >= 100, "the example needs a four-digit CP")
        let rows = groupAll((1...5).map { frame(tail, n: $0) })
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].cp, CP)
        XCTAssertEqual(rows[0].ivs, IVS)
        XCTAssertEqual(rows[0].flags, ["cp-recovered:\(CP)-from-\(tail)"])
    }

    func testACpReadInFullThatDoesNotFitIsNeverReplacedByARecoveredOne() {
        let wrong = IVs(atk: IVS.atk + 2, def: IVS.def, hp: IVS.hp)
        let decoy = cpOptions([moltres], hp: HPV, ivs: wrong).options[0]
        XCTAssertNotEqual(decoy, CP)
        let rows = groupAll([frame(CP, ivs: wrong, n: 1), frame(CP, ivs: wrong, n: 2), frame(CP, ivs: wrong, n: 3), frame(decoy % 1000, ivs: wrong, n: 4)])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].cp, CP)
        XCTAssertFalse(rows[0].flags.contains { $0.hasPrefix("cp-recovered") })
    }

    func testAnyFullLengthReadBlocksRecoveryEvenOneAgainstSeveralShortOnes() {
        let wrong = IVs(atk: IVS.atk + 2, def: IVS.def, hp: IVS.hp)
        let decoy = cpOptions([moltres], hp: HPV, ivs: wrong).options[0]
        let rows = groupAll([frame(CP, ivs: wrong, n: 1)] + (2...4).map { frame(decoy % 100, ivs: wrong, n: $0) })
        XCTAssertTrue(rows.allSatisfy { !$0.flags.contains { $0.hasPrefix("cp-recovered") } })
    }

    func testCpOptionsListsTheCpsThatFitAndWhichPartialReadIsTheirTail() {
        let r = cpOptions([moltres], hp: HPV, ivs: IVS, ivConfidence: 0.95, reads: [CP % 1000, CP % 100])
        XCTAssertTrue(r.options.contains(CP))
        XCTAssertEqual(r.supported, [CP])
        XCTAssertEqual(r.tailOf[CP], CP % 1000)
        XCTAssertEqual(cpOptions([moltres], hp: HPV, ivs: IVS, ivConfidence: 0.3).options, [])   // unsettled bars prove nothing
        XCTAssertEqual(cpOptions([moltres], hp: HPV, ivs: IVS, reads: [CP % 10]).supported, [])  // one digit is not evidence
    }

    func testFramesWithTheCpHiddenNeverSplitARunNextToTheSamePokemon() {
        let rows = groupAll([frame(CP, n: 1), frame(CP, n: 2), frame(nil, n: 3), frame(nil, n: 4)])
        XCTAssertEqual(rows.count, 1)
        let before = groupAll([frame(nil, n: 1), frame(CP, n: 2), frame(CP, n: 3)])
        XCTAssertEqual(before.count, 1)
    }

    func testAHiddenCpPokemonOfItsOwnIsListedAndItsOnlyFittingCpIsWorkedOut() {
        let rows = groupAll([frame(CP + 9, hp: HPV + 1, ivs: nil, n: 1), frame(CP + 9, hp: HPV + 1, ivs: nil, n: 2), frame(CP + 9, hp: HPV + 1, ivs: nil, n: 3)] + swipes()
                            + [frame(nil, n: 4), frame(nil, n: 5), frame(nil, n: 6)] + swipes()
                            + [frame(CP - 9, hp: HPV - 1, ivs: nil, n: 8), frame(CP - 9, hp: HPV - 1, ivs: nil, n: 9), frame(CP - 9, hp: HPV - 1, ivs: nil, n: 10)])
        XCTAssertEqual(rows.map(\.cp), [CP + 9, CP, CP - 9])
        XCTAssertEqual(rows[1].flags, ["cp-computed:\(CP)"])
        XCTAssertEqual(rows.map(\.index), [1, 2, 3])
        // One or two such frames with no HP are a card sliding past, not an entry.
        XCTAssertEqual(groupAll([frame(CP, n: 1), frame(CP, n: 2), frame(CP, n: 3)] + swipes() + [frame(nil, hp: nil, n: 3), frame(nil, hp: nil, n: 4)] + swipes() + [frame(CP - 9, hp: HPV - 1, ivs: nil, n: 6), frame(CP - 9, hp: HPV - 1, ivs: nil, n: 7), frame(CP - 9, hp: HPV - 1, ivs: nil, n: 8)]).count, 2)
        // A hidden Pokémon whose HP and bars allow several CPs stays listed, with the options.
        let ambiguous = cpOptions([moltres], hp: HPV, ivs: IVS).options
        XCTAssertEqual(ambiguous.count, 1)
    }

    /// Two identical Pokémon in a row (marathon-phone Staraptor 1986) are told apart by the swipe between them.
    func testASwipeBetweenTwoIdenticalReadingsMakesTwoRows() {
        let a = (1...4).map { frame(CP, n: $0) }, b = (6...9).map { frame(CP, n: $0) }
        XCTAssertEqual(groupAll(a + swipes() + b).count, 2)
        // A single unreadable frame inside a Pokémon's time on screen does not split it.
        XCTAssertEqual(groupAll(a + [swipe()] + b).count, 1)
        XCTAssertEqual(groupAll(a + swipes(2) + b).count, 1)
    }

    /// iPad junk rows: partial CP reads while a model crosses the CP, and a mid-slide frame, are absorbed.
    func testPartialAndStrayCardsAreAbsorbedIntoTheSamePokemon() {
        let tail = CP % 1000
        // A tail of the real CP (971 of 1971) is the same Pokémon, not a new row.
        let rows = groupAll([frame(CP, n: 1), frame(CP, n: 2), frame(tail, n: 3), frame(CP % 100, n: 4), frame(CP, n: 5)])
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(cpRelated(1971, 971)); XCTAssertTrue(cpRelated(1971, 197)); XCTAssertTrue(cpRelated(1971, 71))
        XCTAssertFalse(cpRelated(1971, 7)); XCTAssertFalse(cpRelated(1971, 1861))
        // One slide frame with the next card's CP and the last card's HP, bars unsettled, then the next card.
        let slide = frame(CP - 15, hp: HPV, ivs: IVS, n: 5, conf: 0.4)
        let rows2 = groupAll([frame(CP, n: 1), frame(CP, n: 2), frame(CP, n: 3)] + swipes() + [slide, frame(CP - 15, hp: HPV, ivs: IVS, n: 9), frame(CP - 15, hp: HPV, ivs: IVS, n: 10), frame(CP - 15, hp: HPV, ivs: IVS, n: 11)])
        XCTAssertEqual(rows2.map(\.cp), [CP, CP - 15])
        // A one-frame card of another name is not absorbed.
        let other = frame(CP, hp: HPV, ivs: nil, name: "Zapdos", n: 5)
        XCTAssertEqual(groupAll([frame(CP, n: 1), frame(CP, n: 2), frame(CP, n: 3), other, frame(CP, n: 6)]).count, 3)
    }

    /// iPad: the first digits of a CP are read while the model covers the last ("197" of 1971), bars still animating,
    /// then the tail ("971") once settled; and a hidden-CP stretch after a lost frame is still the same Pokémon.
    func testAPrefixReadBeforeTheTailIsAbsorbedAndAHiddenStretchWithTheSameKeyIsNotARow() {
        let prefix = String(CP).prefix(3), tail = CP % 1000
        let rows = groupAll(swipes() + [frame(Int(prefix), hp: nil, ivs: IVS, n: 1, conf: 0.1), frame(Int(prefix), hp: nil, ivs: IVS, n: 2, conf: 0.1)]
                            + (3...7).map { frame(tail, n: $0) })
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].cp, CP)
        XCTAssertEqual(rows[0].frames, 7)
        XCTAssertEqual(rows[0].flags.filter { $0.hasPrefix("absorbed") }, ["absorbed:\(prefix)"], "every absorption leaves a trace on the absorbing row")
        // Same name, HP and settled bars as the run before, a frame or two unreadable between: not a new row.
        let hidden = groupAll((1...4).map { frame(CP, n: $0) } + [swipe(), frame(nil, n: 6), frame(nil, n: 7)])
        XCTAssertEqual(hidden.count, 1)
        // But after a swipe it is another Pokémon's hidden card.
        XCTAssertEqual(groupAll((1...4).map { frame(CP, n: $0) } + swipes() + [frame(nil, n: 6), frame(nil, n: 7)]).count, 2)
    }

    /// iPad: three cards had no HP bar (special background, Lucky nickname): their CP is read, no name. They are listed.
    func testACardWithACpAndNoNameIsListedUnnamedAndAMisreadNameFrameIsNot() {
        func cpOnly(_ cp: Int, n: Int) -> FrameReading { var r = FrameReading(frame: "f\(n)", time: Double(n) / 5); r.cp = cp; r.cpReads = [cp]; r.flags = ["no-hp-bar"]; return r }
        let rows = groupAll((1...4).map { frame(CP, n: $0) } + swipes() + (5...12).map { cpOnly(1484, n: $0) } + swipes() + (13...16).map { frame(CP - 15, hp: HPV, ivs: IVS, n: $0) })
        XCTAssertEqual(rows.map(\.cp), [CP, 1484, CP - 15])
        XCTAssertEqual(rows[1].name, "(name not read)")
        XCTAssertEqual(rows[1].flags, ["name-not-read"])
        XCTAssertEqual(rows[1].frames, 8)
        // A frame of a named Pokémon whose name was misread, or two stray frames, add no row.
        var misread = cpOnly(CP, n: 3); misread.flags = ["name-unmatched"]
        XCTAssertEqual(groupAll([frame(CP, n: 1), frame(CP, n: 2), misread, misread, misread, frame(CP, n: 6)]).count, 1)
        XCTAssertEqual(groupAll([frame(CP, n: 1), frame(CP, n: 2), frame(CP, n: 3)] + swipes() + [cpOnly(1484, n: 8)] + swipes() + [frame(CP - 15, hp: HPV, ivs: IVS, n: 14), frame(CP - 15, hp: HPV, ivs: IVS, n: 15), frame(CP - 15, hp: HPV, ivs: IVS, n: 16)]).count, 2)
        // Two frames (0.4 s) between swipes are listed, as in JS; one is not.
        XCTAssertEqual(groupAll((1...3).map { frame(CP, n: $0) } + swipes() + [cpOnly(1484, n: 8), cpOnly(1484, n: 9)] + swipes() + (14...16).map { frame(CP - 15, hp: HPV, ivs: IVS, n: $0) }).map(\.name), ["Moltres", "(name not read)", "Moltres"])
    }

    func testARowSeenInOneReadingIsFlaggedShortRun() {
        let rows = groupAll((1...4).map { frame(CP, n: $0) } + swipes() + [frame(CP - 30, hp: HPV + 8, ivs: IVs(atk: 4, def: 5, hp: 6), n: 9)] + swipes())
        XCTAssertEqual(rows.count, 2)
        XCTAssertFalse(rows[0].flags.contains("short-run"))
        XCTAssertTrue(rows[1].flags.contains("short-run"))
    }

    func testRowsRememberWhereThePokemonWasOnScreen() {
        let rows = groupAll((1...4).map { frame(CP, n: $0) })
        XCTAssertEqual([rows[0].firstFrame, rows[0].lastFrame], ["f1", "f4"])
        XCTAssertEqual(rows[0].firstTime, 0.0)
        XCTAssertEqual(rows[0].lastTime ?? -1, 0.6, accuracy: 1e-9)
    }

    /// Fault 1 in the grouper: a symbol read names the row, and no sex-from-stats flag is needed.
    func testNidoranWithItsSymbolReadHasASexAndWithoutItIsFlagged() {
        func nido(_ ids: [String], n: Int) -> FrameReading { var r = frame(300, hp: 60, ivs: nil, name: "Nidoran", n: n); r.speciesIds = ids; return r }
        let sexed = groupAll([nido(["nidoran_female"], n: 1), nido(["nidoran_female"], n: 2)])
        XCTAssertEqual(sexed[0].name, "Nidoran♀")
        XCTAssertFalse(sexed[0].flags.contains("sex-not-read"))
        let unsexed = groupAll([nido(["nidoran_female", "nidoran_male"], n: 1)])
        XCTAssertEqual(unsexed[0].name, "Nidoran")
        XCTAssertTrue(unsexed[0].flags.contains("sex-not-read"))
        // Frames with and without the symbol are still one Pokémon.
        let mixed = groupAll([nido(["nidoran_male"], n: 1), nido(["nidoran_female", "nidoran_male"], n: 2)])
        XCTAssertEqual(mixed.count, 1)
        XCTAssertEqual(mixed[0].name, "Nidoran♂")
    }

    func testAWeakNameOfAnotherSpeciesInsideAPokemonsTimeOnScreenAddsNoRow() {
        func sect(_ n: Int) -> FrameReading { frame(1531, hp: 118, ivs: nil, name: "Parasect", n: n) }
        let rows = groupAll([sect(1), sect(2), frame(1531, hp: 118, ivs: nil, name: "Paras", n: 3, weak: true), sect(4), sect(5)])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].frames, 4)
        // A weak read between two other Pokémon is a flagged row of its own.
        let between = groupAll([sect(1), sect(2)] + swipes() + [frame(700, hp: 50, ivs: nil, name: "Venonat", n: 3, weak: true)] + swipes() + [frame(CP, n: 5), frame(CP, n: 6)])
        XCTAssertEqual(between.map(\.name), ["Parasect", "Venonat", "Moltres"])
        XCTAssertEqual(between[1].flags.contains("name-low-confidence"), true)
    }

    func testRowsAreUpdatedLiveAndMemoryStaysBounded() {
        var g = LiveGrouper(species: table)
        XCTAssertTrue(g.add(frame(CP, n: 1)))
        XCTAssertEqual(g.rows.count, 1)
        XCTAssertFalse(g.add(swipe()))
        // A long run of garbled CPs does not grow the tallies without bound (checked through the row staying one row).
        for n in 2...400 { g.add(frame(CP + (n % 7) - 3, n: n)) }
        XCTAssertEqual(g.rows.count, 1)
        XCTAssertEqual(g.rows[0].frames, 400)
    }

    // MARK: round 3

    func testNoCandidateThatFitsAndNoRecoveryIsFlaggedNoLevelFits() {
        for cp in [1, 99] {
            let rows = groupAll((1...3).map { frame(cp, n: $0) })
            XCTAssertEqual(rows.count, 1)
            XCTAssertTrue(rows[0].flags.contains("no-level-fits"), "CP \(cp): \(rows[0].flags)")
        }
        // A CP that fits is not flagged; neither is a row whose bars are not settled (nothing to check against).
        XCTAssertFalse(groupAll((1...3).map { frame(CP, n: $0) })[0].flags.contains("no-level-fits"))
        XCTAssertFalse(groupAll((1...3).map { frame(1, ivs: IVS, n: $0, conf: 0.3) })[0].flags.contains("no-level-fits"))
    }

    func testAStrayWithADifferentHpIsItsOwnPokemon() {
        let a = IVs(atk: 10, def: 10, hp: 10)
        let rows = groupAll((1...6).map { frame(345, hp: 50, ivs: a, name: "Pidgey", n: $0) } + [swipe()]
                            + [frame(375, hp: 55, ivs: IVs(atk: 3, def: 9, hp: 1), name: "Pidgey", n: 8, conf: 0.4), frame(375, hp: 55, ivs: IVs(atk: 4, def: 9, hp: 1), name: "Pidgey", n: 9, conf: 0.4)] + swipes())
        XCTAssertEqual(rows.map(\.cp), [345, 375])
        XCTAssertEqual(rows[0].frames, 6)
        XCTAssertFalse(rows[0].flags.contains { $0.hasPrefix("absorbed") })
    }

    func testAWeakNamedFirstOrLastPokemonOrOneAfterASwipeIsAFlaggedRow() {
        func pidgey(_ n: Int) -> FrameReading { frame(345, hp: 50, ivs: IVS, name: "Pidgey", n: n) }
        func weakRattata(_ n: Int) -> FrameReading { frame(210, hp: 41, ivs: nil, name: "Rattata", n: n, weak: true) }
        // First Pokémon weak.
        let first = groupAll((1...5).map(weakRattata) + swipes() + (6...10).map(pidgey))
        XCTAssertEqual(first.map(\.name), ["Rattata", "Pidgey"])
        XCTAssertTrue(first[0].flags.contains("name-low-confidence"))
        // Last Pokémon weak.
        let last = groupAll((1...5).map(pidgey) + swipes() + (6...10).map(weakRattata))
        XCTAssertEqual(last.map(\.name), ["Pidgey", "Rattata"])
        XCTAssertTrue(last[1].flags.contains("name-low-confidence"))
        // Same species as the neighbour but another Pokémon (different CP and HP, a swipe between).
        func weakPidgey(_ n: Int) -> FrameReading { frame(500, hp: 60, ivs: nil, name: "Pidgey", n: n, weak: true) }
        let same = groupAll((1...5).map(pidgey) + swipes() + (6...10).map(weakPidgey) + swipes() + (11...15).map { frame(210, hp: 41, ivs: IVS, name: "Rattata", n: $0) })
        XCTAssertEqual(same.map(\.name), ["Pidgey", "Pidgey", "Rattata"])
        XCTAssertTrue(same[1].flags.contains("name-low-confidence"))
        // The same Pokémon's own weak frames (no swipe, related CP) add nothing.
        XCTAssertEqual(groupAll((1...4).map(pidgey) + [frame(345, hp: 50, ivs: nil, name: "Pidgey", n: 5, weak: true)] + (6...8).map(pidgey)).count, 1)
    }

    func testAHiddenCpPokemonAtTheEndComesAfterTheOneBeforeIt() {
        let rows = groupAll((1...6).map { frame(CP, n: $0) } + swipes() + (11...15).map { frame(nil, ivs: IVS, n: $0) })
        XCTAssertEqual(rows.map(\.index), [1, 2])
        XCTAssertEqual(rows[0].cp, CP)
        XCTAssertEqual(rows[1].flags.first, "cp-computed:\(CP)")
    }

    func testNidoranWithoutTheSymbolTakesTheSexWhoseStatsFit() {
        let male = table.byId["nidoran_male"]!, ivs = IVs(atk: 9, def: 10, hp: 13)
        let cp = cpAt(male.baseStats, ivs, 20), hp = hpAt(male.baseStats, ivs, 20)
        func nido(_ n: Int) -> FrameReading { var r = frame(cp, hp: hp, ivs: ivs, name: "Nidoran", n: n); r.speciesIds = ["nidoran_female", "nidoran_male"]; return r }
        let rows = groupAll((1...4).map(nido))
        let femaleFits = cpFits([table.byId["nidoran_female"]!], cp: cp, hp: hp, ivs: ivs) == true
        if femaleFits { XCTAssertTrue(rows[0].flags.contains("sex-not-read")) }
        else { XCTAssertEqual(rows[0].name, "Nidoran♂"); XCTAssertFalse(rows[0].flags.contains("sex-not-read")) }
    }

    /// Thresholds are durations: the same Pokémon read in every other frame (a busy extension) groups the same.
    func testGroupingDoesNotDependOnHowManyFramesWereRead() {
        func at(_ r: FrameReading, _ t: Double) -> FrameReading { var x = r; x.time = t; return x }
        func run(_ step: Double) -> [LiveRow] {
            var g = LiveGrouper(species: table)
            var t = 0.0
            func put(_ r: FrameReading, count: Int) { for _ in 0..<count { g.add(at(r, t)); t += step } }
            put(frame(CP, n: 1), count: Int(1.4 / step))
            put(swipe(), count: Int(0.8 / step))
            put(frame(CP - 15, hp: HPV + 4, ivs: IVs(atk: 1, def: 2, hp: 3), n: 2), count: Int(1.4 / step))
            put(swipe(), count: Int(0.8 / step))
            put(frame(CP - 30, hp: HPV + 8, ivs: IVs(atk: 4, def: 5, hp: 6), n: 3), count: Int(1.4 / step))
            g.finish()
            return g.rows
        }
        for step in [0.2, 0.4, 0.7] { XCTAssertEqual(run(step).map(\.cp), [CP, CP - 15, CP - 30], "step \(step)") }
        // Two identical Pokémon with the swipe unseen merge, and the row says so.
        var g = LiveGrouper(species: table)
        for k in 0..<8 { g.add(at(frame(CP, n: k), Double(k) * 0.45)) }
        g.finish()
        XCTAssertEqual(g.rows.count, 1)
        XCTAssertTrue(g.rows[0].flags.contains("long-stay"))
    }

    func testTheCurrentRunsTalliesStayBoundedWhateverIsRead() {
        var g = LiveGrouper(species: table)
        for n in 0..<600 {
            var r = frame(CP, hp: HPV, ivs: IVS, n: n)
            r.cpReads = [CP, 1000 + n % 97]     // many different reads
            r.ivs = IVs(atk: n % 16, def: (n / 16) % 16, hp: (n / 256) % 16); r.ivConfidence = 0.9
            r.time = Double(n) * 0.2
            g.add(r)
        }
        XCTAssertLessThanOrEqual(g.debugTallySize, 16 + 8 + 12)
        XCTAssertGreaterThan(g.debugTallySize, 8, "the tallies are in use")
        XCTAssertEqual(g.rows.count, 1)
    }

    func testAHiddenCardWithSeveralFittingLevelsIsListedWithItsOptions() {
        var found: (sp: Species, hp: Int, ivs: IVs, options: [Int])?
        for sp in table.species where found == nil && !sp.id.contains("_") {
            let ivs = IVs(atk: 7, def: 7, hp: 7)
            for hp in [20, 25, 30, 35, 40] {
                let o = cpOptions([sp], hp: hp, ivs: ivs).options
                if o.count >= 2 && o.count <= 6 { found = (sp, hp, ivs, o); break }
            }
        }
        let f = found!
        let display = names.first { $0.speciesIds.contains(f.sp.id) }!.display
        let rows = groupAll((1...4).map { frame(nil, hp: f.hp, ivs: f.ivs, name: display, n: $0) })
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0].cp)
        XCTAssertEqual(rows[0].flags, ["cp-not-read", "cp-options:" + f.options.map(String.init).joined(separator: "|")])
    }

    func testNidorinaRunIsNotInterruptedByANidoranWithALetterStuckToIt() {
        func nidorina(_ n: Int) -> FrameReading { frame(500, hp: 70, ivs: nil, name: "Nidorina", n: n) }
        var stray = frame(500, hp: 70, ivs: nil, name: "Nidoran", n: 3); stray.nameAttached = true
        XCTAssertEqual(groupAll([nidorina(1), nidorina(2), stray, nidorina(4)]).count, 1)
    }
}
