import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// Round 31c, step 1: a stationed Pokémon's card (name and bars, no CP, no HP) is carried through the replay log and the pipeline as ONE `stationed` item per card, and the merge marks the saved
/// entry it is, when exactly one is, as seen. The constructed log (`run23-stationed-constructed.replay.jsonl`) is run23's excerpt with its blank readings replaced by the stationed readings the
/// reader would emit for the owner's six cards (no live log of a stationed card exists; the owner's two screenshots are read by `StationedCardTests`).
final class StationedCardMergeTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private func date(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(d) * 86_400) }
    private let hint = PagingHint(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds)
    private func run(_ fixture: String, paging: PagingHint? = nil) throws -> ScanPipeline.Outcome {
        try ScanPipeline.process(replay: Fixture.url(fixture), engine: sharedEngine, paging: paging ?? hint)
    }
    private func ivs(_ a: Int, _ d: Int, _ h: Int) -> IVs { IVs(atk: a, def: d, hp: h) }
    private func entry(_ id: String, _ species: String, cp: Int, hp: Int, _ iv: IVs?) -> BoxEntry {
        let nf = GameMaster.nameAndForm(gm.byId[species]?.name ?? species)
        let r = ScanRow(index: 0, name: nf.name, display: nf.name, form: nf.form, speciesId: species, dex: gm.byId[species]?.dex, cp: cp, hp: hp, ivs: iv, ivsRead: iv, ivsGuess: nil, level: 20, levelMax: 20, dust: 0,
                        solveStatus: "exact", flags: [], frames: [])
        return BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0))
    }
    private func stationedItems(_ o: ScanPipeline.Outcome) -> [Unmatched] { o.scan.unmatched.filter { $0.reason == StationedCards.reason } }

    /// The owner's six stationed Pokémon (run20 box) and what the constructed log shows of each.
    private let owners: [(id: String, species: String, cp: Int, hp: Int, bars: IVs)] = [
        ("z1990", "zapdos", 1990, 132, IVs(atk: 13, def: 14, hp: 14)), ("z1966", "zapdos", 1966, 130, IVs(atk: 11, def: 14, hp: 12)), ("m1966", "moltres", 1966, 131, IVs(atk: 15, def: 14, hp: 13)),
        ("z1965", "zapdos", 1965, 132, IVs(atk: 11, def: 11, hp: 15)), ("m1920", "moltres", 1920, 129, IVs(atk: 12, def: 12, hp: 10)), ("m1918", "moltres", 1918, 129, IVs(atk: 13, def: 10, hp: 10)),
    ]
    /// The excerpt's rows (read with the blanks as they are) as saved entries, and the owner's six beside them.
    private func ownerBox() throws -> [BoxEntry] {
        let plain = try run("run23-staraptor-twin-and-blanks.replay.jsonl")
        var out = plain.scan.rows.enumerated().map { BoxEntry(id: "row\($0.offset)", row: $0.element, firstSeen: date(0), lastSeen: date(0)) }
        for o in owners { out.append(entry(o.id, o.species, cp: o.cp, hp: o.hp, o.bars)) }
        return out
    }

    // MARK: a. the log and the pipeline

    /// The rows of the constructed log are the rows of the log with blanks: a stationed reading reaches the grouper, Refine and the JavaScript as the blank frame it was. Without that a named
    /// reading with no CP and no HP is a hidden-CP row for them. The six cards are six items, in order, each with its name, species ids, bars, readings and its neighbours' CPs.
    func testEachStationedCardIsOneItemAndTheRowsAreUnchanged() throws {
        let plain = try run("run23-staraptor-twin-and-blanks.replay.jsonl")
        let o = try run("run23-stationed-constructed.replay.jsonl")
        XCTAssertEqual(o.scan.rows, plain.scan.rows, "the rows are exactly those of the log with blank readings")
        XCTAssertEqual(o.scan.review, plain.scan.review)
        let items = stationedItems(o)
        XCTAssertEqual(items.map(\.name), ["Zapdos", "Zapdos", "Moltres", "Zapdos", "Moltres", "Moltres"])
        XCTAssertEqual(items.map(\.ivs), [ivs(13, 14, 14), ivs(11, 14, 12), ivs(15, 14, 13), ivs(11, 11, 15), ivs(12, 12, 10), ivs(13, 10, 10)])
        XCTAssertEqual(items.map(\.frames), [6, 6, 6, 6, 6, 6]); XCTAssertEqual(items.map(\.count), [1, 1, 1, 1, 1, 1])
        XCTAssertEqual(items.map(\.cpBefore), [1992, 1967, 1967, 1967, 1920, 1920]); XCTAssertEqual(items.map(\.cpAfter), [1987, 1961, 1961, 1961, 1913, 1913])
        XCTAssertEqual(items.first?.speciesIds, ["zapdos"])
        XCTAssertTrue(items.allSatisfy { $0.cp == nil && $0.hp == nil && $0.nameText == nil }, "no CP, no HP; the card's text is not copied")
        XCTAssertTrue(o.scan.unmatched.allSatisfy { $0.reason != BlankCards.reason }, "no stretch is left as a blank card")
        XCTAssertEqual(o.scan.unmatched.filter { $0.reason != StationedCards.reason }, plain.scan.unmatched.filter { $0.reason != BlankCards.reason }, "every other item is unchanged")
        // the blank-card items the plain log has are the same stretches: 1, 3 and 2 cards
        XCTAssertEqual(plain.scan.unmatched.filter { $0.reason == BlankCards.reason }.map(\.count), [1, 3, 2])
        // nothing without command paging (as for a blank stretch)
        XCTAssertTrue(try run("run23-stationed-constructed.replay.jsonl", paging: PagingHint(pagedByCommand: false, expectedPeriod: 1.2)).scan.unmatched.allSatisfy { $0.reason != StationedCards.reason })
    }

    /// The log keeps what a stationed reading holds (name, species ids, bars, flag) and no place text: the line has no field for one. An old log line decodes as before.
    func testAStationedReadingSurvivesTheLogLine() throws {
        var r = FrameReading(frame: "r1", time: 5)
        r.name = "Zapdos"; r.speciesIds = ["zapdos"]; r.nameText = "Zapdos"; r.ivs = ivs(13, 14, 14); r.ivConfidence = 0.9; r.flags = ["stationed"]
        let data = ReplayLog.encode(.reading(ReplayReading(r, time: 5, ms: 70)))
        guard case .reading(let back)? = ReplayLog.decode(data) else { return XCTFail("not a reading") }
        XCTAssertTrue(back.frameReading.isStationed); XCTAssertEqual(back.frameReading.name, "Zapdos"); XCTAssertEqual(back.frameReading.ivs, ivs(13, 14, 14)); XCTAssertNil(back.frameReading.cp)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(Set((try JSONSerialization.jsonObject(with: data) as! [String: Any]).keys), ["k", "t", "name", "nameText", "speciesIds", "ivs", "ivConfidence", "cpText", "hpText", "flags", "ms"], text)
        // a saved scan from before the field decodes
        let old = #"{"frame":"b1","frames":6,"reason":"blank-card","count":1,"cpBefore":1992,"cpAfter":1987}"#
        let u = try JSONDecoder().decode(Unmatched.self, from: Data(old.utf8))
        XCTAssertNil(u.speciesIds); XCTAssertEqual(u.count, 1)
    }

    private func reading(_ t: Double, _ name: String?, bars: IVs?, confidence: Double = 0.9) -> FrameReading {
        var r = FrameReading(frame: "s\(Int((t * 100).rounded()))", time: t)
        guard let name else { return r }
        r.name = name; r.speciesIds = [name.lowercased()]; r.nameText = name; r.flags = ["stationed"]
        if let bars { r.ivs = bars; r.ivConfidence = confidence }
        return r
    }
    private func normal(_ t: Double, cp: Int) -> FrameReading { var r = FrameReading(frame: "c\(Int((t * 100).rounded()))", time: t); r.nameText = "Pidgey"; r.cpText = "CP\(cp)"; r.hpText = "50 / 50 HP"; return r }
    private func rowAt(_ index: Int, cp: Int, from a: Double, to b: Double) -> ScanRow {
        ScanRow(index: index, name: "Pidgey", display: "Pidgey", form: "", speciesId: "pidgey", dex: 16, cp: cp, hp: 50, ivs: ivs(1, 2, 3), ivsRead: ivs(1, 2, 3), ivsGuess: nil, level: 20, levelMax: 20, dust: 0, solveStatus: "exact", flags: [],
                frames: stride(from: a, through: b, by: 0.4).map { FrameLabel(frame: "c\(Int(($0 * 100).rounded()))", time: $0, cp: cp, cpText: "\(cp)", name: "Pidgey", hp: "50/50", ivs: "1/2/3", ivConfidence: 0.9, sharpness: 1, clip: nil) })
    }
    /// A stretch between two Pidgey rows (900 before, 800 after), the readings given by (name, bars) per 0.2 s step starting at `start`.
    private func stretch(_ spec: [(String?, IVs?)], start: Double = 11.0, confidence: Double = 0.9) -> (readings: [FrameReading], rows: [ScanRow]) {
        var rs = stride(from: 10.0, through: 10.8, by: 0.4).map { normal($0, cp: 900) }
        for (k, s) in spec.enumerated() { rs.append(reading(start + Double(k) * 0.2, s.0, bars: s.1, confidence: confidence)) }
        let end = start + Double(spec.count) * 0.2
        rs += stride(from: end, through: end + 0.8, by: 0.4).map { normal($0, cp: 800) }
        return (rs, [rowAt(1, cp: 900, from: 10, to: 10.8), rowAt(2, cp: 800, from: end, to: end + 0.8)])
    }
    private func repeated(_ n: Int, _ name: String?, _ b: IVs?) -> [(String?, IVs?)] { Array(repeating: (name, b), count: n) }

    /// How a run of stationed readings is cut into cards. Three in a row: two of one species whose bars differ (cut at the change of settled bars), then two identical ones (one part of two
    /// periods, cut by the command's period, the readings shared). A name change cuts too; a lone reading with another name or other bars inside a run is a misread or the card changing and cuts nothing.
    func testSeveralStationedCardsInARow() {
        let a = ivs(11, 14, 12), b = ivs(11, 11, 15), m = ivs(15, 14, 13)
        // Zapdos a x6, Zapdos b x6, Moltres m x12 (two identical cards, 2.4 s)
        let s = stretch(repeated(6, "Zapdos", a) + repeated(6, "Zapdos", b) + repeated(12, "Moltres", m))
        let items = BlankCards.find(readings: s.readings, rows: s.rows, paging: hint)
        XCTAssertEqual(items.map(\.name), ["Zapdos", "Zapdos", "Moltres", "Moltres"], "bars cut the two Zapdos; the period cuts the identical Moltres")
        XCTAssertEqual(items.map(\.ivs), [a, b, m, m]); XCTAssertEqual(items.map(\.frames), [6, 6, 6, 6]); XCTAssertEqual(items.map(\.count), [1, 1, 1, 1])
        XCTAssertTrue(items.allSatisfy { $0.reason == StationedCards.reason && $0.cpBefore == 900 && $0.cpAfter == 800 })
        // the same two Zapdos with the SAME bars are one part of two periods: two identical cards, not a cut at nothing
        let twins = BlankCards.find(readings: stretch(repeated(12, "Zapdos", a)).readings, rows: stretch(repeated(12, "Zapdos", a)).rows, paging: hint)
        XCTAssertEqual(twins.map(\.ivs), [a, a]); XCTAssertEqual(twins.map(\.frames), [6, 6])
        // a name change with the SAME bars is two cards too
        let named = stretch(repeated(6, "Zapdos", a) + repeated(6, "Moltres", a))
        XCTAssertEqual(BlankCards.find(readings: named.readings, rows: named.rows, paging: hint).map(\.name), ["Zapdos", "Moltres"])
        // a lone reading of another name inside a run is a misread: one card. A lone reading with other bars is the card changing: one card, the bars it settled on.
        var odd = repeated(6, "Zapdos", a); odd[3] = ("Moltres", a)
        let oddS = stretch(odd)
        XCTAssertEqual(BlankCards.find(readings: oddS.readings, rows: oddS.rows, paging: hint).map(\.name), ["Zapdos"])
        var animating = repeated(6, "Zapdos", a); animating[0] = ("Zapdos", b)
        let animS = stretch(animating)
        let anim = BlankCards.find(readings: animS.readings, rows: animS.rows, paging: hint)
        XCTAssertEqual(anim.map(\.ivs), [a]); XCTAssertEqual(anim.map(\.frames), [6])
        // bars below the settled confidence are no state: the card still counts, with no bars (so the merge cannot match it)
        let weakS = stretch(repeated(6, "Zapdos", a), confidence: 0.5)
        let weak = BlankCards.find(readings: weakS.readings, rows: weakS.rows, paging: hint)
        XCTAssertEqual(weak.count, 1); XCTAssertNil(weak.first?.ivs)
        // no bars read (flag no-bars): one card, no bars
        let noBarsS = stretch(repeated(6, "Zapdos", nil))
        XCTAssertEqual(BlankCards.find(readings: noBarsS.readings, rows: noBarsS.rows, paging: hint).map(\.ivs), [nil])
        // blank readings beside a stationed card are a blank-card item of their own only when they last a card
        let mixed = stretch(repeated(6, "Zapdos", a) + repeated(6, nil, nil))
        let mixedItems = BlankCards.find(readings: mixed.readings, rows: mixed.rows, paging: hint)
        XCTAssertEqual(mixedItems.map(\.reason), [StationedCards.reason, BlankCards.reason]); XCTAssertEqual(mixedItems.last?.count, 1)
        let short = stretch(repeated(6, "Zapdos", a) + repeated(2, nil, nil))
        XCTAssertEqual(BlankCards.find(readings: short.readings, rows: short.rows, paging: hint).map(\.reason), [StationedCards.reason], "two blank readings are the transition, not a card")
        // a stretch under 0.8 of a period is nothing, stationed or not; a pause covers it
        let tiny = stretch(repeated(2, "Zapdos", a))
        XCTAssertTrue(BlankCards.find(readings: tiny.readings, rows: tiny.rows, paging: hint).isEmpty)
        var paused = hint; paused.pauses = [10.8...17.0]
        XCTAssertTrue(BlankCards.find(readings: s.readings, rows: s.rows, paging: paused).isEmpty)
    }

    // MARK: b. the merge

    func testTheSixCardsAreMatchedToTheOwnersEntriesAndNothingIsNotSeenOrNew() throws {
        let o = try run("run23-stationed-constructed.replay.jsonl")
        let box = try ownerBox()
        for kind in [BoxStore.Kind.full, .partial] {
            let p = BoxMerge.plan(scanned: o.scan.rows, unmatched: o.scan.unmatched, into: box, kind: kind, scanDate: date(1), gameMaster: gm)
            XCTAssertEqual(p.stationedSeen.map(\.savedId), ["z1990", "z1966", "m1966", "z1965", "m1920", "m1918"], "\(kind)")
            XCTAssertEqual(p.stationedSeen.map(\.item).count, 6)
            XCTAssertTrue(p.new.isEmpty && p.unsure.isEmpty, "never New, never a question: \(p.new) \(p.unsure.count)")
            XCTAssertTrue(p.gone.isEmpty && p.unreadEntries.isEmpty)
            XCTAssertEqual(p.same.count, o.scan.rows.count, "the rows are Same as before; the six are not in Same")
            let report = BoxMerge.goneReport(p, resolutions: [:])
            XCTAssertTrue(report.gone.isEmpty && report.onScreenUnread.isEmpty)
            XCTAssertNil(BoxMerge.unreadLine(p), "every item was matched: nothing is left unread")
            // nothing is written: the box after the scan differs only in last seen, no entry added or removed
            let after = try BoxMerge.apply(p, to: box)
            XCTAssertEqual(after.map(\.id), box.map(\.id))
            XCTAssertEqual(after.map(\.row), box.map(\.row), "no value is written")
            for id in owners.map(\.id) { XCTAssertEqual(after.first { $0.id == id }?.lastSeen, date(1), "\(id) is marked seen") }
            let lines = ScanReportBuilder.reviewLines(plan: p, resolutions: [:], keepGone: [], base: box)
            XCTAssertEqual(lines.filter { $0.contains("is stationed") }.count, 6)
        }
        // without the matching (the items stay unread, as blank cards did) the same six entries are on screen unread, which is the 31a outcome
        var stripped = o.scan.unmatched; for i in stripped.indices { stripped[i].ivs = nil }
        let unread = BoxMerge.plan(scanned: o.scan.rows, unmatched: stripped, into: try ownerBox(), kind: .full, scanDate: date(1), gameMaster: gm)
        XCTAssertTrue(unread.stationedSeen.isEmpty); XCTAssertEqual(Set(unread.unreadEntries.map(\.id)), Set(owners.map(\.id))); XCTAssertTrue(unread.gone.isEmpty)
    }

    /// One match needs ALL of: the species, the bars, exactly one such entry, and (in CP order) a CP inside the bounds. A failed match is an unread item: never New, never a question, and the
    /// entries inside the bounds stay out of Not seen exactly as for a blank card (as many entries as cards).
    func testAMatchNeedsOneEntryOfTheSpeciesTheBarsAndTheBounds() throws {
        let o = try run("run23-stationed-constructed.replay.jsonl")
        let rows = o.scan.rows
        func plan(_ extra: [BoxEntry], drop: Set<String> = [], items: [Unmatched]? = nil, kind: BoxStore.Kind = .full) throws -> BoxMerge.Plan {
            let box = try ownerBox().filter { !drop.contains($0.id) } + extra
            return BoxMerge.plan(scanned: rows, unmatched: items ?? o.scan.unmatched, into: box, kind: kind, scanDate: date(1), gameMaster: gm)
        }
        // two entries of the species and bars inside the bounds: several, so none (both stay out of Not seen only when as many as the cards: here 2 entries, 1 card, so they are Not seen)
        let twin = try plan([entry("zTwin", "zapdos", cp: 1964, hp: 132, ivs(11, 14, 12))])
        XCTAssertFalse(twin.stationedSeen.map(\.savedId).contains("z1966"), "two Zapdos 11/14/12 inside the bounds: not unique")
        XCTAssertEqual(twin.stationedSeen.count, 5)
        XCTAssertTrue(twin.new.isEmpty && twin.unsure.isEmpty, "never New, never a question")
        XCTAssertEqual(Set(twin.gone), ["z1966", "zTwin"], "two entries for one card: nothing says which, they are Not seen as for a blank card")
        // the entry the card is, absent from the box: the card is unread; the other entry inside the bounds (one entry, one card) is kept out of Not seen
        let absent = try plan([], drop: ["z1966"])
        XCTAssertEqual(absent.stationedSeen.count, 5)
        XCTAssertTrue(absent.new.isEmpty && absent.unsure.isEmpty && absent.gone.isEmpty, "\(absent.gone)")
        XCTAssertNotNil(BoxMerge.unreadLine(absent)); XCTAssertTrue(BoxMerge.unreadLine(absent)!.contains("Zapdos"))
        // other bars on the saved entry: no match, and the entry is on screen unread inside the bounds (same as before)
        var other = entry("z1966", "zapdos", cp: 1966, hp: 130, ivs(11, 14, 13))
        other.row.ivsRead = ivs(11, 14, 13)
        let bars = try plan([other], drop: ["z1966"])
        XCTAssertEqual(bars.stationedSeen.count, 5); XCTAssertEqual(bars.unreadEntries.map(\.id), ["z1966"]); XCTAssertTrue(bars.gone.isEmpty)
        // another species with the right bars is not a match (Moltres 15/14/13 at CP 1966 is the Moltres card's; a Zapdos entry with those bars is not)
        let species = try plan([entry("zWrong", "zapdos", cp: 1966, hp: 131, ivs(15, 14, 13))], drop: ["m1966"])
        XCTAssertFalse(species.stationedSeen.map(\.savedId).contains("zWrong"))
        // a CP outside the bounds is no match (CP order): the same entry, 1500, is not seen by the card
        let far = try plan([entry("far", "zapdos", cp: 1500, hp: 130, ivs(11, 14, 12))], drop: ["z1966"])
        XCTAssertFalse(far.stationedSeen.map(\.savedId).contains("far")); XCTAssertEqual(far.gone, ["far"])
        // rows not in CP order: the bounds mean nothing, a unique species and bars match is still a match (the entry at CP 1500 is the only one)
        var shuffled = rows; for i in stride(from: 0, to: rows.count - 2, by: 3) { shuffled.swapAt(i, i + 2) }
        if BlankCards.cpOrder(shuffled) == nil {
            let box = try ownerBox().filter { $0.id != "z1966" } + [entry("far", "zapdos", cp: 1500, hp: 130, ivs(11, 14, 12))]
            let p = BoxMerge.plan(scanned: shuffled, unmatched: o.scan.unmatched, into: box, kind: .full, scanDate: date(1), gameMaster: gm)
            XCTAssertTrue(p.stationedSeen.map(\.savedId).contains("far"))
        }
        // a stationed card never creates an entry: a card nobody in the box is: nothing New
        let empty = BoxMerge.plan(scanned: rows, unmatched: o.scan.unmatched, into: try ownerBox().filter { !owners.map(\.id).contains($0.id) }, kind: .full, scanDate: date(1), gameMaster: gm)
        XCTAssertTrue(empty.stationedSeen.isEmpty && empty.new.isEmpty && empty.unsure.isEmpty)
        // a card with no bars read cannot be matched
        var noBars = o.scan.unmatched; for i in noBars.indices { noBars[i].ivs = nil }
        XCTAssertTrue(try plan([], items: noBars).stationedSeen.isEmpty)
        // two identical cards and one entry: the first takes it, the second is unread
        let two = [Unmatched(frame: "a", cp: nil, name: "Zapdos", nameText: nil, hp: nil, ivs: ivs(11, 14, 12), cpOptions: nil, frames: 6, reason: StationedCards.reason, into: nil, clip: nil, count: 1, cpBefore: 1967, cpAfter: 1961, speciesIds: ["zapdos"])]
        let both = try plan([], items: two + two)
        XCTAssertEqual(both.stationedSeen.map(\.item), [0]); XCTAssertEqual(both.stationedSeen.map(\.savedId), ["z1966"])
    }

    /// A card whose reading narrowed the species (Nidoran's symbol read) matches that species only; one that did not (every form its name could be) matches any of them, as the merge's
    /// other name-based rules do. A hand correction of the IVs matches by the value the scan read.
    func testSpeciesNarrowingAndCorrections() throws {
        let rows = [rowAt(1, cp: 900, from: 10, to: 10.8), rowAt(2, cp: 800, from: 12.0, to: 12.8)]
        func item(_ name: String, _ ids: [String]?, _ b: IVs) -> Unmatched {
            Unmatched(frame: "a", cp: nil, name: name, nameText: nil, hp: nil, ivs: b, cpOptions: nil, frames: 6, reason: StationedCards.reason, into: nil, clip: nil, count: 1, cpBefore: 900, cpAfter: 800, speciesIds: ids)
        }
        let b = ivs(5, 6, 7)
        let male = entry("male", "nidoran_male", cp: 850, hp: 40, b)
        func seen(_ it: Unmatched, _ box: [BoxEntry]) -> [String] {
            BoxMerge.plan(scanned: rows, unmatched: [it], into: box, kind: .partial, scanDate: date(1), gameMaster: gm).stationedSeen.map(\.savedId)
        }
        let base = [entry("r0", "pidgey", cp: 900, hp: 50, ivs(1, 2, 3)), entry("r1", "pidgey", cp: 800, hp: 50, ivs(1, 2, 3))]
        XCTAssertEqual(seen(item("Nidoran", ["nidoran_female", "nidoran_male"], b), base + [male]), ["male"], "a name that could be either sex: either entry")
        XCTAssertEqual(seen(item("Nidoran", ["nidoran_female"], b), base + [male]), [], "the symbol read as female: the male entry is another Pokémon")
        XCTAssertEqual(seen(item("Nidoran", nil, b), base + [male]), ["male"], "no ids kept: the screen name decides")
        var corrected = male; corrected.row.ivs = ivs(5, 6, 8); corrected.corrections.ivs = Fix(was: b)
        XCTAssertEqual(seen(item("Nidoran", ["nidoran_male"], b), base + [corrected]), ["male"], "the bars the scan read are the correction's old value")
    }

    /// Several unmatched stationed cards in one stretch are one group for the bounds: three cards cover the three entries inside them (a blank stretch of three does the same). Judged one by
    /// one, none of them would (three entries, one card each).
    func testUnmatchedStationedCardsOfOneStretchCoverTheEntriesInsideIt() throws {
        let o = try run("run23-stationed-constructed.replay.jsonl")
        // the first long stretch holds three cards; their bars are not in the box, three entries of other bars sit inside its bounds (1967 to 1961)
        var box = try ownerBox().filter { !["z1966", "m1966", "z1965"].contains($0.id) }
        box += [entry("x1", "zapdos", cp: 1966, hp: 130, ivs(1, 1, 1)), entry("x2", "zapdos", cp: 1964, hp: 130, ivs(2, 2, 2)), entry("x3", "moltres", cp: 1962, hp: 130, ivs(3, 3, 3))]
        let p = BoxMerge.plan(scanned: o.scan.rows, unmatched: o.scan.unmatched, into: box, kind: .full, scanDate: date(1), gameMaster: gm)
        XCTAssertEqual(p.stationedSeen.count, 3)
        XCTAssertEqual(Set(p.unreadEntries.map(\.id)), ["x1", "x2", "x3"]); XCTAssertTrue(p.gone.isEmpty)
        XCTAssertEqual(Set(BoxMerge.goneReport(p, resolutions: [:]).onScreenUnread), ["x1", "x2", "x3"])
        // a fourth entry in the bounds: more entries than cards, so none is kept out of Not seen
        let four = BoxMerge.plan(scanned: o.scan.rows, unmatched: o.scan.unmatched, into: box + [entry("x4", "moltres", cp: 1963, hp: 130, ivs(4, 4, 4))], kind: .full, scanDate: date(1), gameMaster: gm)
        XCTAssertTrue(four.unreadEntries.isEmpty); XCTAssertEqual(Set(four.gone), ["x1", "x2", "x3", "x4"])
    }

    // MARK: d. Articuno 1729

    /// Articuno 1729's card sits between Scyther 1786 and Scyther 1726 in the real log. Stationed readings in its place do NOT make it caught: the grouper joins the first 1726 reading (at 513.25 s,
    /// after the six card-less readings) to the 1786 row, so ONE row (510.85 to 513.25 s) spans the stretch, and a stretch is recorded only between two different rows (the row before has ended,
    /// the row after has not begun: that is what keeps a menu open on one Pokémon from counting as a card). Catching it needs a rule of its own (a stationed stretch inside a row), which this
    /// round does not add. This pins the consequence: no item, and in a Full scan the saved Articuno is Not seen. The stretch itself IS read as a stationed card by `StationedCards` when
    /// the rows allow (`testSeveralStationedCardsInARow`).
    func testArticunoInsideTheScytherRowsIsStillNotCaught() throws {
        let o = try ScanPipeline.process(replay: Fixture.url("run23-stationed-articuno.replay.jsonl"), engine: sharedEngine, paging: hint)
        XCTAssertTrue(o.scan.unmatched.allSatisfy { $0.reason != StationedCards.reason && $0.reason != BlankCards.reason }, "\(o.scan.unmatched)")
        let scyther = o.scan.rows.filter { $0.display == "Scyther" }
        XCTAssertEqual(scyther.map(\.cp), [1786, 1726])
        let times = scyther[0].frames.compactMap(\.time)
        XCTAssertEqual(times.count, 4, "the 1786 row holds the three 1786 readings and the first 1726 one, across the stretch")
        XCTAssertGreaterThan(times.max()! - times.min()!, 2.0)
        let box = o.scan.rows.enumerated().map { BoxEntry(id: "r\($0.offset)", row: $0.element, firstSeen: date(0), lastSeen: date(0)) } + [entry("art", "articuno", cp: 1729, hp: 125, ivs(15, 11, 15))]
        let p = BoxMerge.plan(scanned: o.scan.rows, unmatched: o.scan.unmatched, into: box, kind: .full, scanDate: date(1), gameMaster: gm)
        XCTAssertTrue(p.stationedSeen.isEmpty); XCTAssertEqual(p.gone, ["art"])
    }
}
