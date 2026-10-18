import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// Round 31a: the first whole-box Full scan (run23) and the two reviews of round 30. Rows that hold several cards are cut (bars for N states, bars below the settled confidence on the
/// command's beat, timing with identical readings beside an irregular neighbourhood), cards on screen that were not read are counted from the timing and kept out of "Not seen", a part
/// read is never paired automatically to an entry of another form, and a one-reading fragment beside its own card is flagged. Excerpts of run23's log are in `Fixtures/run23-*`.
final class RoundThirtyOneTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private func date(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(d) * 86_400) }
    private let hint = PagingHint(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds)
    private func run(_ fixture: String, paging: PagingHint?) throws -> ScanPipeline.Outcome {
        try ScanPipeline.process(replay: Fixture.url(fixture), engine: sharedEngine, paging: paging)
    }
    private func rows(_ o: ScanPipeline.Outcome, _ display: String, cp: Int) -> [ScanRow] { o.scan.rows.filter { $0.display == display && $0.cp == cp } }

    // MARK: 1a, a row of several cards is cut at each change of bars

    /// run23's Charmander CP 12 / HP 11: nine readings, settled bars 11/13/3 x3, 11/4/4 x2 (one 11/5/4 between), 10/7/0 x3. Three Pokémon (owner-confirmed 4 Oct 2026), cut at both changes, each part
    /// solved on its own. `barsSplitMaxStates` is 3: a limit of 2 leaves the row one, and so does a fourth state (nothing is cut; the row keeps `ivs-disagree`).
    func testThreeStatesOfBarsAreThreePokemon() throws {
        XCTAssertEqual(Refine.barsSplitMaxStates, 3)
        func labelled(_ rs: [FrameReading]) -> [FrameReading] { rs.enumerated().map { (i, r) -> FrameReading in var f = r; f.frame = "r\(i)"; return f } }
        let readings = labelled(try ReplayReadings.load(url: Fixture.url("run23-charmander-triplet.replay.jsonl")).readings)
        let base = try sharedEngine.finish(readings: readings)
        XCTAssertEqual(base.rows.filter { $0.display == "Charmander" && $0.cp == 12 }.count, 1, "the JavaScript joins the three")
        // (the excerpt also holds a Charmander CP 11 of two states, which is cut whatever the limit)
        let byDefault = try Refine.splitByBars(base, readings: readings, engine: sharedEngine, hintPeriod: 1.2)
        let c = byDefault.scan.rows.filter { $0.display == "Charmander" && $0.cp == 12 }
        XCTAssertEqual(c.map(\.ivs), [IVs(atk: 11, def: 13, hp: 3), IVs(atk: 11, def: 4, hp: 4), IVs(atk: 10, def: 7, hp: 0)])
        XCTAssertTrue(c.allSatisfy { $0.flags.contains("split-by-bars") && $0.solveStatus == "exact" && $0.cp == 12 && $0.hp == 11 }, "\(c.map(\.flags))")
        XCTAssertEqual(c.map { $0.frames.count }.reduce(0, +), 9, "the nine readings are divided, none lost")
        let two = try Refine.splitByBars(base, readings: readings, engine: sharedEngine, hintPeriod: 1.2, maxStates: 2)
        XCTAssertEqual(two.scan.rows.filter { $0.display == "Charmander" && $0.cp == 12 }.count, 1, "a limit of two leaves it one row")
        XCTAssertEqual(byDefault.scan.rows.count, two.scan.rows.count + 2)
        XCTAssertEqual(byDefault.marks.count, two.marks.count + 2, "one mark per cut")
        // four states: a fourth block of three readings (bars 7/7/7) follows the third, the cards after it come 1.2 s later: left as one row
        var four = [FrameReading]()
        let src = try ReplayReadings.load(url: Fixture.url("run23-charmander-triplet.replay.jsonl")).readings
        let lastIdx = try XCTUnwrap(src.indices.last { src[$0].name == "Charmander" && src[$0].cp == 12 })
        let lastT = src[lastIdx].time!
        for (i, r) in src.enumerated() {
            var x = r; if x.time! > lastT { x.time! += 1.2 }; four.append(x)
            if i == lastIdx { for k in (lastIdx - 2)...lastIdx { var y = src[k]; y.time! += 1.2; y.ivs = IVs(atk: 7, def: 7, hp: 7); y.ivConfidence = 0.8; four.append(y) } }
        }
        let four4 = labelled(four)
        let b4 = try sharedEngine.finish(readings: four4)
        let r4 = try Refine.splitByBars(b4, readings: four4, engine: sharedEngine, hintPeriod: 1.2)
        XCTAssertEqual(r4.scan.rows.filter { $0.display == "Charmander" && $0.cp == 12 }.count, 1, "four states: not cut")
        // the row does have four states: a limit of four cuts it
        XCTAssertEqual(try Refine.splitByBars(b4, readings: four4, engine: sharedEngine, hintPeriod: 1.2, maxStates: 4).scan.rows.filter { $0.display == "Charmander" && $0.cp == 12 }.count, 4)
    }

    // MARK: 1b, bars below the settled confidence count when the cut is on the command's beat

    /// run23's Fidough 768 / 89: 15/5/10 once, 15/4/10 twice, then 15/11/12 three times at confidence 0.696 (under the 0.7 floor). The cut falls exactly 1.2 s from both boundaries.
    func testBarsBelowTheSettledConfidenceCutOnTheBeat() throws {
        let o = try run("run23-fidough-twin.replay.jsonl", paging: hint)
        let f = rows(o, "Fidough", cp: 768)
        XCTAssertEqual(f.map(\.ivs), [IVs(atk: 15, def: 4, hp: 10), IVs(atk: 15, def: 11, hp: 12)])
        XCTAssertTrue(f.allSatisfy { $0.flags.contains("split-by-bars") })
        XCTAssertFalse(f[1].flags.contains("same-as-previous"), "different Pokemon, not a repeat")
        XCTAssertTrue(o.changes.contains { $0.kind == .barsSplit && $0.detail.contains("below the settled confidence") })
        // the confidence floor is not lowered: without the command's period the same row stays one (the strict rule sees one state)
        let none = try run("run23-fidough-twin.replay.jsonl", paging: nil)
        XCTAssertEqual(rows(none, "Fidough", cp: 768).count, 1)
        let handPaged = try run("run23-fidough-twin.replay.jsonl", paging: PagingHint(pagedByCommand: false))
        XCTAssertEqual(rows(handPaged, "Fidough", cp: 768).count, 1)
    }

    /// The same readings with everything after the second state moved 0.8 s later: the cut is no longer a whole number of periods from the row's boundaries, so the weak bars do not cut.
    func testWeakBarsOffTheBeatDoNotCut() throws {
        var readings = try ReplayReadings.load(url: Fixture.url("run23-fidough-twin.replay.jsonl")).readings
        let weak = try XCTUnwrap(readings.first { $0.name == "Fidough" && $0.ivs == IVs(atk: 15, def: 11, hp: 12) }?.time)
        for i in readings.indices where readings[i].time! >= weak { readings[i].time! += 0.8 }
        let base = try sharedEngine.finish(readings: readings)
        let r = try Refine.apply(to: base, readings: readings, ticks: [], engine: sharedEngine, paging: hint)
        XCTAssertEqual(r.scan.rows.filter { $0.display == "Fidough" && $0.cp == 768 }.count, 1)
        XCTAssertFalse(r.changes.contains { $0.kind == .barsSplit && $0.detail.contains("Fidough") })
    }

    // MARK: 1c, identical readings beside an irregular neighbourhood

    /// run23's Staraptor 1986 / 139 / 15/13/11: six readings, identical bars, a stay of 2.4 s on a 1.2 s beat. The left neighbourhood is irregular (a folded digit misread and a one-reading Zapdos row:
    /// side median 1.4 s), the right one is exactly 1.2 s.
    func testTwoIdenticalPokemonBesideAnIrregularNeighbourhoodAreSplitByTheCommandsPeriod() throws {
        let o = try run("run23-staraptor-twin-and-blanks.replay.jsonl", paging: hint)
        let s = rows(o, "Staraptor", cp: 1986).filter { $0.hp == 139 }
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s.map(\.ivs), [IVs(atk: 15, def: 13, hp: 11), IVs(atk: 15, def: 13, hp: 11)])
        XCTAssertEqual(s.map { $0.flags.contains("split-by-timing") }, [false, true])
        XCTAssertTrue(s[1].flags.contains("same-as-previous"))
        XCTAssertTrue(o.changes.contains { $0.kind == .timingSplit && $0.detail.contains("Staraptor CP 1986") })
        // without the command's period (or paged by hand) the irregular side still blocks it, as before round 31
        XCTAssertEqual(rows(try run("run23-staraptor-twin-and-blanks.replay.jsonl", paging: PagingHint(pagedByCommand: true)), "Staraptor", cp: 1986).filter { $0.hp == 139 }.count, 1)
        XCTAssertEqual(rows(try run("run23-staraptor-twin-and-blanks.replay.jsonl", paging: nil), "Staraptor", cp: 1986).filter { $0.hp == 139 }.count, 1)
        XCTAssertEqual(rows(try run("run23-staraptor-twin-and-blanks.replay.jsonl", paging: PagingHint(pagedByCommand: false, expectedPeriod: 1.2)), "Staraptor", cp: 1986).filter { $0.hp == 139 }.count, 1)
    }

    /// The guards that keep a card that merely stayed out: a row that touches a pause, a stay of three periods (`timingMaxCopies` is 2), and a stay that its own readings do not fill.
    func testStallsAndPausesAreNotSplitByThePeriod() throws {
        let l = try ReplayReadings.load(url: Fixture.url("run23-staraptor-twin-and-blanks.replay.jsonl"))
        func refine(_ readings: [FrameReading], _ paging: PagingHint) throws -> Refine.Refined {
            try Refine.apply(to: try sharedEngine.finish(readings: readings), readings: readings, ticks: l.ticks, engine: sharedEngine, paging: paging)
        }
        func twins(_ r: Refine.Refined) -> Int { r.scan.rows.filter { $0.display == "Staraptor" && $0.cp == 1986 && $0.hp == 139 }.count }
        XCTAssertEqual(twins(try refine(l.readings, hint)), 2, "the control: split")
        // 1. the stay touches a pause (the extension waited there on purpose)
        var paused = hint; paused.pauses = [119474.0...119475.0]
        XCTAssertEqual(twins(try refine(l.readings, paused)), 1, "a pause")
        // 2. three periods: the card's readings run on for another period (three more readings) and everything after moves 1.2 s later
        var longer = l.readings
        let own = longer.indices.filter { longer[$0].name == "Staraptor" && longer[$0].time! > 119473.7 && longer[$0].time! < 119476 }
        XCTAssertEqual(own.count, 6)
        let extra = own.suffix(3).map { i -> FrameReading in var r = longer[i]; r.time! += 1.2; r.frame = "x\(i)"; return r }
        let last = longer[own.last!].time!
        for i in longer.indices where longer[i].time! > last { longer[i].time! += 1.2 }
        longer.insert(contentsOf: extra, at: own.last! + 1)
        XCTAssertEqual(twins(try refine(longer, hint)), 1, "a stay of three periods")
        // 3. the stay is about 2.4 s but the card's own readings span 1.2 s of it (an unread stretch or dropped frames beside it): its last two readings are gone and the cards after it come 0.8 s later
        var thin = l.readings
        let gone = Set(own.suffix(2).map { thin[$0].frame })
        thin.removeAll { gone.contains($0.frame) }
        let cut = l.readings[own[3]].time!
        for i in thin.indices where thin[i].time! > cut { thin[i].time! += 0.8 }
        XCTAssertEqual(twins(try refine(thin, hint)), 1, "readings that do not fill the stay")
    }

    // MARK: 2a, cards on screen that were not read

    func testBlankStretchesBecomeUnreadCardsWithTheirNeighboursCps() throws {
        let o = try run("run23-staraptor-twin-and-blanks.replay.jsonl", paging: hint)
        let blank = o.scan.unmatched.filter { $0.reason == BlankCards.reason }
        XCTAssertEqual(blank.map { $0.count }, [1, 3, 2])
        XCTAssertEqual(blank.map { $0.cpBefore }, [1992, 1967, 1920]); XCTAssertEqual(blank.map { $0.cpAfter }, [1987, 1961, 1913])
        // nothing without command paging
        for paging in [nil, PagingHint(pagedByCommand: false, expectedPeriod: 1.2), PagingHint(pagedByCommand: true)] {
            XCTAssertTrue(try run("run23-staraptor-twin-and-blanks.replay.jsonl", paging: paging).scan.unmatched.allSatisfy { $0.reason != BlankCards.reason })
        }
        // an old saved scan (no count or bounds) still decodes
        let old = #"{"frame":"r1","frames":3,"reason":"name-not-read","cp":282}"#
        let u = try JSONDecoder().decode(Unmatched.self, from: Data(old.utf8))
        XCTAssertNil(u.count); XCTAssertNil(u.cpBefore)
    }

    private func card(_ t: Double, cp: Int) -> FrameReading { var r = FrameReading(frame: "c\(Int(t * 100))", time: t); r.nameText = "Pidgey"; r.cpText = "CP\(cp)"; r.hpText = "50 / 50 HP"; return r }
    private func blankReading(_ t: Double) -> FrameReading { FrameReading(frame: "b\(Int(t * 100))", time: t) }
    private func rowAt(_ index: Int, cp: Int, from a: Double, to b: Double) -> ScanRow {
        ScanRow(index: index, name: "Pidgey", display: "Pidgey", form: "", speciesId: "pidgey", dex: 16, cp: cp, hp: 50, ivs: IVs(atk: 1, def: 2, hp: 3), ivsRead: IVs(atk: 1, def: 2, hp: 3), ivsGuess: nil, level: 20, levelMax: 20, dust: 0, solveStatus: "exact", flags: [],
                frames: stride(from: a, through: b, by: 0.4).map { FrameLabel(frame: "c\(Int($0 * 100))", time: $0, cp: cp, cpText: "\(cp)", name: "Pidgey", hp: "50/50", ivs: "1/2/3", ivConfidence: 0.9, sharpness: 1, clip: nil) })
    }

    /// What is not counted: the readings before the first and after the last card, a stretch with the same row on both sides (a menu open on one Pokémon), a stretch inside a pause, one under 0.8 of a period.
    func testBlankStretchesThatAreNotCards() {
        let rowsAB = [rowAt(1, cp: 900, from: 10, to: 10.8), rowAt(2, cp: 800, from: 13.2, to: 14.0)]
        func readings(blank: ClosedRange<Double>, step: Double = 0.2, leading: Bool = false, trailing: Bool = false) -> [FrameReading] {
            var rs = [FrameReading]()
            if leading { rs += stride(from: 7.0, to: 9.8, by: 0.2).map(blankReading) }
            rs += stride(from: 10.0, through: 10.8, by: 0.4).map { card($0, cp: 900) }
            rs += stride(from: blank.lowerBound, through: blank.upperBound, by: step).map(blankReading)
            rs += stride(from: 13.2, through: 14.0, by: 0.4).map { card($0, cp: 800) }
            if trailing { rs += stride(from: 14.2, to: 17.0, by: 0.2).map(blankReading) }
            return rs
        }
        // two periods of blank between the rows: two cards
        let two = BlankCards.find(readings: readings(blank: 11.0...13.0), rows: rowsAB, paging: hint)
        XCTAssertEqual(two.count, 1); XCTAssertEqual(two.first?.count, 2); XCTAssertEqual(two.first?.cpBefore, 900); XCTAssertEqual(two.first?.cpAfter, 800)
        // leading and trailing blanks (before the first card, after the last) are not cards
        XCTAssertEqual(BlankCards.find(readings: readings(blank: 11.0...13.0, leading: true, trailing: true), rows: rowsAB, paging: hint).count, 1)
        XCTAssertTrue(BlankCards.find(readings: readings(blank: 11.0...11.0, leading: true, trailing: true), rows: rowsAB, paging: hint).isEmpty, "a short gap, leading and trailing blanks alone")
        // under 0.8 of a period
        XCTAssertTrue(BlankCards.find(readings: readings(blank: 11.0...11.4), rows: rowsAB, paging: hint).isEmpty)
        // a pause covering the stretch
        var paused = hint; paused.pauses = [10.8...13.2]
        XCTAssertTrue(BlankCards.find(readings: readings(blank: 11.0...13.0), rows: rowsAB, paging: paused).isEmpty)
        // a menu on one Pokémon: the same row on both sides of the blank (and another row after it, so only the row test can refuse it)
        let menuRows = [rowAt(1, cp: 900, from: 10, to: 14.0), rowAt(2, cp: 800, from: 15.0, to: 15.8)]
        var menu = readings(blank: 11.0...13.0); for i in menu.indices where menu[i].cpText == "CP800" { menu[i].cpText = "CP900" }
        menu += stride(from: 15.0, through: 15.8, by: 0.4).map { card($0, cp: 800) }
        XCTAssertTrue(BlankCards.find(readings: menu, rows: menuRows, paging: hint).isEmpty)
        // no command paging, no period
        XCTAssertTrue(BlankCards.find(readings: readings(blank: 11.0...13.0), rows: rowsAB, paging: nil).isEmpty)
        XCTAssertTrue(BlankCards.find(readings: readings(blank: 11.0...13.0), rows: rowsAB, paging: PagingHint(pagedByCommand: true)).isEmpty)
    }

    // MARK: 2b, the merge

    /// A scan of 40 rows in CP order (highest first), the box holding all of them plus Pokémon of other species at CPs between and outside the bounds of a blank stretch.
    private func orderedScan(descending: Bool = true) -> [ScanRow] {
        let cps = (0..<40).map { 3000 - $0 * 20 }
        let rs = cps.enumerated().map { rowAt($0.offset + 1, cp: $0.element, from: Double($0.offset) * 2, to: Double($0.offset) * 2 + 0.8) }
        return descending ? rs : rs.reversed()
    }
    private func box(_ rows: [ScanRow], extra: [(String, String, Int, Int)]) -> [BoxEntry] {
        var out = rows.enumerated().map { BoxEntry(id: "r\($0.offset)", row: $0.element, firstSeen: date(0), lastSeen: date(0)) }
        for (id, species, cp, hp) in extra {
            let nf = GameMaster.nameAndForm(gm.byId[species]?.name ?? species)
            let r = ScanRow(index: 0, name: nf.name, display: nf.name, form: nf.form, speciesId: species, dex: gm.byId[species]?.dex, cp: cp, hp: hp, ivs: IVs(atk: 5, def: 5, hp: 5), ivsRead: nil, ivsGuess: nil, level: 20, levelMax: 20, dust: 0, solveStatus: "exact", flags: [], frames: [])
            out.append(BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0)))
        }
        return out
    }
    private func blankItem(count: Int, before: Int, after: Int) -> Unmatched {
        Unmatched(frame: "b1", cp: nil, name: nil, nameText: nil, hp: nil, ivs: nil, cpOptions: nil, frames: count * 6, reason: BlankCards.reason, into: nil, clip: nil, count: count, cpBefore: before, cpAfter: after)
    }

    func testAnEntryInsideTheBoundsOfABlankStretchIsOnScreenUnreadNotNotSeen() throws {
        let rows = orderedScan()
        XCTAssertEqual(BlankCards.cpOrder(rows), .descending); XCTAssertEqual(BlankCards.cpOrder(orderedScan(descending: false)), .ascending)
        // the stretch lies between 2000 and 1980 and holds two cards: two saved entries are inside, one is above and one below
        let b = box(rows, extra: [("in1", "zapdos", 1995, 130), ("in2", "moltres", 1990, 131), ("above", "articuno", 2500, 120), ("below", "zapdos", 100, 40)])
        let items = [blankItem(count: 2, before: 2000, after: 1980)]
        let p = BoxMerge.plan(scanned: rows, unmatched: items, into: b, kind: .full, scanDate: date(1), gameMaster: gm)
        XCTAssertEqual(Set(p.unreadEntries.map(\.id)), ["in1", "in2"])
        XCTAssertEqual(Set(p.gone), ["above", "below"], "only entries outside every stretch are Not seen")
        let report = BoxMerge.goneReport(p, resolutions: [:])
        XCTAssertEqual(Set(report.onScreenUnread), ["in1", "in2"]); XCTAssertEqual(Set(report.gone), ["above", "below"])
        // never on a removal list: the app marks exactly goneReport.gone for removal
        XCTAssertTrue(Set(report.gone).isDisjoint(with: report.onScreenUnread))
        let after = try BoxMerge.apply(p, resolutions: [:], keepGone: BoxMerge.keepSet(plan: p, resolutions: [:], markedForRemoval: Set(report.gone)), to: b)
        XCTAssertEqual(Set(after.map(\.id)), Set(b.map(\.id)).subtracting(["above", "below"]), "only the marked ones are removed, never an unread one")
        // the line counts the cards; both have an entry kept out of the list, so it no longer says entries below may be those (round 32: they are not below)
        XCTAssertEqual(BoxMerge.unreadLine(p), "2 cards on screen could not be read. Each has a saved entry kept out of the Not seen list, under \"On screen but not read\".")
        // an add-and-update scan lists and removes nothing
        let part = BoxMerge.plan(scanned: rows, unmatched: items, into: b, kind: .partial, scanDate: date(1), gameMaster: gm)
        XCTAssertTrue(part.unreadEntries.isEmpty); XCTAssertTrue(part.gone.isEmpty)
    }

    func testMoreEntriesThanCardsInTheBoundsStayNotSeen() {
        let rows = orderedScan()
        let b = box(rows, extra: [("a", "zapdos", 1995, 130), ("b", "moltres", 1990, 131), ("c", "articuno", 1985, 120)])
        let p = BoxMerge.plan(scanned: rows, unmatched: [blankItem(count: 2, before: 2000, after: 1980)], into: b, kind: .full, scanDate: date(1), gameMaster: gm)
        XCTAssertTrue(p.unreadEntries.isEmpty, "three entries, two cards: nothing says which two were there")
        XCTAssertEqual(Set(p.gone), ["a", "b", "c"])
    }

    func testRowsNotInCpOrderUseTheCountOnly() {
        // the same 40 rows, every second one swapped with its neighbour pair-wise far apart: neither order
        var rows = orderedScan()
        for i in stride(from: 0, to: 38, by: 4) { rows.swapAt(i, i + 2) }
        XCTAssertNil(BlankCards.cpOrder(rows))
        let b = box(rows, extra: [("a", "zapdos", 1995, 130)])
        let items = [blankItem(count: 1, before: 2000, after: 1980)]
        let p = BoxMerge.plan(scanned: rows, unmatched: items, into: b, kind: .full, scanDate: date(1), gameMaster: gm)
        XCTAssertTrue(p.unreadEntries.isEmpty); XCTAssertEqual(p.gone, ["a"])
        XCTAssertNotNil(BoxMerge.unreadLine(p), "the count is still told")
        // bounds that run against the order of the rows mean nothing either
        let wrong = BoxMerge.plan(scanned: orderedScan(), unmatched: [blankItem(count: 1, before: 1980, after: 2000)], into: box(orderedScan(), extra: [("a", "zapdos", 1995, 130)]), kind: .full, scanDate: date(1), gameMaster: gm)
        XCTAssertTrue(wrong.unreadEntries.isEmpty)
    }

    /// run23's Charizard: a name and an HP, the CP never read. Saved entries of that name and HP are on screen unread; another HP is not.
    func testAnItemWithANameAndAnHpButNoCpKeepsEntriesOfThatNameAndHpOutOfNotSeen() {
        let rows = orderedScan()
        let b = box(rows, extra: [("hit", "charizard", 1607, 118), ("otherHP", "charizard", 1700, 130), ("otherName", "venusaur", 1600, 118)])
        let item = Unmatched(frame: "r322", cp: nil, name: "Charizard", nameText: "Charizard", hp: 118, ivs: nil, cpOptions: [], frames: 3, reason: "cp-not-read", into: nil, clip: nil)
        let p = BoxMerge.plan(scanned: rows, unmatched: [item], into: b, kind: .full, scanDate: date(1), gameMaster: gm)
        XCTAssertEqual(p.unreadEntries.map(\.id), ["hit"])
        XCTAssertEqual(Set(p.gone), ["otherHP", "otherName"])
        XCTAssertEqual(BoxMerge.goneReport(p, resolutions: [:]).onScreenUnread, ["hit"])
    }

    // MARK: 3a, a part read is never paired automatically to an entry of another form

    private func entry(_ id: String, species: String, cp: Int, hp: Int, ivs: IVs = IVs(atk: 10, def: 10, hp: 10)) -> BoxEntry {
        let nf = GameMaster.nameAndForm(gm.byId[species]?.name ?? species)
        let r = ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: species, dex: gm.byId[species]?.dex, cp: cp, hp: hp, ivs: ivs, ivsRead: ivs, ivsGuess: nil, level: 20, levelMax: 20, dust: 0, solveStatus: "exact", flags: [], frames: [])
        return BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0))
    }
    private func untrusted(species: String, display: String, raw: String, cp: Int, hp: Int) -> ScanRow {
        ScanRow(index: 1, name: display, display: display, form: "", speciesId: species, dex: gm.byId[species]?.dex, cp: cp, hp: hp, ivs: nil, ivsRead: nil, ivsGuess: nil, level: nil, levelMax: nil, dust: nil, solveStatus: "none", flags: ["no-level-fits"],
                frames: [FrameLabel(frame: "f1", time: 1, cp: cp, cpText: String(cp), name: raw, hp: "\(hp)/\(hp)", ivs: nil, ivConfidence: 0, sharpness: 1, clip: nil)])
    }

    /// Reviewer case C2: a part read of Tauros, Darmanitan, Thundurus or Giratina beside the owner's entry of another form is a question (the candidate list accepts any form the name could be), never a silent pairing.
    func testAPartReadBesideAnEntryOfAnotherFormIsAQuestionNotAPairing() throws {
        let ten = IVs(atk: 10, def: 10, hp: 10)
        for (display, first, other) in [("Tauros", "tauros", "tauros_blaze"), ("Darmanitan", "darmanitan_standard", "darmanitan_galarian_zen"), ("Thundurus", "thundurus_incarnate", "thundurus_therian"), ("Giratina", "giratina_altered", "giratina_origin")] {
            let b = try XCTUnwrap(gm.byId[other]?.baseStats)
            let cp = cpAt(b, ten, 30), hp = hpAt(b, ten, 30)
            let e = entry("other", species: other, cp: cp, hp: hp)
            let part = Int(String(String(cp).dropFirst()))!
            let row = untrusted(species: first, display: display, raw: display, cp: part, hp: hp)
            for kind in [BoxStore.Kind.full, .partial] {
                let p = BoxMerge.plan(scanned: [row], into: [e], kind: kind, scanDate: date(1), gameMaster: gm)
                XCTAssertTrue(p.same.isEmpty && p.partMatches.isEmpty && p.new.isEmpty, "\(display) \(kind): \(p.same) \(p.new)")
                let u = try XCTUnwrap(p.unsure.first, "\(display) \(kind)")
                XCTAssertEqual(u.candidates, ["other"]); XCTAssertEqual(u.kind, .partialRead)
            }
        }
        // the strict test still pairs a part read of the SAME form id automatically (a sole candidate, HP, digits, no contradicting bars)
        let b = try XCTUnwrap(gm.byId["tauros_blaze"]?.baseStats)
        let cp = cpAt(b, ten, 30), hp = hpAt(b, ten, 30)
        let same = BoxMerge.plan(scanned: [untrusted(species: "tauros_blaze", display: "Tauros", raw: "Tauros", cp: Int(String(String(cp).dropFirst()))!, hp: hp)], into: [entry("own", species: "tauros_blaze", cp: cp, hp: hp)], kind: .full, scanDate: date(1), gameMaster: gm)
        XCTAssertEqual(same.partMatches.map(\.savedId), ["own"]); XCTAssertTrue(same.unsure.isEmpty)
    }

    // MARK: 3b, Nidoran

    /// Reviewer case C1: a Nidoran whose symbol WAS read is not offered or paired with the other sex's entry. One whose symbol was not read (the device never reads it) is asked.
    func testANidoranWhoseSymbolWasReadIsNeverOfferedTheOtherSex() throws {
        let ten = IVs(atk: 10, def: 10, hp: 10)
        let m = try XCTUnwrap(gm.byId["nidoran_male"]?.baseStats)
        let mcp = cpAt(m, ten, 25), mhp = hpAt(m, ten, 25)
        let male = entry("male", species: "nidoran_male", cp: mcp, hp: mhp)
        let part = Int(String(String(mcp).dropFirst()))!
        let female = untrusted(species: "nidoran_female", display: "Nidoran", raw: "Nidoran♀", cp: part, hp: mhp)
        for kind in [BoxStore.Kind.full, .partial] {
            let p = BoxMerge.plan(scanned: [female], into: [male], kind: kind, scanDate: date(1), gameMaster: gm)
            XCTAssertEqual(p.new, [0], "\(kind): a female part read of a male entry is another Pokémon")
            XCTAssertTrue(p.same.isEmpty && p.unsure.isEmpty && p.partMatches.isEmpty)
        }
        // the symbol read as male: the male entry is the candidate (a question, not a pairing: the id is the first sex, not the entry's)
        let readMale = untrusted(species: "nidoran_female", display: "Nidoran", raw: "Nidoran♂", cp: part, hp: mhp)
        let q = BoxMerge.plan(scanned: [readMale], into: [male], kind: .full, scanDate: date(1), gameMaster: gm)
        XCTAssertEqual(q.unsure.first?.candidates, ["male"]); XCTAssertTrue(q.same.isEmpty && q.new.isEmpty)
        // the device's reality: the symbol was not read ("Nidoran f /"): a question with the entry, never an automatic pairing
        let unread = untrusted(species: "nidoran_female", display: "Nidoran", raw: "Nidoran f /", cp: part, hp: mhp)
        let u = BoxMerge.plan(scanned: [unread], into: [male], kind: .full, scanDate: date(1), gameMaster: gm)
        XCTAssertTrue(u.same.isEmpty && u.partMatches.isEmpty && u.new.isEmpty)
        XCTAssertEqual(u.unsure.first?.candidates, ["male"])
    }

    private func fragRow(_ i: Int, display: String, cp: Int, raw: String, times: [Double], fits: Bool) -> ScanRow {
        let bars = IVs(atk: 12, def: 13, hp: 10)
        return ScanRow(index: i, name: display, display: display, form: "", speciesId: "pidgey", dex: 16, cp: cp, hp: 50, ivs: fits ? bars : nil, ivsRead: bars, ivsGuess: nil, level: fits ? 20 : nil, levelMax: fits ? 20 : nil, dust: 0, solveStatus: fits ? "exact" : "none", flags: fits ? [] : ["no-level-fits"],
                       frames: times.map { FrameLabel(frame: "g\(Int($0 * 1000))", time: $0, cp: cp, cpText: String(cp), name: raw, hp: "50/50", ivs: "12/13/10", ivConfidence: 0.9, sharpness: 1, clip: nil) })
    }
    private func fold(_ rows: [ScanRow]) -> [ScanRow] { Refine.absorbFragments(ScanResult(rows: rows, review: [], unmatched: [])).scan.rows }

    /// The Nidoran symbol check in `sameScreenName` applies to the Nidoran screen name only: a raw text with a symbol on another species is no evidence of anything.
    func testTheNidoranSymbolCheckAppliesOnlyToNidoran() {
        func pidgey(_ i: Int, _ t: Double) -> ScanRow { fragRow(i, display: "Pokémon", cp: 500, raw: "Pokémon", times: [t, t + 0.4, t + 0.8], fits: true) }
        let frag = fragRow(2, display: "Pidgey", cp: 9017, raw: "Pidgey♀", times: [5.0], fits: false)
        let card = fragRow(3, display: "Pidgey", cp: 2017, raw: "Pidgey♂", times: [5.8, 6.2], fits: true)
        XCTAssertEqual(fold([pidgey(1, 0), frag, card, pidgey(4, 20)]).count, 3, "folded: the symbols mean nothing on a Pidgey")
        // a Nidoran with different symbols read is still two
        let nf = fragRow(2, display: "Nidoran", cp: 9017, raw: "Nidoran♀", times: [5.0], fits: false)
        let nc = fragRow(3, display: "Nidoran", cp: 2017, raw: "Nidoran♂", times: [5.8, 6.2], fits: true)
        XCTAssertEqual(fold([pidgey(1, 0), nf, nc, pidgey(4, 20)]).count, 4)
    }

    // MARK: 3c, a one-reading fragment beside its own card

    /// Reviewer case C5: a fragment of one reading with no bars read, beside a card it could be a one-digit misread of, is not folded (the fold rules are unchanged); when the card is a NEW catch
    /// both would be added, so the fragment's row carries a check flag naming the card.
    func testAOneReadingFragmentWithNoBarsBesideItsCardIsFlaggedToCheck() throws {
        func pidgey(_ i: Int, _ t: Double) -> ScanRow { fragRow(i, display: "Pidgey", cp: 500, raw: "Pidgey", times: [t, t + 0.4, t + 0.8], fits: true) }
        func charizard(_ i: Int, cp: Int, times: [Double], fits: Bool, bars: Bool) -> ScanRow { var r = fragRow(i, display: "Charizard", cp: cp, raw: "Charizard", times: times, fits: fits); if !bars { r.ivsRead = nil }; return r }
        let frag = charizard(2, cp: 9017, times: [5.0], fits: false, bars: false), card = charizard(3, cp: 2017, times: [5.8, 6.2], fits: true, bars: true)
        let rows = fold([pidgey(1, 0), frag, card, pidgey(4, 20)])
        XCTAssertEqual(rows.count, 4, "not folded")
        let f = try XCTUnwrap(rows.first { $0.cp == 9017 })
        XCTAssertTrue(f.flags.contains("misread-of-neighbour:2017"), "\(f.flags)")
        XCTAssertTrue(f.needsCheck)
        XCTAssertTrue(FlagInfo.explain("misread-of-neighbour:2017").contains("2017"))
        XCTAssertEqual(FlagInfo.severity(of: "misread-of-neighbour:2017", solveStatus: "none"), .check)
        XCTAssertFalse(try XCTUnwrap(rows.first { $0.cp == 2017 }).flags.contains { $0.hasPrefix("misread-of-neighbour") })
        // not flagged: bars read (the fold rule decides), two readings, a CP that is not one digit apart
        let withBars = fold([pidgey(1, 0), charizard(2, cp: 9017, times: [5.0], fits: false, bars: true), card, pidgey(4, 20)])
        XCTAssertFalse(withBars.contains { $0.flags.contains { $0.hasPrefix("misread-of-neighbour") } }, "bars read: folded or not, but not this flag")
        let two = fold([pidgey(1, 0), charizard(2, cp: 9017, times: [4.6, 5.0], fits: false, bars: false), card, pidgey(4, 20)])
        XCTAssertFalse(two.contains { $0.flags.contains { $0.hasPrefix("misread-of-neighbour") } })
        let far = fold([pidgey(1, 0), charizard(2, cp: 9999, times: [5.0], fits: false, bars: false), card, pidgey(4, 20)])
        XCTAssertFalse(far.contains { $0.flags.contains { $0.hasPrefix("misread-of-neighbour") } })
    }
}
