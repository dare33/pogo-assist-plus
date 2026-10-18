import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// Round 32, patch (the final review, F5): a stationed card the reader recognised only in part must not vanish. The recognised stationed readings alone can last under 0.8 of a period when the card
/// did not (one unrecognised reading at an edge), and `StationedCards` used to drop such a part although `BlankCards.find` had counted the stretch as a card; the second of two neighbouring
/// Moltres also took the first one's bars. The six-bird log (`run23-stationed-constructed`, six readings a card at 0.2 s) is reshaped the way the device may read it.
final class RoundThirtyTwoPatchTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private func date(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(d) * 86_400) }
    private let hint = PagingHint(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds)
    private func ivs(_ a: Int, _ d: Int, _ h: Int) -> IVs { IVs(atk: a, def: d, hp: h) }
    private let owners: [(id: String, species: String, cp: Int, hp: Int, bars: IVs)] = [
        ("z1990", "zapdos", 1990, 132, IVs(atk: 13, def: 14, hp: 14)), ("z1966", "zapdos", 1966, 130, IVs(atk: 11, def: 14, hp: 12)), ("m1966", "moltres", 1966, 131, IVs(atk: 15, def: 14, hp: 13)),
        ("z1965", "zapdos", 1965, 132, IVs(atk: 11, def: 11, hp: 15)), ("m1920", "moltres", 1920, 129, IVs(atk: 12, def: 12, hp: 10)), ("m1918", "moltres", 1918, 129, IVs(atk: 13, def: 10, hp: 10)),
    ]
    private func entry(_ id: String, _ species: String, cp: Int, hp: Int, _ iv: IVs?) -> BoxEntry {
        let nf = GameMaster.nameAndForm(gm.byId[species]?.name ?? species)
        let r = ScanRow(index: 0, name: nf.name, display: nf.name, form: nf.form, speciesId: species, dex: gm.byId[species]?.dex, cp: cp, hp: hp, ivs: iv, ivsRead: iv, ivsGuess: nil, level: 20, levelMax: 20, dust: 0,
                        solveStatus: "exact", flags: [], frames: [])
        return BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0))
    }

    // MARK: the six birds, reshaped

    /// The constructed log with each card's six stationed lines (position 0 to 5) kept, blanked (a reading with no name, CP or HP text) or dropped by `how`. The six lines of a card are every
    /// sixth stationed line of the log; `resetAtOtherLines` (the review's probe) restarts the count at any line that is not a stationed reading, a tap line included, which cuts a card at its tap.
    private func reshaped(_ how: (Int) -> String, name: String, resetAtOtherLines: Bool = false) throws -> URL {
        let lines = try String(contentsOf: Fixture.url("run23-stationed-constructed.replay.jsonl"), encoding: .utf8).split(separator: "\n").map(String.init)
        let blankLine = #"{"k":"r","t":TTT,"nameText":"","hpText":"","cpText":"","flags":["no-cp-text"],"ivConfidence":0,"ms":10}"#
        var out = [String](), k = 0, prev = false
        for l in lines {
            let st = l.contains("\"stationed\"")
            if resetAtOtherLines && st && !prev { k = 0 }
            prev = st
            guard st else { out.append(l); continue }
            let pos = k % 6; k += 1
            switch how(pos) {
            case "keep": out.append(l)
            case "blank": out.append(blankLine.replacingOccurrences(of: "TTT", with: l.components(separatedBy: "\"t\":")[1].components(separatedBy: ",")[0]))
            default: break
            }
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("r32patch-\(name).jsonl")
        try out.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func assertSixBirds(_ how: (Int) -> String, _ name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let resetAtOtherLines = false
        let plain = try ScanPipeline.process(replay: Fixture.url("run23-staraptor-twin-and-blanks.replay.jsonl"), engine: sharedEngine, paging: hint)
        var box = plain.scan.rows.enumerated().map { BoxEntry(id: "row\($0.offset)", row: $0.element, firstSeen: date(0), lastSeen: date(0)) }
        for o in owners { box.append(entry(o.id, o.species, cp: o.cp, hp: o.hp, o.bars)) }
        let o = try ScanPipeline.process(replay: try reshaped(how, name: name, resetAtOtherLines: resetAtOtherLines), engine: sharedEngine, paging: hint)
        let items = o.scan.unmatched.filter { $0.reason == StationedCards.reason }
        XCTAssertEqual(items.map(\.name), ["Zapdos", "Zapdos", "Moltres", "Zapdos", "Moltres", "Moltres"], name, file: file, line: line)
        XCTAssertEqual(items.map(\.ivs), owners.map(\.bars), "\(name): the bars of each item are those of its own card", file: file, line: line)
        XCTAssertTrue(o.scan.unmatched.allSatisfy { $0.reason != BlankCards.reason }, "\(name): no blank card is left over", file: file, line: line)
        let p = BoxMerge.plan(scanned: o.scan.rows, unmatched: o.scan.unmatched, into: box, kind: .full, scanDate: date(1), gameMaster: gm)
        XCTAssertEqual(p.stationedSeen.map(\.savedId), owners.map(\.id), "\(name): six items matched to the six owner entries", file: file, line: line)
        XCTAssertTrue(p.gone.isEmpty && p.unreadEntries.isEmpty && p.new.isEmpty, "\(name): nothing Not seen, nothing on screen unread", file: file, line: line)
        XCTAssertNil(BoxMerge.unreadLine(p), name, file: file, line: line)
        XCTAssertEqual(BoxMerge.unreadCount(p), 0, name, file: file, line: line)
    }

    /// The review's probe cut each card at its tap line (it restarted the count of six at every line that is not a stationed reading), so its blanking fell on the wrong readings: some cards had two
    /// recognised readings of six, which no rule can call a card. What must hold there is conservation: never fewer cards than the stretches' length gives (six), and no item with another card's
    /// bars. Mutation: delete the top-up (five items, a card lost).
    func testTheProbesTapCutShapesStillCountSixCards() throws {
        let shapes: [(String, (Int) -> String)] = [("b1s4b1", { $0 == 0 || $0 == 5 ? "blank" : "keep" }), ("b2s4", { $0 < 2 ? "blank" : "keep" }),
                                                   ("04first", { $0 == 0 ? "blank" : ($0 % 2 == 0 ? "keep" : "drop") }), ("04last", { $0 == 4 ? "blank" : ($0 % 2 == 0 ? "keep" : "drop") })]
        for (name, how) in shapes {
            let o = try ScanPipeline.process(replay: try reshaped(how, name: name + "-tap", resetAtOtherLines: true), engine: sharedEngine, paging: hint)
            XCTAssertEqual(cards(o.scan.unmatched.filter { $0.reason == StationedCards.reason || $0.reason == BlankCards.reason }), 6, name)
            let stationed = o.scan.unmatched.filter { $0.reason == StationedCards.reason }
            let bars = stationed.compactMap(\.ivs)
            XCTAssertEqual(Set(bars.map { "\($0)" }).count, bars.count, "\(name): no two items carry one card's bars")
        }
    }

    /// B1 S4 B1 at 0.2 s: the first and last reading of each card unrecognised. Mutation: measure a stationed part over its recognised readings only (drop `widen` from the length rule and the
    /// promotion): the three Zapdos and the first Moltres have 4 readings (0.8 s) and vanish (4 of 6 items missing, 4 entries Not seen).
    func testB1S4B1() throws { try assertSixBirds({ $0 == 0 || $0 == 5 ? "blank" : "keep" }, "B1S4B1") }

    /// B2 S4: the first two readings of each card unrecognised. Same mutation: only the second Moltres survived, with the first Moltres's bars (the reviewer's m1918 12/12/10 for 13/10/10).
    func testB2S4() throws { try assertSixBirds({ $0 < 2 ? "blank" : "keep" }, "B2S4") }

    /// 0.4 s readings (positions 0, 2, 4 kept), the first reading of each card unrecognised. Mutation: as above (only m1918 survived).
    func testAtFourTenthsTheFirstReadingBlank() throws { try assertSixBirds({ $0 == 0 ? "blank" : ($0 % 2 == 0 ? "keep" : "drop") }, "04first") }

    /// 0.4 s readings, the last reading of each card unrecognised. Mutation: as above (m1920 twice, m1918 carrying m1920's bars).
    func testAtFourTenthsTheLastReadingBlank() throws { try assertSixBirds({ $0 == 4 ? "blank" : ($0 % 2 == 0 ? "keep" : "drop") }, "04last") }

    /// The expected device shape: about three readings a card at 0.4 s, all recognised. It passed before the patch as well (the rule never dropped it), so it fails on no earlier revision; it guards
    /// the patch against costing the normal case. Mutation: raise `minimumLength` to 1.3 periods (the cards of 1.2 s vanish).
    func testThreeReadingsACardAtFourTenthsAllRecognised() throws { try assertSixBirds({ $0 % 2 == 0 ? "keep" : "drop" }, "04all") }

    // MARK: the rules, on constructed stretches

    private func reading(_ t: Double, _ name: String?, bars: IVs?) -> FrameReading {
        var r = FrameReading(frame: "s\(Int((t * 100).rounded()))", time: t)
        guard let name else { return r }
        r.name = name; r.speciesIds = [name.lowercased()]; r.nameText = name; r.flags = ["stationed"]
        if let bars { r.ivs = bars; r.ivConfidence = 0.9 }
        return r
    }
    private func normal(_ t: Double, cp: Int) -> FrameReading { var r = FrameReading(frame: "c\(Int((t * 100).rounded()))", time: t); r.nameText = "Pidgey"; r.cpText = "CP\(cp)"; r.hpText = "50 / 50 HP"; return r }
    private func rowAt(_ index: Int, cp: Int, from a: Double, to b: Double) -> ScanRow {
        ScanRow(index: index, name: "Pidgey", display: "Pidgey", form: "", speciesId: "pidgey", dex: 16, cp: cp, hp: 50, ivs: ivs(1, 2, 3), ivsRead: ivs(1, 2, 3), ivsGuess: nil, level: 20, levelMax: 20, dust: 0, solveStatus: "exact", flags: [],
                frames: stride(from: a, through: b, by: 0.4).map { FrameLabel(frame: "c\(Int(($0 * 100).rounded()))", time: $0, cp: cp, cpText: "\(cp)", name: "Pidgey", hp: "50/50", ivs: "1/2/3", ivConfidence: 0.9, sharpness: 1, clip: nil) })
    }
    /// A stretch between two Pidgey rows, the readings given by (name, bars) every `step` seconds from 11.0.
    private func stretch(_ spec: [(String?, IVs?)], step: Double = 0.2) -> (readings: [FrameReading], rows: [ScanRow]) {
        var rs = stride(from: 10.0, through: 10.8, by: 0.4).map { normal($0, cp: 900) }
        for (k, s) in spec.enumerated() { rs.append(reading(11.0 + Double(k) * step, s.0, bars: s.1)) }
        let end = 11.0 + Double(spec.count) * step
        rs += stride(from: end, through: end + 0.8, by: 0.4).map { normal($0, cp: 800) }
        return (rs, [rowAt(1, cp: 900, from: 10, to: 10.8), rowAt(2, cp: 800, from: end, to: end + 0.8)])
    }
    private func cards(_ items: [Unmatched]) -> Int { items.reduce(0) { $0 + ($1.reason == BlankCards.reason ? ($1.count ?? 1) : 1) } }

    /// Conservation: two stationed readings of different names among blank readings are too few for a card each, but the stretch lasts a card (`BlankCards`: 1.6 s, one card), so the stretch gives a
    /// blank-card item (no name, no bars), not nothing. Mutation: delete the top-up after the parts (the stretch gives no item at all; it gave none on 59f724b).
    func testAStretchWhoseStationedReadingsAreTooFewYieldsABlankCardNotNothing() {
        let s = stretch([(nil, nil), (nil, nil), ("Zapdos", ivs(1, 2, 3)), (nil, nil), (nil, nil), ("Moltres", ivs(4, 5, 6)), (nil, nil), (nil, nil)])
        let items = BlankCards.find(readings: s.readings, rows: s.rows, paging: hint)
        XCTAssertEqual(items.map(\.reason), [BlankCards.reason]); XCTAssertEqual(items.first?.count, 1)
        XCTAssertTrue(items.first?.name == nil && items.first?.ivs == nil)
        XCTAssertEqual(items.first?.cpBefore, 900); XCTAssertEqual(items.first?.cpAfter, 800)
        // and in the banner (an unmatched blank card is counted)
        // with enough readings for the cards, the count is the stretch's: 6 stationed readings of one card among blanks is one card, not two
        let one = stretch([(nil, nil), ("Zapdos", ivs(1, 2, 3)), ("Zapdos", ivs(1, 2, 3)), ("Zapdos", ivs(1, 2, 3)), (nil, nil), (nil, nil)])
        let oneItems = BlankCards.find(readings: one.readings, rows: one.rows, paging: hint)
        XCTAssertEqual(oneItems.map(\.reason), [StationedCards.reason]); XCTAssertEqual(cards(oneItems), 1, "the blank readings the card took are not counted again")
    }

    /// The number of items for a stretch is never less than the cards `BlankCards` counts, for every way of blanking readings out of a stretch of two cards (a stationed Zapdos then a stationed Moltres,
    /// six readings each at 0.2 s) and of three at 0.4 s. Mutation: delete the top-up (a pattern that loses a card fails).
    func testCardsAreConservedWhateverReadingsAreBlanked() {
        for mask in 0..<(1 << 12) {
            let spec: [(String?, IVs?)] = (0..<12).map { k in
                if mask >> k & 1 == 1 { return (nil, nil) }
                return k < 6 ? ("Zapdos", ivs(1, 2, 3)) : ("Moltres", ivs(4, 5, 6))
            }
            let s = stretch(spec)
            // the number the whole-stretch rule gives, read from the same stretch with every reading blank
            let allBlank = stretch(spec.map { _ in (nil, nil) })
            let want = cards(BlankCards.find(readings: allBlank.readings, rows: allBlank.rows, paging: hint))
            let got = cards(BlankCards.find(readings: s.readings, rows: s.rows, paging: hint))
            XCTAssertGreaterThanOrEqual(got, want, "mask \(mask)")
        }
    }

    /// (iii) The bars of an item are those of its own recognised readings, whatever the neighbour's: two Moltres cards in a row (12/12/10 then 13/10/10), the second with its first two readings
    /// unrecognised, are two items with their own bars; a stationed card with no bars read (blank readings widen it) has none, never its neighbour's. Mutation: join a short part to the same-name
    /// neighbour before widening it (the second card was one item with the first's bars).
    func testBarsComeOnlyFromAPartsOwnReadings() {
        let a = ivs(12, 12, 10), b = ivs(13, 10, 10)
        let spec: [(String?, IVs?)] = Array(repeating: ("Moltres", a), count: 6) + [(nil, nil), (nil, nil)] + Array(repeating: ("Moltres", b), count: 4)
        let s = stretch(spec)
        let items = BlankCards.find(readings: s.readings, rows: s.rows, paging: hint)
        XCTAssertEqual(items.map(\.reason), [StationedCards.reason, StationedCards.reason]); XCTAssertEqual(items.map(\.ivs), [a, b])
        // the same at 0.4 s with the last reading of the second card unrecognised
        let spec2: [(String?, IVs?)] = Array(repeating: ("Moltres", a), count: 3) + [("Moltres", b), ("Moltres", b), (nil, nil)]
        let s2 = stretch(spec2, step: 0.4)
        let items2 = BlankCards.find(readings: s2.readings, rows: s2.rows, paging: hint)
        XCTAssertEqual(items2.map(\.ivs), [a, b], "the second card has its own bars, not the first's")
        // a part with no bars read has none
        let noBars = stretch([(nil, nil), ("Zapdos", nil), ("Zapdos", nil), ("Zapdos", nil), ("Zapdos", nil), (nil, nil)])
        XCTAssertEqual(BlankCards.find(readings: noBars.readings, rows: noBars.rows, paging: hint).map(\.ivs), [nil])
    }

    /// Round 32's behaviours stay: `S B S B S B` is one item, and a genuinely short stray stationed reading is not an extra card (one stationed reading beside two blank readings at the edge of a
    /// one-card stretch gives that card's one item, never two).
    func testRoundThirtyTwoBehavioursStay() {
        let a = ivs(1, 2, 3)
        let sb = stretch([("Zapdos", a), (nil, nil), ("Zapdos", a), (nil, nil), ("Zapdos", a), (nil, nil)])
        XCTAssertEqual(BlankCards.find(readings: sb.readings, rows: sb.rows, paging: hint).map(\.ivs), [a])
        let stray = stretch(Array(repeating: ("Zapdos", a), count: 6) + [("Moltres", ivs(4, 5, 6)), (nil, nil)])
        let items = BlankCards.find(readings: stray.readings, rows: stray.rows, paging: hint)
        XCTAssertEqual(cards(items), 1, "a stray reading is not an extra card: \(items.map { "\($0.reason) \($0.name ?? "-")" })")
        XCTAssertEqual(items.first?.name, "Zapdos")
    }
}
