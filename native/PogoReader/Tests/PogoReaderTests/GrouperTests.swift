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

    // MARK: round 4

    /// A name alone (CP and HP hidden) is a card, not a swipe: the Moltres is listed, flagged.
    func testANameOnlyCardIsListed() {
        func zapdos(_ n: Int) -> FrameReading { frame(CP, hp: HPV, ivs: IVS, name: "Zapdos", n: n) }
        func moltresNameOnly(_ n: Int) -> FrameReading { var r = frame(nil, hp: nil, ivs: nil, name: "Moltres", n: n); r.ivs = nil; return r }
        let withSwipes = groupAll((1...4).map(zapdos) + swipes() + (5...9).map(moltresNameOnly) + swipes() + (10...13).map(zapdos))
        XCTAssertEqual(withSwipes.map(\.name), ["Zapdos", "Moltres", "Zapdos"])
        XCTAssertTrue(withSwipes[1].flags.contains("cp-not-read"))
        // No separators at all around it: still listed.
        let bare = groupAll((1...4).map(zapdos) + (5...9).map(moltresNameOnly) + (10...13).map(zapdos))
        XCTAssertTrue(bare.contains { $0.name == "Moltres" && $0.flags.contains("cp-not-read") })
    }

    func testASwipeTickMakesTheNextCardANewPokemonEvenWhenItReadsTheSame() {
        func at(_ r: FrameReading, _ t: Double) -> FrameReading { var x = r; x.time = t; return x }
        func run(tick: Double?) -> [LiveRow] {
            var g = LiveGrouper(species: table)
            for k in 0..<4 { g.add(at(frame(CP, n: k), Double(k) * 0.2)) }
            if let t = tick { g.swipe(at: t) }
            for k in 0..<4 { g.add(at(frame(CP, n: 10 + k), 2.0 + Double(k) * 0.2)) }   // a gap with no readings at all
            g.finish()
            return g.rows
        }
        XCTAssertEqual(run(tick: nil).count, 1)
        XCTAssertEqual(run(tick: 1.0).count, 2)
        // A tick stamped with the reading's own time (the frame that confirmed the swipe) counts for that reading.
        XCTAssertEqual(run(tick: 2.0).count, 2)
        // A tick before the last card is used up; one after the reading waits for a later reading.
        XCTAssertEqual(run(tick: 0.4).count, 1)
        XCTAssertEqual(run(tick: 9.0).count, 1)       // a tick after every reading is still waiting: it splits nothing here
        XCTAssertEqual(run(tick: .nan).count, 1)
    }

    /// The extension's order, with the real `SwipeDetector` and `SwipeTicker`: every frame goes through the signature
    /// and the ticker; a frame is read only if the reader is free (a card read keeps it busy `slow` ms, any other
    /// `fast` ms); the pending ticks are drained after the read, immediately before the reading is added.
    private struct SimFrame { var image: RGBAImage; var reading: FrameReading; var isCard: Bool }

    private func extensionSim(_ frames: [SimFrame], slow: Double, fast: Double, useTicks: Bool = true) -> (rows: [LiveRow], kept: Int) {
        var detector = SwipeDetector(), ticker = SwipeTicker(), g = LiveGrouper(species: table)
        var pending = [Double](), busyUntil = -1.0, kept = 0
        for (k, f) in frames.enumerated() {
            let t = Double(k) * 0.2
            if let tick = ticker.feed(diff: detector.feed(f.image), time: t), useTicks { pending.append(tick) }
            if t < busyUntil - 1e-9 { continue }
            busyUntil = t + (f.isCard ? slow : fast) / 1000
            kept += 1
            var r = f.reading; r.time = t
            for tick in pending { g.swipe(at: tick) }
            pending.removeAll()
            g.add(r)
        }
        for tick in pending { g.swipe(at: tick) }
        g.finish()
        return (g.rows, kept)
    }

    private static let cardImage: RGBAImage = { var i = RGBAImage(width: 300, height: 650); SyntheticScreen.draw(into: &i, SyntheticScreen.Spec(name: "Moltres", cp: 1984, hp: 140, ivs: IVs(atk: 15, def: 12, hp: 12))); return i }()
    private static let slideImage: RGBAImage = { var i = RGBAImage(width: 300, height: 650); SyntheticScreen.draw(into: &i, SyntheticScreen.Spec(name: "Moltres", cp: 1984, hp: 140, ivs: IVs(atk: 15, def: 12, hp: 12)), style: .padMuted); return i }()
    private static let blanks: [RGBAImage] = [40, 160, 70, 190].map { v in var i = RGBAImage(width: 300, height: 650); i.fill(Rect(x: 0, y: 0, w: 300, h: 650), (UInt8(v), UInt8(v), UInt8(v))); return i }

    /// A stream of cards `pace` seconds apart: each card on screen for `pace - 0.8` s, then a 0.8 s swipe: four blank
    /// moving frames, or (`slide`) one readable sliding frame of the old card and three blanks.
    private func simStream(pace: Double, cards: [FrameReading], slide: Bool) -> [SimFrame] {
        var out = [SimFrame]()
        for reading in cards {
            for _ in 0..<Int(((pace - 0.8) / 0.2).rounded()) { out.append(SimFrame(image: Self.cardImage, reading: reading, isCard: true)) }
            for k in 0..<4 {
                if slide && k == 0 { out.append(SimFrame(image: Self.slideImage, reading: reading, isCard: true)) }
                else { out.append(SimFrame(image: Self.blanks[k], reading: swipe(), isCard: false)) }
            }
        }
        return out
    }

    func testIdenticalNeighboursStayTwoRowsAtEveryPaceUnderEveryVisionModel() {
        func card(_ cp: Int, hp: Int, _ ivs: IVs) -> FrameReading { frame(cp, hp: hp, ivs: ivs, name: "Moltres") }
        let c = card(CP + 40, hp: HPV + 5, IVs(atk: 1, def: 2, hp: 3)), a = card(CP, hp: HPV, IVS), d = card(CP - 40, hp: HPV - 5, IVs(atk: 4, def: 5, hp: 6))
        for slide in [false, true] {
            for pace in [1.4, 1.6, 2.0, 2.4] {
                for (slow, fast) in [(0.0, 0.0), (250.0, 20.0), (450.0, 200.0), (650.0, 200.0)] {
                    let r = extensionSim(simStream(pace: pace, cards: [c, a, a, d, c], slide: slide), slow: slow, fast: fast)
                    let twins = r.rows.filter { $0.cp == CP }
                    let label = "slide \(slide) pace \(pace) model \(slow)/\(fast): \(r.rows.map { "\($0.cp as Any) \($0.flags)" })"
                    XCTAssertEqual(twins.count, 2, label)
                    XCTAssertEqual(r.rows.count, 5, label)
                    // Only a twin can be marked "reads like the one before it" (when only the tick saw the swipe).
                    XCTAssertTrue(r.rows.filter { $0.flags.contains("same-as-previous") }.allSatisfy { $0.cp == CP }, label)
                    XCTAssertLessThanOrEqual(r.rows.filter { $0.flags.contains("same-as-previous") }.count, 1, label)
                }
            }
        }
        // Without the signature the twins merge when the reader sees one frame in five: the test is about the ticks.
        XCTAssertEqual(extensionSim(simStream(pace: 1.4, cards: [c, a, a, d, c], slide: false), slow: 1000, fast: 1000, useTicks: false).rows.filter { $0.cp == CP }.count, 1)
    }

    func testAWeakNamedPokemonBetweenTwoOthersOrLastSurvivesDrops() {
        func strong(_ cp: Int, hp: Int, _ ivs: IVs) -> FrameReading { frame(cp, hp: hp, ivs: ivs, name: "Moltres") }
        let p = strong(CP + 40, hp: HPV + 5, IVs(atk: 1, def: 2, hp: 3)), q = strong(CP - 40, hp: HPV - 5, IVs(atk: 4, def: 5, hp: 6))
        let w = frame(210, hp: 41, ivs: nil, name: "Rattata", weak: true)
        for pace in [1.4, 1.6, 2.0, 2.4] {
            for (slow, fast) in [(0.0, 0.0), (250.0, 20.0), (450.0, 200.0), (650.0, 200.0)] {
                for order in [[p, w, q], [p, q, w]] {
                    let stream = simStream(pace: pace, cards: order, slide: false)
                    let r = extensionSim(stream, slow: slow, fast: fast)
                    // Survives whenever at least one of its readings was read (a card fully inside the busy gap is invisible).
                    var busyUntil = -1.0, weakRead = false
                    for (k, f) in stream.enumerated() {
                        let t = Double(k) * 0.2
                        if t < busyUntil - 1e-9 { continue }
                        busyUntil = t + (f.isCard ? slow : fast) / 1000
                        if f.reading.name == "Rattata" { weakRead = true }
                    }
                    if weakRead { XCTAssertTrue(r.rows.contains { $0.name == "Rattata" && $0.flags.contains("name-low-confidence") }, "pace \(pace) model \(slow)/\(fast) order \(order.map { $0.name ?? "" })") }
                }
            }
        }
    }

    /// A card of ANOTHER species sliding past is often read with only its name: two such frames are separator frames, not
    /// a card. (A name alone that is the name of the Pokémon on screen is neither: see the neutral-reading tests.)
    func testATwoFrameNameOnlySlideOfAnotherSpeciesBetweenIdenticalCardsIsASwipe() {
        func nameOnly(_ n: Int, _ name: String = "Zapdos") -> FrameReading { frame(nil, hp: nil, ivs: nil, name: name, n: n) }
        let a = (1...4).map { frame(CP, n: $0) }, b = (10...13).map { frame(CP, n: $0) }
        let rows = groupAll(a + [swipe(), nameOnly(6), nameOnly(7)] + b)
        XCTAssertEqual(rows.filter { $0.cp == CP }.count, 2)
        XCTAssertFalse(rows.contains { $0.flags.contains("cp-not-read") }, "a two-frame slide is not listed as a card")
        // The same frames as 5 name-only readings (1.0 s with the same name) are a card.
        XCTAssertTrue(groupAll(a + swipes() + (6...10).map { nameOnly($0) } + swipes() + b).contains { $0.name == "Zapdos" && $0.flags.contains("cp-not-read") })
    }

    /// A run started only by a tick that reads like the row before it is marked, so a false split is never unflagged.
    func testATickOnlySplitThatReadsLikeThePreviousRowIsMarked() {
        func at(_ r: FrameReading, _ t: Double) -> FrameReading { var x = r; x.time = t; return x }
        func run(tick: Bool, secondHp: Int, separators: Bool = false) -> [LiveRow] {
            var g = LiveGrouper(species: table)
            for k in 0..<4 { g.add(at(frame(CP, n: k), Double(k) * 0.2)) }
            if tick { g.swipe(at: 1.5) }
            if separators { for k in 0..<4 { g.add(at(swipe(), 0.8 + Double(k) * 0.2)) } }
            for k in 0..<4 { g.add(at(frame(CP, hp: secondHp, n: 10 + k), 2.0 + Double(k) * 0.2)) }
            g.finish()
            return g.rows
        }
        let same = run(tick: true, secondHp: HPV)
        XCTAssertEqual(same.count, 2)
        XCTAssertFalse(same[0].flags.contains("same-as-previous"))
        XCTAssertTrue(same[1].flags.contains("same-as-previous"))
        // Seen by separator frames as well: not tick-only, no mark. A different HP is plainly another Pokémon.
        XCTAssertFalse(run(tick: true, secondHp: HPV, separators: true)[1].flags.contains("same-as-previous"))
        XCTAssertFalse(run(tick: true, secondHp: HPV + 6)[1].flags.contains("same-as-previous"))
    }

    func testLongStayIsFlaggedAtExactlyTheLimitWhateverTheTimestampBase() {
        for base in [0.0, 1234.567, 98765.4321] {
            var g = LiveGrouper(species: table)
            for k in 0..<12 { var r = frame(CP, n: k); r.time = base + Double(k) * 0.2; g.add(r) }   // 11 intervals + a period = 2.4 s
            g.finish()
            XCTAssertTrue(g.rows[0].flags.contains("long-stay"), "base \(base): \(g.rows[0].flags)")
        }
    }

    func testSexInferredWithNoHpIsFlagged() throws {
        // A level and bars at which the male's stats fit a CP and the female's do not (found, not assumed).
        let male = table.byId["nidoran_male"]!, female = table.byId["nidoran_female"]!
        var found: (cp: Int, ivs: IVs)?
        search: for atk in [3, 9, 14] { for def in [2, 10, 15] { for hp in [4, 13] { for level in stride(from: 5.0, through: 30.0, by: 2.5) {
            let ivs = IVs(atk: atk, def: def, hp: hp), cp = cpAt(male.baseStats, ivs, level)
            if cpFits([male], cp: cp, hp: nil, ivs: ivs) == true && cpFits([female], cp: cp, hp: nil, ivs: ivs) == false { found = (cp, ivs); break search }
        } } } }
        let f = try XCTUnwrap(found, "no input reaches the flag")
        func nido(_ n: Int) -> FrameReading { var r = frame(f.cp, hp: nil, ivs: f.ivs, name: "Nidoran", n: n); r.speciesIds = ["nidoran_female", "nidoran_male"]; return r }
        let rows = groupAll((1...4).map(nido))
        XCTAssertEqual(rows[0].name, "Nidoran♂")
        XCTAssertTrue(rows[0].flags.contains("sex-from-stats-no-hp"), "\(rows[0].flags)")
        XCTAssertFalse(rows[0].flags.contains("sex-not-read"))
    }

    // MARK: grouper pass (tick acceptance, carry-over, same-as-previous at close, separator edge cases)

    /// A swipe that leaves only TWO non-card readings at full rate: the first swipe frame still reads the old card (it
    /// is sliding), the next two are blank, the fourth already reads the new card. 0.6 s between the two cards.
    private func twoSeparatorStream(pace: Double, cards: [FrameReading]) -> [SimFrame] {
        var out = [SimFrame]()
        for reading in cards {
            for _ in 0..<Int(((pace - 0.6) / 0.2).rounded()) { out.append(SimFrame(image: Self.cardImage, reading: reading, isCard: true)) }
            out.append(SimFrame(image: Self.slideImage, reading: reading, isCard: true))
            out.append(SimFrame(image: Self.blanks[1], reading: swipe(), isCard: false))
            out.append(SimFrame(image: Self.blanks[2], reading: swipe(), isCard: false))
        }
        return out
    }

    func testTwinsWithATwoSeparatorSwipeStayTwoRowsAtFullRateAtEveryPace() {
        func card(_ cp: Int, hp: Int, _ ivs: IVs) -> FrameReading { frame(cp, hp: hp, ivs: ivs, name: "Moltres") }
        let c = card(CP + 40, hp: HPV + 5, IVs(atk: 1, def: 2, hp: 3)), a = card(CP, hp: HPV, IVS), d = card(CP - 40, hp: HPV - 5, IVs(atk: 4, def: 5, hp: 6))
        for pace in [1.4, 1.6, 2.0, 2.4] {
            for (slow, fast) in [(0.0, 0.0), (250.0, 20.0), (450.0, 200.0), (650.0, 200.0)] {
                let r = extensionSim(twoSeparatorStream(pace: pace, cards: [c, a, a, d, c]), slow: slow, fast: fast)
                let label = "pace \(pace) model \(slow)/\(fast): \(r.rows.map { "\($0.cp as Any) \($0.flags)" })"
                XCTAssertEqual(r.rows.filter { $0.cp == CP }.count, 2, label)
                XCTAssertEqual(r.rows.count, 5, label)
            }
        }
        // The ticks are what separate them: without the signature the pair merges at full rate.
        XCTAssertEqual(extensionSim(twoSeparatorStream(pace: 1.6, cards: [c, a, a, d, c]), slow: 0, fast: 0, useTicks: false).rows.filter { $0.cp == CP }.count, 1)
    }

    /// Two card readings one frame period apart cannot hold a swipe (0.6 s at the least): a tick between them is a jump
    /// inside one Pokémon's stay and must not split it, at any reading rate that shows every frame.
    func testATickBetweenCardReadingsOnePeriodApartDoesNotSplit() {
        func at(_ r: FrameReading, _ t: Double) -> FrameReading { var x = r; x.time = t; return x }
        var g = LiveGrouper(species: table)
        for k in 0..<10 {
            if k == 5 { g.swipe(at: 0.9) }                       // confirmed between the readings at 0.8 and 1.0
            g.add(at(frame(CP, n: k), Double(k) * 0.2))
        }
        g.finish()
        XCTAssertEqual(g.rows.count, 1)
        // The same tick over a silence long enough for a swipe (0.6 s) does split.
        var h = LiveGrouper(species: table)
        for k in 0..<4 { h.add(at(frame(CP, n: k), Double(k) * 0.2)) }
        h.swipe(at: 1.0)
        for k in 0..<4 { h.add(at(frame(CP, n: 10 + k), 1.4 + Double(k) * 0.2)) }   // 0.8 s after the last card at 0.6
        h.finish()
        XCTAssertEqual(h.rows.count, 2)
    }

    /// A swipe seen while the next readings are not strong runs (a hidden-CP card, a CP-only unnamed card, a weak name)
    /// still ends the run at the next strong reading.
    func testASwipeCarriesOverACardReadingThatStartsNoRun() {
        func at(_ r: FrameReading, _ t: Double) -> FrameReading { var x = r; x.time = t; return x }
        let hiddenReading = frame(nil, hp: HPV, ivs: IVS, name: "Moltres")
        var onlyCp = FrameReading(frame: "u", time: 0); onlyCp.cp = CP; onlyCp.cpReads = [CP]
        let weakReading = frame(CP, hp: HPV, ivs: IVS, name: "Moltres", weak: true)
        for (label, between) in [("hidden", hiddenReading), ("cp-only", onlyCp), ("weak", weakReading)] {
            var g = LiveGrouper(species: table)
            for k in 0..<4 { g.add(at(frame(CP, n: k), Double(k) * 0.2)) }              // the old card, last read at 0.6
            g.swipe(at: 1.4)
            g.add(at(between, 1.8))                                                      // the swipe is seen here, on a reading that starts no run
            g.add(at(frame(CP, n: 20), 2.0))                                              // the next strong reading reads exactly like the old card
            g.add(at(frame(CP, n: 21), 2.2))
            g.finish()
            // Two strong rows at the old card's CP: the old card, and the next card that reads exactly like it (the card reading
            // between them that started no run is its own listed row or none, never part of the old card).
            XCTAssertEqual(g.rows.filter { $0.cp == CP && !$0.flags.contains { $0.hasPrefix("cp-") || $0.hasPrefix("name-") } }.count, 2, "\(label): \(g.rows.map { "\($0.cp as Any) \($0.flags)" })")
        }
    }

    /// `same-as-previous` is decided from the voted values of both rows when the run closes.
    func testSameAsPreviousIsDecidedFromTheVotedValuesNotTheFirstReading() {
        func at(_ r: FrameReading, _ t: Double) -> FrameReading { var x = r; x.time = t; return x }
        func run(firstCp: Int, firstHp: Int?? = nil, secondHp: Int, secondCp: Int) -> [LiveRow] {
            var g = LiveGrouper(species: table)
            for k in 0..<4 { g.add(at(frame(CP, n: k), Double(k) * 0.2)) }
            g.swipe(at: 1.4)
            g.add(at(frame(firstCp, hp: firstHp ?? secondHp, ivs: IVS, n: 10), 2.0))           // the first reading of the new run, perhaps garbled
            for k in 1..<5 { g.add(at(frame(secondCp, hp: secondHp, ivs: IVS, n: 10 + k), 2.0 + Double(k) * 0.2)) }
            g.finish()
            return g.rows
        }
        // A garbled first read (19 for 2409) of an identical Pokémon: the voted values match the row before, so it is marked.
        let garbled = run(firstCp: 19, secondHp: HPV, secondCp: CP)
        XCTAssertEqual(garbled.count, 2)
        XCTAssertTrue(garbled[1].flags.contains("same-as-previous"), "\(garbled[1].flags)")
        // The first reads like the row before but the voted HP and CP are another Pokémon's: not marked.
        // The first reading looks identical to the row before (same CP, HP unread); the later readings vote another HP.
        let other = run(firstCp: CP, firstHp: .some(nil), secondHp: HPV + 7, secondCp: CP)
        XCTAssertEqual(other.count, 2)
        XCTAssertFalse(other[1].flags.contains("same-as-previous"), "\(other[1].flags)")
        // A run started by separator frames (no tick) is not marked.
        var g = LiveGrouper(species: table)
        for k in 0..<4 { g.add(at(frame(CP, n: k), Double(k) * 0.2)) }
        for k in 0..<4 { g.add(at(swipe(), 0.8 + Double(k) * 0.2)) }
        for k in 0..<4 { g.add(at(frame(CP, n: 10 + k), 1.6 + Double(k) * 0.2)) }
        g.finish()
        XCTAssertEqual(g.rows.count, 2)
        XCTAssertFalse(g.rows[1].flags.contains("same-as-previous"))
    }

    /// A short name-only reading of the Pokémon on screen is no separator evidence: unreadable@0, name-only@0.4, CP@0.8.
    func testAShortNameOnlyReadingOfTheCurrentPokemonDoesNotChainSeparators() {
        func at(_ r: FrameReading, _ t: Double) -> FrameReading { var x = r; x.time = t; return x }
        var g = LiveGrouper(species: table)
        for k in 0..<3 { g.add(at(frame(CP, n: k), Double(k) * 0.4)) }                       // 0, 0.4, 0.8
        g.add(at(swipe(), 1.2))                                                              // unreadable
        g.add(at(frame(nil, hp: nil, ivs: nil, name: "Moltres", n: 9), 1.6))                 // name only, the same Pokémon
        g.add(at(frame(CP, n: 10), 2.0))                                                     // read again
        g.finish()
        XCTAssertEqual(g.rows.count, 1, "\(g.rows.map { "\($0.cp as Any) \($0.flags)" })")
    }

    func testTwoIsolatedNameOnlyReadingsMoreThanASecondApartMakeNoCardRow() {
        func at(_ r: FrameReading, _ t: Double) -> FrameReading { var x = r; x.time = t; return x }
        var g = LiveGrouper(species: table)
        for k in 0..<4 { g.add(at(frame(CP, name: "Zapdos", n: k), Double(k) * 0.2)) }
        g.add(at(frame(nil, hp: nil, ivs: nil, name: "Moltres", n: 9), 3.0))
        g.add(at(frame(nil, hp: nil, ivs: nil, name: "Moltres", n: 10), 4.6))                // 1.6 s later: another moment, not the same card
        g.add(at(frame(CP, name: "Zapdos", n: 20), 6.0))
        g.finish()
        XCTAssertFalse(g.rows.contains { $0.name == "Moltres" }, "\(g.rows.map { "\($0.name) \($0.flags)" })")
    }



    // MARK: narrow round (hidden same-species Pokémon, unnamed carry, tests that reach their case)

    /// A Pokémon of the same species as the one before it whose CP and HP are unread for its whole stay: its name-only
    /// readings are the new Pokémon's, not the old one's, and the stretch is listed (`cp-not-read`).
    func testASameSpeciesPokemonWithCpAndHpHiddenIsListedAfterBlanksOrATick() {
        func at(_ r: FrameReading, _ t: Double) -> FrameReading { var x = r; x.time = t; return x }
        let nameOnly = frame(nil, hp: nil, ivs: nil, name: "Moltres")
        for useTick in [false, true] {
            var g = LiveGrouper(species: table)
            for k in 0..<4 { g.add(at(frame(CP, n: k), Double(k) * 0.2)) }                      // Moltres 0 - 0.6
            if useTick { g.swipe(at: 1.4) } else { for k in 0..<3 { g.add(at(swipe(), 0.8 + Double(k) * 0.2)) } }
            for k in 0..<6 { g.add(at(nameOnly, 1.4 + Double(k) * 0.2)) }                         // Moltres name only 1.4 - 2.4
            if !useTick { for k in 0..<3 { g.add(at(swipe(), 2.6 + Double(k) * 0.2)) } } else { g.swipe(at: 2.8) }
            for k in 0..<4 { g.add(at(frame(CP - 300, hp: HPV + 9, ivs: IVs(atk: 4, def: 5, hp: 6), name: "Zapdos", n: 30 + k), 3.2 + Double(k) * 0.2)) }
            g.finish()
            let label = "tick \(useTick): \(g.rows.map { "\($0.name) \($0.cp as Any) \($0.flags)" })"
            XCTAssertEqual(g.rows.map(\.name), ["Moltres", "Moltres", "Zapdos"], label)
            XCTAssertTrue(g.rows[1].flags.contains("cp-not-read"), label)
        }
    }

    /// The first readings of the new Pokémon have a CP but no name: it is one row, not a row and a "(name not read)" one.
    func testANewPokemonWhoseFirstReadingsHaveNoNameMakesNoUnnamedRow() {
        func at(_ r: FrameReading, _ t: Double) -> FrameReading { var x = r; x.time = t; return x }
        var g = LiveGrouper(species: table)
        for k in 0..<4 { g.add(at(frame(CP - 800, hp: HPV + 5, ivs: IVs(atk: 1, def: 2, hp: 3), n: k), Double(k) * 0.2)) }   // A (a CP unrelated to B's)
        for k in 0..<4 { g.add(at(swipe(), 0.8 + Double(k) * 0.2)) }                                                          // swipe
        for k in 0..<2 { var r = FrameReading(frame: "u\(k)", time: 0); r.cp = CP; r.cpReads = [CP]; g.add(at(r, 1.6 + Double(k) * 0.2)) }  // B, CP only
        for k in 0..<4 { g.add(at(frame(CP, n: 20 + k), 2.0 + Double(k) * 0.2)) }                                            // B, strong
        g.finish()
        XCTAssertEqual(g.rows.count, 2, "\(g.rows.map { "\($0.name) \($0.cp as Any) \($0.flags)" })")
        XCTAssertFalse(g.rows.contains { $0.name == "(name not read)" }, "\(g.rows.map { "\($0.name) \($0.cp as Any) \($0.flags) f\($0.frames)" })")
    }

    /// KNOWN LIMIT, not a goal: a swipe that leaves ONE blank reading (the old card still readable on the first changed
    /// frame, one blank, the new card on the third) is 0.4 s between the bracketing card readings, too short for the tick
    /// rule and too few separator frames, so two identical Pokémon merge at full rate. The row is flagged `long-stay` only
    /// when the merged stay reaches 2.4 s: at a 2.1 s pace it is, at a 1.2 s pace it is not and carries no flag.
    func testKnownLimitOneSeparatorSwipeMergesIdenticalNeighboursAtFullRate() {
        func card(_ cp: Int, hp: Int, _ ivs: IVs) -> FrameReading { frame(cp, hp: hp, ivs: ivs, name: "Moltres") }
        let c = card(CP + 40, hp: HPV + 5, IVs(atk: 1, def: 2, hp: 3)), a = card(CP, hp: HPV, IVS), d = card(CP - 40, hp: HPV - 5, IVs(atk: 4, def: 5, hp: 6))
        func stream(cardFrames n: Int) -> [SimFrame] {
            var out = [SimFrame]()
            for reading in [c, a, a, d] {
                for _ in 0..<n { out.append(SimFrame(image: Self.cardImage, reading: reading, isCard: true)) }
                out.append(SimFrame(image: Self.slideImage, reading: reading, isCard: true))     // first changed frame, still readable
                out.append(SimFrame(image: Self.blanks[1], reading: swipe(), isCard: false))     // one blank; the next card is the third frame
            }
            return out
        }
        for (n, flagged) in [(4, false), (9, true)] {          // 1.2 s and 2.2 s per Pokémon
            let r = extensionSim(stream(cardFrames: n), slow: 0, fast: 0)
            let twins = r.rows.filter { $0.cp == CP }
            XCTAssertEqual(twins.count, 1, "\(n): the twins merge (known limit)")
            XCTAssertEqual(twins.first?.flags.contains("long-stay"), flagged, "\(n) card frames: \(twins.first?.flags ?? [])")
        }
    }


    func testNidorinaRunIsNotInterruptedByANidoranWithALetterStuckToIt() {
        func nidorina(_ n: Int) -> FrameReading { frame(500, hp: 70, ivs: nil, name: "Nidorina", n: n) }
        var stray = frame(500, hp: 70, ivs: nil, name: "Nidoran", n: 3); stray.nameAttached = true
        XCTAssertEqual(groupAll([nidorina(1), nidorina(2), stray, nidorina(4)]).count, 1)
    }
}
