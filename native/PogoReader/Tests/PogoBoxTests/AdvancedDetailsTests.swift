import XCTest
@testable import PogoBox

/// Pass 3, rules 17 and 18: the advanced details' option lists and defaults, from the bundled game master.
final class AdvancedDetailsTests: XCTestCase {
    private let gm = P23.gm
    typealias D = AdvancedDetails

    func testMoveListsAreTheSpeciesOwnWithEliteFlags() {
        let fast = D.fastMoves(of: "eevee", gm: gm), charged = D.chargedMoves(of: "eevee", gm: gm)
        XCTAssertEqual(fast.map(\.id), ["QUICK_ATTACK", "TACKLE"])
        XCTAssertEqual(fast.map(\.name), ["Quick Attack", "Tackle"])
        XCTAssertEqual(fast.map(\.type), ["normal", "normal"])
        XCTAssertEqual(charged.map(\.id), ["BODY_SLAM", "DIG", "LAST_RESORT", "SWIFT"])
        XCTAssertEqual(charged.map(\.elite), [true, false, true, false], "Body Slam and Last Resort are in eliteMoves")
        XCTAssertEqual(fast.map(\.elite), [false, false])
        XCTAssertEqual(D.fastMoves(of: "not_a_species", gm: gm), [])
        XCTAssertEqual(D.chargedMoves(of: "not_a_species", gm: gm), [])
    }

    func testDefaultsAreTheFirstFastAndTheFirstNonEliteCharged() {
        XCTAssertEqual(D.defaults(of: "eevee", gm: gm), D.Defaults(fast: "QUICK_ATTACK", charged1: "DIG", charged2: nil))
        XCTAssertEqual(D.defaults(of: "not_a_species", gm: gm), D.Defaults(fast: nil, charged1: nil, charged2: nil))
        // A species whose charged moves are all Elite falls back to the first.
        let all = gm.byId.values.first { s in !s.chargedMoves.isEmpty && Set(s.chargedMoves).isSubset(of: Set(s.eliteMoves)) }
        if let all { XCTAssertEqual(D.defaults(of: all.id, gm: gm).charged1, all.chargedMoves.first) }
    }

    func testTheSecondChargedMoveNeverEqualsTheFirst() {
        XCTAssertEqual(D.secondChargedOptions(of: "eevee", first: "DIG", gm: gm).map(\.id), ["BODY_SLAM", "LAST_RESORT", "SWIFT"])
        XCTAssertEqual(D.firstChargedOptions(of: "eevee", second: "SWIFT", gm: gm).map(\.id), ["BODY_SLAM", "DIG", "LAST_RESORT"])
        XCTAssertEqual(D.secondChargedOptions(of: "eevee", first: nil, gm: gm).count, 4, "no first chosen: all four")
        let n = D.normalised(D.Defaults(fast: "TACKLE", charged1: "DIG", charged2: "DIG"), speciesId: "eevee", gm: gm)
        XCTAssertEqual(n, D.Defaults(fast: "TACKLE", charged1: "DIG", charged2: nil), "an equal second is Not unlocked")
        let stale = D.normalised(D.Defaults(fast: "AIR_SLASH", charged1: "BLAST_BURN", charged2: "SWIFT"), speciesId: "eevee", gm: gm)
        XCTAssertEqual(stale, D.Defaults(fast: "QUICK_ATTACK", charged1: "DIG", charged2: "SWIFT"), "a move the species cannot learn becomes the default")
        XCTAssertEqual(D.normalised(D.Defaults(fast: nil, charged1: nil, charged2: "ZAP"), speciesId: "eevee", gm: gm), D.Defaults(fast: "QUICK_ATTACK", charged1: "DIG", charged2: nil))
    }

    func testMaxAttackNameFollowsTheFastMovesType() {
        XCTAssertEqual(D.maxAttackNames.count, 18)
        XCTAssertEqual(Set(D.maxAttackNames.keys), Set(HubData.typeOrder), "one name per type")
        XCTAssertEqual(Set(D.maxAttackNames.values).count, 18)
        XCTAssertEqual(D.maxAttackName(fastMove: "EMBER", speciesId: "charizard", gm: gm), "Max Flare")
        XCTAssertEqual(D.maxAttackName(fastMove: "AIR_SLASH", speciesId: "charizard", gm: gm), "Max Airstream", "the fast move's type, not the species'")
        XCTAssertEqual(D.maxAttackName(fastMove: nil, speciesId: "vaporeon", gm: gm), "Max Geyser", "no fast move: the species' first type")
        XCTAssertEqual(D.maxAttackName(fastMove: nil, speciesId: "not_a_species", gm: gm), "Max Strike")
        XCTAssertEqual(D.maxAttackName(fastMove: "TACKLE", speciesId: "eevee", gm: gm), "Max Strike")
        XCTAssertEqual(D.maxAttackLevels, [1, 2, 3]); XCTAssertEqual(D.maxGuardLevels, [0, 1, 2, 3]); XCTAssertEqual(D.maxSpiritLevels, [0, 1, 2, 3])
    }

    func testMaxMovesShowOnlyWhileTheDynamaxMarkIsOn() {
        XCTAssertTrue(D.showsMaxMoves(dynamax: true))
        XCTAssertFalse(D.showsMaxMoves(dynamax: false))
        XCTAssertFalse(D.showsMaxMoves(dynamax: nil))
    }

    func testTheMegaLevelShowsOnlyForASpeciesWithAMegaForm() {
        XCTAssertEqual(D.megaForms(of: "charizard", gm: gm), ["Charizard (Mega X)", "Charizard (Mega Y)"], "the game master's names")
        XCTAssertEqual(D.megaForms(of: "kyogre", gm: gm).count, 1, "a Primal form counts")
        XCTAssertEqual(D.megaForms(of: "lucario", gm: gm), ["Lucario (Mega)"])
        XCTAssertTrue(D.showsMegaLevel(speciesId: "lucario", gm: gm))
        XCTAssertFalse(D.showsMegaLevel(speciesId: "vaporeon", gm: gm))
        XCTAssertFalse(D.showsMegaLevel(speciesId: "charmander", gm: gm), "only the species with the entry, not its family")
        XCTAssertFalse(D.showsMegaLevel(speciesId: "not_a_species", gm: gm))
        XCTAssertEqual(D.MegaLevel.allCases.map(\.title), ["Not yet", "Base", "High", "Max"])
        XCTAssertEqual(D.marks, ["Lucky", "Purified", "Best Buddy", "Weather-boosted"])
    }
}
