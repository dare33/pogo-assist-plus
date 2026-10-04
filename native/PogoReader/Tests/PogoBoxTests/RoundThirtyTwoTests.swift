import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// Round 32: the findings of two reviews of round 31. CE1 to CE6 are the reviewer's constructed counter-examples (CE2 to CE4 rebuilt from the probe, CE5 and CE6 from the findings); each of
/// these tests failed on `601e6db` (the mutation that restores the old behaviour is named beside it) and passes now.
final class RoundThirtyTwoTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private func date(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(d) * 86_400) }
    private let hint = PagingHint(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds)
    private func ivs(_ a: Int, _ d: Int, _ h: Int) -> IVs { IVs(atk: a, def: d, hp: h) }
    private func entry(_ id: String, _ species: String, cp: Int, hp: Int, _ iv: IVs?) -> BoxEntry {
        let nf = GameMaster.nameAndForm(gm.byId[species]?.name ?? species)
        let r = ScanRow(index: 0, name: nf.name, display: nf.name, form: nf.form, speciesId: species, dex: gm.byId[species]?.dex, cp: cp, hp: hp, ivs: iv, ivsRead: iv, ivsGuess: nil, level: 20, levelMax: 20, dust: 0,
                        solveStatus: "exact", flags: [], frames: [])
        return BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0))
    }
    private func pidgey(_ i: Int, cp: Int, t: Double) -> ScanRow {
        ScanRow(index: i, name: "Pidgey", display: "Pidgey", form: "", speciesId: "pidgey", dex: 16, cp: cp, hp: 50, ivs: ivs(1, 2, 3), ivsRead: ivs(1, 2, 3), ivsGuess: nil, level: 20, levelMax: 20, dust: 0, solveStatus: "exact", flags: [],
                frames: stride(from: t, through: t + 0.8, by: 0.4).map { FrameLabel(frame: "c\(i)_\($0)", time: $0, cp: cp, cpText: "\(cp)", name: "Pidgey", hp: "50/50", ivs: "1/2/3", ivConfidence: 0.9, sharpness: 1, clip: nil) })
    }
    /// 30 rows in CP order (descending from 3000 by 10), a card every 1.2 s.
    private func orderedRows() -> [ScanRow] { (0..<30).map { pidgey($0, cp: 3000 - $0 * 10, t: 10 + Double($0) * 1.2) } }
    private func box(_ rows: [ScanRow], _ extra: [BoxEntry]) -> [BoxEntry] { rows.enumerated().map { BoxEntry(id: "row\($0.offset)", row: $0.element, firstSeen: date(0), lastSeen: date(0)) } + extra }
    private func plan(_ rows: [ScanRow], _ items: [Unmatched], _ b: [BoxEntry], kind: BoxStore.Kind = .full) -> BoxMerge.Plan {
        BoxMerge.plan(scanned: rows, unmatched: items, into: b, kind: kind, scanDate: date(1), gameMaster: gm)
    }
    private func stationedItem(_ name: String, _ ids: [String], _ b: IVs?, before: Int, after: Int, stretch: Int? = nil) -> Unmatched {
        Unmatched(frame: "a", cp: nil, name: name, nameText: nil, hp: nil, ivs: b, cpOptions: nil, frames: 6, reason: StationedCards.reason, into: nil, clip: nil, count: 1, cpBefore: before, cpAfter: after, speciesIds: ids, stretch: stretch)
    }
    private func blankItem(count: Int = 1, before: Int, after: Int, stretch: Int? = nil) -> Unmatched {
        Unmatched(frame: "b", cp: nil, name: nil, nameText: nil, hp: nil, ivs: nil, cpOptions: nil, frames: count * 6, reason: BlankCards.reason, into: nil, clip: nil, count: count, cpBefore: before, cpAfter: after, stretch: stretch)
    }

    // MARK: 1. the lenient bars split

    /// CE1: one Fidough held 11.6 s inside a recorded pause whose weak bars (confidence 0.65) flip once. One Pokémon. Mutation: drop `!touchesPause` and the one-period part test in `RefineBars`.
    func testCE1AWeakBarsFlipInsideAPauseOrAHeldCardDoesNotSplit() throws {
        let l = try ReplayReadings.load(url: Fixture.url("run23-fidough-twin.replay.jsonl"))
        let fid = l.readings.indices.filter { l.readings[$0].name == "Fidough" && l.readings[$0].cp == 768 }
        let t0 = l.readings[fid.first!].time!, tEnd = l.readings[fid.last!].time!
        let template = l.readings[fid.first!]
        var out = [FrameReading]()
        for r in l.readings where r.time! < t0 { out.append(r) }
        for k in 0..<30 {
            var r = template; r.time = t0 + Double(k) * 0.4; r.frame = "x\(k)"
            r.ivs = k < 3 ? ivs(15, 4, 10) : ivs(15, 5, 10); r.ivConfidence = 0.65
            out.append(r)
        }
        for r in l.readings where r.time! > tEnd { var x = r; x.time! += 9.6; out.append(x) }
        for i in out.indices { out[i].frame = "r\(i)" }
        var paused = hint; paused.pauses = [(t0 + 3)...(t0 + 11)]
        for (label, h) in [("hint and pause", paused), ("hint, held 11.6 s", hint)] {
            let base = try sharedEngine.finish(readings: out)
            let r = try Refine.apply(to: base, readings: out, ticks: l.ticks, engine: sharedEngine, paging: h)
            XCTAssertEqual(r.scan.rows.filter { $0.display == "Fidough" && $0.cp == 768 }.count, 1, "\(label): one Pokémon is one row")
            XCTAssertFalse(r.scan.rows.contains { $0.flags.contains("split-by-bars") && $0.display == "Fidough" }, label)
        }
    }

    /// The pause rule on its own: the real Fidough twin (two parts of one period each, bars below the settled confidence) splits on the beat; with a recorded pause over it the same readings are one
    /// Pokémon held, and it does not. Mutation: drop `!touchesPause` (alone, the one-period test does not catch this, the parts are right).
    func testTheRealFidoughTwinSplitsButNotInsideAPause() throws {
        let l = try ReplayReadings.load(url: Fixture.url("run23-fidough-twin.replay.jsonl"))
        let fid = l.readings.indices.filter { l.readings[$0].name == "Fidough" && l.readings[$0].cp == 768 }
        let t0 = l.readings[fid.first!].time!, tEnd = l.readings[fid.last!].time!
        func rows(_ h: PagingHint) throws -> Int {
            let base = try sharedEngine.finish(readings: l.readings)
            return try Refine.apply(to: base, readings: l.readings, ticks: l.ticks, engine: sharedEngine, paging: h).scan.rows.filter { $0.display == "Fidough" && $0.cp == 768 }.count
        }
        XCTAssertEqual(try rows(hint), 2, "control: the twin splits")
        var paused = hint; paused.pauses = [(t0 - 0.5)...(tEnd + 0.5)]
        XCTAssertEqual(try rows(paused), 1, "a row inside a recorded pause is never cut by the lenient path")
    }

    // MARK: 2. stationed items

    private func reading(_ t: Double, _ name: String?, bars: IVs?, confidence: Double = 0.9) -> FrameReading {
        var r = FrameReading(frame: "s\(Int((t * 100).rounded()))", time: t)
        guard let name else { return r }
        r.name = name; r.speciesIds = [name.lowercased()]; r.nameText = name; r.flags = ["stationed"]
        if let bars { r.ivs = bars; r.ivConfidence = confidence }
        return r
    }
    private func normal(_ t: Double, cp: Int) -> FrameReading { var r = FrameReading(frame: "c\(Int((t * 100).rounded()))", time: t); r.nameText = "Pidgey"; r.cpText = "CP\(cp)"; r.hpText = "50 / 50 HP"; return r }
    private func rowAt(_ index: Int, cp: Int, from a: Double, to b: Double) -> ScanRow {
        var r = pidgey(index, cp: cp, t: a)
        r.frames = stride(from: a, through: b, by: 0.4).map { FrameLabel(frame: "c\(Int(($0 * 100).rounded()))", time: $0, cp: cp, cpText: "\(cp)", name: "Pidgey", hp: "50/50", ivs: "1/2/3", ivConfidence: 0.9, sharpness: 1, clip: nil) }
        return r
    }
    /// A stretch between two Pidgey rows (900 before, 800 after), a reading per 0.2 s step from `start`.
    private func stretch(_ spec: [(String?, IVs?)], start: Double = 11.0) -> (readings: [FrameReading], rows: [ScanRow]) {
        var rs = stride(from: 10.0, through: 10.8, by: 0.4).map { normal($0, cp: 900) }
        for (k, s) in spec.enumerated() { rs.append(reading(start + Double(k) * 0.2, s.0, bars: s.1)) }
        let end = start + Double(spec.count) * 0.2
        rs += stride(from: end, through: end + 0.8, by: 0.4).map { normal($0, cp: 800) }
        return (rs, [rowAt(1, cp: 900, from: 10, to: 10.8), rowAt(2, cp: 800, from: end, to: end + 0.8)])
    }
    private func items(_ spec: [(String?, IVs?)]) -> [Unmatched] { let s = stretch(spec); return BlankCards.find(readings: s.readings, rows: s.rows, paging: hint) }

    /// CE5: a stationed card whose readings alternate with blank ones (the reader loses the card every other frame) is ONE item with its bars. Mutation: drop the flicker fill in `StationedCards.items`.
    func testCE5ABlankBetweenTwoReadingsOfOneCardIsPartOfThatCard() {
        let a = ivs(11, 14, 12)
        let one = items([("Zapdos", a), (nil, nil), ("Zapdos", a), (nil, nil), ("Zapdos", a), (nil, nil)])
        XCTAssertEqual(one.map(\.reason), [StationedCards.reason]); XCTAssertEqual(one.first?.ivs, a); XCTAssertEqual(one.first?.name, "Zapdos")
        // a gap of a card's length between two Zapdos is not flicker: the blank stretch between them is its own card
        let gap = items([("Zapdos", a), ("Zapdos", a), ("Zapdos", a), ("Zapdos", a), ("Zapdos", a), ("Zapdos", a)] + Array(repeating: (nil, nil), count: 6) + Array(repeating: ("Zapdos", a), count: 6))
        XCTAssertEqual(gap.map(\.reason), [StationedCards.reason, BlankCards.reason, StationedCards.reason])
    }

    /// CE6: the first readings of a card, still the previous card's bars moving to its own (two readings, equal, above the settled confidence), are part of that card: one item, the bars that held.
    /// Mutation: restore the one-state-per-two-readings rule in `cutByBars` (drop the `minimumLength` loop).
    func testCE6TheFirstReadingsOfACardWithOtherBarsBelongToThatCard() {
        let a = ivs(11, 14, 12), b = ivs(15, 14, 13)
        for lead in 1...3 {
            let r = items(Array(repeating: ("Zapdos", b), count: lead) + Array(repeating: ("Zapdos", a), count: 6 - lead))
            XCTAssertEqual(r.map(\.ivs), [a], "\(lead) leading readings: one card, the bars it settled on")
            XCTAssertEqual(r.map(\.frames), [6])
        }
        // the same at the end of the card
        XCTAssertEqual(items(Array(repeating: ("Zapdos", a), count: 4) + Array(repeating: ("Zapdos", b), count: 2)).map(\.ivs), [a])
        // two cards of whole periods each are still cut at the change (round 31c)
        XCTAssertEqual(items(Array(repeating: ("Zapdos", a), count: 6) + Array(repeating: ("Zapdos", b), count: 6)).map(\.ivs), [a, b])
    }

    /// A part under 0.8 of a period is not forced to a card: a short run of a name beside nothing of its name is nothing, as a short stretch of one name always was.
    /// Mutation: restore `n = max(1, n)`.
    func testAShortStationedPartIsNotForcedToACard() {
        let a = ivs(11, 14, 12)
        let r = items(Array(repeating: ("Zapdos", a), count: 6) + Array(repeating: (nil, nil), count: 5) + Array(repeating: ("Zapdos", a), count: 2))
        XCTAssertEqual(r.map(\.reason), [StationedCards.reason, BlankCards.reason], "the two Zapdos readings after the blank stretch are the transition, not a card")
    }

    // MARK: 3. the match

    /// CE2: the card's bars read one notch off. The box holds the real stationed Zapdos (13/14/13) and another Zapdos (13/14/14) the owner transferred; the card reads 13/14/14. Mutation: drop the
    /// near-neighbour refusal in `matchStationed`.
    func testCE2ANearNeighbourRefusesTheMatch() {
        let rows = orderedRows()
        let b = box(rows, [entry("real1989", "zapdos", cp: 1989, hp: 132, ivs(13, 14, 13)), entry("transferred1990", "zapdos", cp: 1990, hp: 132, ivs(13, 14, 14))])
        let item = stationedItem("Zapdos", ["zapdos"], ivs(13, 14, 14), before: 2000, after: 1980)
        let p = plan(rows, [item], b)
        XCTAssertTrue(p.stationedSeen.isEmpty, "two entries one notch apart: nothing says which: \(p.stationedSeen)")
        XCTAssertTrue(p.new.isEmpty && p.unsure.isEmpty)
        // two entries for one card: the bounds shelter neither (more entries than cards); both are Not seen
        XCTAssertEqual(Set(p.gone), ["real1989", "transferred1990"])
        // without the near neighbour the exact, unique, in-bounds entry matches with no question
        let alone = plan(rows, [item], box(rows, [entry("transferred1990", "zapdos", cp: 1990, hp: 132, ivs(13, 14, 14))]))
        XCTAssertEqual(alone.stationedSeen.map(\.savedId), ["transferred1990"])
        // a near neighbour outside the bounds is no neighbour (the bounds apply)
        let far = plan(rows, [item], box(rows, [entry("transferred1990", "zapdos", cp: 1990, hp: 132, ivs(13, 14, 14)), entry("far", "zapdos", cp: 1500, hp: 132, ivs(13, 14, 13))]))
        XCTAssertEqual(far.stationedSeen.map(\.savedId), ["transferred1990"])
        // two notches off on one stat is not near
        let two = plan(rows, [item], box(rows, [entry("transferred1990", "zapdos", cp: 1990, hp: 132, ivs(13, 14, 14)), entry("other", "zapdos", cp: 1989, hp: 132, ivs(13, 14, 12))]))
        XCTAssertEqual(two.stationedSeen.map(\.savedId), ["transferred1990"])
        // another species with the same bars is no neighbour
        let species = plan(rows, [item], box(rows, [entry("transferred1990", "zapdos", cp: 1990, hp: 132, ivs(13, 14, 14)), entry("moltres", "moltres", cp: 1989, hp: 132, ivs(13, 14, 13))]))
        XCTAssertEqual(species.stationedSeen.map(\.savedId), ["transferred1990"])
    }

    /// Rows not in CP order give no bounds, so a stationed card is not matched at all (round 31c matched a far-CP entry). Mutation: restore the unbounded match.
    func testAStationedCardIsNotMatchedWhenTheRowsAreNotInCpOrder() {
        var rows = orderedRows(); for i in stride(from: 0, to: rows.count - 2, by: 3) { rows.swapAt(i, i + 2) }
        XCTAssertNil(BlankCards.cpOrder(rows))
        let b = box(rows, [entry("far", "zapdos", cp: 1500, hp: 132, ivs(13, 14, 14))])
        let p = plan(rows, [stationedItem("Zapdos", ["zapdos"], ivs(13, 14, 14), before: 2000, after: 1980)], b)
        XCTAssertTrue(p.stationedSeen.isEmpty); XCTAssertEqual(p.gone, ["far"])
        XCTAssertNotNil(BoxMerge.unreadLine(p))
    }

    // MARK: 4. sheltering

    /// CE3: one Charizard (HP 118) whose CP was not read and two unseen Charizard entries with HP 118 (one transferred): nothing says which, so neither is kept out of Not seen; one entry for one
    /// card is. Mutation: restore the unbounded `cp-not-read` loop.
    func testCE3ACardWithNoCpShelltersAtMostOneEntryPerCard() {
        let rows = orderedRows()
        let item = Unmatched(frame: "a", cp: nil, name: "Charizard", nameText: "Charizard", hp: 118, ivs: nil, cpOptions: [], frames: 3, reason: "cp-not-read", into: nil, clip: nil)
        let two = plan(rows, [item], box(rows, [entry("c1607", "charizard", cp: 1607, hp: 118, ivs(13, 11, 12)), entry("c1616", "charizard", cp: 1616, hp: 118, ivs(13, 12, 13)), entry("c1500", "charizard", cp: 1500, hp: 119, ivs(1, 1, 1))]))
        XCTAssertTrue(two.unreadEntries.isEmpty); XCTAssertEqual(Set(two.gone), ["c1607", "c1616", "c1500"])
        XCTAssertTrue(BoxMerge.unreadLine(two)!.hasPrefix("1 Pokémon on screen could not be read (names: Charizard)"), "the line still says how many cards could not be read: \(BoxMerge.unreadLine(two)!)")
        XCTAssertTrue(BoxMerge.unreadLine(two)!.hasSuffix("Some of the entries below may be those."))
        let one = plan(rows, [item], box(rows, [entry("c1607", "charizard", cp: 1607, hp: 118, ivs(13, 11, 12))]))
        XCTAssertEqual(one.unreadEntries.map(\.id), ["c1607"]); XCTAssertTrue(one.gone.isEmpty)
        XCTAssertTrue(BoxMerge.unreadLine(one)!.hasSuffix("under \"On screen but not read\"."), BoxMerge.unreadLine(one)!)
        // two such cards and two such entries: one each
        let both = plan(rows, [item, item], box(rows, [entry("c1607", "charizard", cp: 1607, hp: 118, ivs(13, 11, 12)), entry("c1616", "charizard", cp: 1616, hp: 118, ivs(13, 12, 13))]))
        XCTAssertEqual(Set(both.unreadEntries.map(\.id)), ["c1607", "c1616"])
        // two such cards and three entries: more entries than cards, none
        let many = plan(rows, [item, item], box(rows, [entry("c1607", "charizard", cp: 1607, hp: 118, ivs(13, 11, 12)), entry("c1616", "charizard", cp: 1616, hp: 118, ivs(13, 12, 13)), entry("c1620", "charizard", cp: 1620, hp: 118, ivs(1, 2, 3))]))
        XCTAssertTrue(many.unreadEntries.isEmpty)
    }

    /// CE4: a blank card beside a misread row (CP 987 for 1987: bounds 2992 to 987) shelters no entry by its bounds, the count only; a real stretch of the 25 logs still does. Mutation: drop the
    /// `widestPlausibleBoundsRatio` guard.
    func testCE4WideBoundsShelterNothing() {
        let rows = orderedRows()
        let far = entry("transferred1500", "charizard", cp: 1500, hp: 118, ivs(1, 1, 1))
        let wide = plan(rows, [blankItem(before: 2992, after: 987)], box(rows, [far]))
        XCTAssertTrue(wide.unreadEntries.isEmpty); XCTAssertEqual(wide.gone, ["transferred1500"])
        XCTAssertNotNil(BoxMerge.unreadLine(wide), "the count is still told")
        // the widest real stretch (run1's first two cards, 4262 to 3000, ratio 1.42) and an ordinary one are within the limit
        XCTAssertGreaterThan(BoxMerge.widestPlausibleBoundsRatio, 4262.0 / 3000.0)
        let ok = plan(rows, [blankItem(before: 3000, after: 2000)], box(rows, [entry("in", "charizard", cp: 2500, hp: 118, ivs(1, 1, 1))]))
        XCTAssertEqual(ok.unreadEntries.map(\.id), ["in"], "3000 to 2000 is exactly 1.5: at the limit the bounds still count")
    }

    /// Stretches with the same neighbouring CPs pool only when they are one stretch. Two cards in two places that happen to lie between the same CPs are two stretches: one entry each, judged apart.
    /// Mutation: group by the bounds alone, as round 31c did.
    func testStretchesSharingBoundsPoolOnlyWhenTheyAreOneStretch() {
        let rows = orderedRows()
        let inside = [entry("in1", "zapdos", cp: 1995, hp: 130, ivs(1, 1, 1)), entry("in2", "moltres", cp: 1990, hp: 130, ivs(2, 2, 2))]
        // one stretch: a stationed card and a blank card pool (two cards, two entries)
        let one = plan(rows, [stationedItem("Zapdos", ["zapdos"], nil, before: 2000, after: 1980, stretch: 4), blankItem(before: 2000, after: 1980, stretch: 4)], box(rows, inside))
        XCTAssertEqual(Set(one.unreadEntries.map(\.id)), ["in1", "in2"])
        // two stretches (another row position): each is one card with two entries inside, so none
        let two = plan(rows, [stationedItem("Zapdos", ["zapdos"], nil, before: 2000, after: 1980, stretch: 4), blankItem(before: 2000, after: 1980, stretch: 19)], box(rows, inside))
        XCTAssertTrue(two.unreadEntries.isEmpty); XCTAssertEqual(Set(two.gone), ["in1", "in2"])
    }

    /// The pipeline gives every item the position of the row before its stretch.
    func testFoundItemsCarryTheirStretch() {
        let a = ivs(11, 14, 12)
        let r = items(Array(repeating: ("Zapdos", a), count: 6))
        XCTAssertEqual(r.map(\.stretch), [0])
        let blank = items(Array(repeating: (nil, nil), count: 6))
        XCTAssertEqual(blank.map(\.stretch), [0])
    }

    // MARK: 5. the line

    /// `unreadLine` points at the list below only while an entry in it can be one of the cards.
    func testUnreadLineDoesNotPointAtEntriesThatAreNotThere() {
        let rows = orderedRows()
        let b = box(rows, [entry("in1", "zapdos", cp: 1995, hp: 130, ivs(1, 1, 1))])
        let sheltered = plan(rows, [blankItem(before: 2000, after: 1980)], b)
        XCTAssertEqual(sheltered.unreadEntries.map(\.id), ["in1"])
        XCTAssertEqual(BoxMerge.unreadLine(sheltered), "1 card on screen could not be read (no name, CP or HP showed). Each has a saved entry kept out of the Not seen list, under \"On screen but not read\".")
        // two cards, one entry: one card has no entry, so the list below may hold it
        let partial = plan(rows, [blankItem(count: 2, before: 2000, after: 1980)], b)
        XCTAssertEqual(partial.unreadEntries.map(\.id), ["in1"])
        XCTAssertEqual(BoxMerge.unreadLine(partial), "2 cards on screen could not be read (no name, CP or HP showed). Some of the entries below may be those.")
    }
}
