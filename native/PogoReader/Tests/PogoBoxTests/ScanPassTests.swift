import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// Filtered passes: the optional `pass` field, the mark rule in `apply`, hand values that outrank a pass, and the mistyped-search guard.
final class ScanPassTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private func date(_ day: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(day) * 86_400) }
    private func row(_ speciesId: String = "pidgey", cp: Int = 300, ivs: IVs? = IVs(atk: 10, def: 11, hp: 12), hp: Int? = 50) -> ScanRow {
        let sp = gm.byId[speciesId]
        let nf = GameMaster.nameAndForm(sp?.name ?? speciesId)
        return ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: speciesId, dex: sp?.dex, cp: cp, hp: hp, ivs: ivs, ivsRead: ivs, ivsGuess: nil,
                       level: 10, levelMax: 10, dust: 1000, solveStatus: "exact", flags: [], frames: [])
    }
    private func entry(_ r: ScanRow, id: String) -> BoxEntry { BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0)) }
    private func plan(_ scanned: [ScanRow], _ saved: [BoxEntry], _ pass: ScanPass?, kind: BoxStore.Kind = .partial) -> BoxMerge.Plan {
        BoxMerge.plan(scanned: scanned, into: saved, kind: kind, scanDate: date(10), gameMaster: gm, pass: pass)
    }
    private func mark(_ e: BoxEntry, _ pass: ScanPass) -> Bool? {
        switch pass {
        case .dynamax: return e.row.dynamax
        case .gigantamax: return e.row.gigantamax
        case .shadow: return e.row.shadow == 1
        case .purified: return e.row.shadow == 2
        }
    }
    private func byId(_ es: [BoxEntry]) -> [String: BoxEntry] { Dictionary(es.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }

    // MARK: - the field

    func testOldJsonWithoutPassDecodes() throws {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let scan = try d.decode(BoxStore.StoredScan.self, from: Data(contentsOf: Self.fixture("greg-dynamax-pass-2026-10-25.result.json")))
        XCTAssertNil(scan.pass, "the real export predates passes")
        let meta = try d.decode(PendingScanMeta.self, from: Data(#"{"signature":"1-2","account":"A"}"#.utf8))
        XCTAssertNil(meta.pass)
        XCTAssertNil(ScanPass(stored: nil)); XCTAssertNil(ScanPass(stored: "unknown-future-pass"))
        XCTAssertEqual(ScanPass(stored: "gigantamax"), .gigantamax)
    }

    func testAPassIsStoredAndSavedAsPartial() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pass-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BoxStore(root: root)
        let summary = try store.save(ScanResult(rows: [row()], review: [], unmatched: []), account: "A", source: "test", kind: .partial, pass: "dynamax")
        XCTAssertEqual(summary.pass, "dynamax"); XCTAssertEqual(summary.kind, .partial)
        XCTAssertEqual(try store.load(account: "A", id: summary.id).pass, "dynamax")
        XCTAssertEqual(try store.list(account: "A").scans.first?.pass, "dynamax")
        // Even asked for as a full scan, a pass plan removes nothing.
        let p = plan([row()], [entry(row("rattata"), id: "gone")], .dynamax, kind: .full)
        XCTAssertEqual(p.kind, .partial)
        XCTAssertTrue(BoxMerge.goneReport(p, resolutions: [:]).gone.isEmpty)
    }

    // MARK: - the mark rule

    func testEachPassMarksSameUpdatedConfirmedAndNewRowsAndLeavesTheRestAlone() throws {
        for pass in ScanPass.allCases {
            let same = row("pidgey", cp: 300), noIVs = row("rattata", cp: 200, ivs: nil), powered = row("pidgeotto", cp: 500, ivs: IVs(atk: 1, def: 2, hp: 3))
            let left = row("weedle", cp: 100, ivs: IVs(atk: 4, def: 5, hp: 6)), unseen = row("caterpie", cp: 90)
            let saved = [entry(same, id: "same"), entry(noIVs, id: "updated"), entry(powered.withCP(400), id: "powered"), entry(left, id: "left"), entry(unseen, id: "unseen")]
            var scannedNoIVs = noIVs; scannedNoIVs.ivs = IVs(atk: 9, def: 9, hp: 9); scannedNoIVs.ivsRead = scannedNoIVs.ivs
            let scanned = [same, scannedNoIVs, powered, left.withCP(150), row("zubat", cp: 123)]
            let p = plan(scanned, saved, pass)
            XCTAssertEqual(p.same.map(\.savedId), ["same"]); XCTAssertEqual(p.updated.map(\.savedId), ["updated"])
            XCTAssertEqual(p.new.count, 1)
            let questions = Dictionary(uniqueKeysWithValues: p.unsure.map { ($0.candidates[0], $0.scanned) })
            XCTAssertEqual(Set(questions.keys), ["powered", "left"])
            let res: [Int: BoxMerge.Resolution] = [questions["powered"]!: .existing("powered"), questions["left"]!: .leaveOut]
            let out = byId(try BoxMerge.apply(p, resolutions: res, to: saved, engine: nil))
            for id in ["same", "updated", "powered"] { XCTAssertEqual(mark(out[id]!, pass), true, "\(pass) \(id)") }
            XCTAssertNotEqual(mark(out["left"]!, pass), true, "Leave out marks nothing")
            XCTAssertNotEqual(mark(out["unseen"]!, pass), true, "an unseen Pokémon is never changed")
            XCTAssertEqual(out["unseen"]!, saved[4]); XCTAssertEqual(out["left"]!.row.cp, 100)
            let added = out.values.filter { !saved.map(\.id).contains($0.id) }
            XCTAssertEqual(added.count, 1); XCTAssertEqual(mark(added[0], pass), true, "a new row is added, marked")
            if pass == .gigantamax { for id in ["same", "updated", "powered"] { XCTAssertEqual(out[id]!.row.dynamax, true, "Gigantamax implies Dynamax") }; XCTAssertEqual(added[0].row.dynamax, true) }
            if pass == .dynamax { XCTAssertNil(out["same"]!.row.gigantamax) }
            let t = BoxMerge.passTally(p, resolutions: res, base: saved)
            XCTAssertEqual(t, BoxMerge.PassTally(marked: 3, new: 1, conflicts: 0, unanswered: 0))
        }
    }

    func testAnOrdinaryPlanMarksNothing() throws {
        let saved = [entry(row(), id: "a")]
        let out = try BoxMerge.apply(plan([row()], saved, nil), to: saved, engine: nil)
        XCTAssertNil(out[0].row.dynamax); XCTAssertNil(out[0].row.shadow)
    }

    // MARK: - hand values win

    private func handShadow(_ e: BoxEntry, _ v: BoxMerge.ShadowEdit) throws -> BoxEntry { try BoxMerge.correct(e, with: BoxMerge.Edit(shadow: v), gameMaster: gm) }

    func testAHandValueIsKeptAndRaisesAPassConflict() throws {
        let cases: [(ScanPass, BoxMerge.ShadowEdit, Int)] = [(.shadow, .purified, 2), (.shadow, .neither, 0), (.purified, .shadow, 1), (.purified, .neither, 0)]
        for (pass, hand, value) in cases {
            let saved = [try handShadow(entry(row(), id: "a"), hand)]
            let p = plan([row()], saved, pass)
            let out = try BoxMerge.apply(p, to: saved, engine: nil)[0]
            XCTAssertEqual(out.row.shadow, value, "\(pass) over hand \(hand)")
            XCTAssertTrue(out.row.flags.contains(BoxMerge.conflictFlag(pass, saved: value)), "\(out.row.flags)")
            XCTAssertTrue(out.needsCheck, "a check item")
            XCTAssertEqual(FlagInfo.severity(of: BoxMerge.conflictFlag(pass, saved: value), solveStatus: "exact"), .check)
            XCTAssertEqual(BoxMerge.passTally(p, resolutions: [:], base: saved), BoxMerge.PassTally(marked: 0, new: 0, conflicts: 1, unanswered: 0))
        }
    }

    func testTheMergesCarryOverOfAScannedShadowDoesNotOverrideAHandValue() throws {
        // A saved entry with no IVs is updated when the scan reads them (`ivsNowRead`); that path keeps a saved mark and fills only a blank one.
        var noIVs = row("rattata", cp: 200, ivs: nil); noIVs.shadow = nil
        let saved = [try handShadow(entry(noIVs, id: "a"), .purified)]
        var scanned = row("rattata", cp: 200, ivs: IVs(atk: 9, def: 9, hp: 9)); scanned.shadow = 1
        let p = plan([scanned], saved, .shadow)
        XCTAssertEqual(p.updated.map(\.savedId), ["a"])
        XCTAssertEqual(BoxMerge.updated(saved[0], with: scanned, date: date(10)).row.shadow, 2, "the generic merge keeps the saved mark")
        let out = try BoxMerge.apply(p, to: saved, engine: nil)[0]
        XCTAssertEqual(out.row.shadow, 2, "the hand value stays")
        XCTAssertTrue(out.row.flags.contains("pass-conflict:shadow:purified"))
        XCTAssertEqual(out.row.ivs, IVs(atk: 9, def: 9, hp: 9), "the rest of the update still happens")
    }

    func testAPurifiedPassMovesAShadowThatAShadowPassSetWithoutAConflict() throws {
        let saved = [entry(row(), id: "a")]
        let first = try BoxMerge.apply(plan([row()], saved, .shadow), to: saved, engine: nil)
        XCTAssertEqual(first[0].row.shadow, 1); XCTAssertEqual(first[0].shadowByPass, true)
        let second = try BoxMerge.apply(plan([row()], first, .purified), to: first, engine: nil)
        XCTAssertEqual(second[0].row.shadow, 2); XCTAssertFalse(second[0].row.flags.contains { $0.hasPrefix("pass-conflict") })
        // The same Shadow value set by hand is not a pass's to change, and a hand edit clears the "set by a pass" record.
        let hand = try handShadow(first[0], .shadow)
        XCTAssertNil(hand.shadowByPass)
        let kept = try BoxMerge.apply(plan([row()], [hand], .purified), to: [hand], engine: nil)[0]
        XCTAssertEqual(kept.row.shadow, 1); XCTAssertTrue(kept.row.flags.contains("pass-conflict:purified:shadow"))
        // A pass meeting its own mark changes nothing and raises nothing.
        let again = try BoxMerge.apply(plan([row()], first, .shadow), to: first, engine: nil)[0]
        XCTAssertEqual(again.row.shadow, 1); XCTAssertTrue(again.row.flags.isEmpty)
        // A hand "Off" for Dynamax is not a conflict: off is "not marked", and a pass turns marks on.
        let off = try BoxMerge.correct(entry(row(), id: "b"), with: BoxMerge.Edit(dynamax: .off), gameMaster: gm)
        XCTAssertEqual(try BoxMerge.apply(plan([row()], [off], .dynamax), to: [off], engine: nil)[0].row.dynamax, true)
    }

    // MARK: - the mistyped-search guard

    func testTheGuardFiresAboveItsThresholdOnly() {
        XCTAssertFalse(PassGuard.fires(unmatched: 0, total: 0))
        XCTAssertFalse(PassGuard.fires(unmatched: 3, total: 10))
        XCTAssertTrue(PassGuard.fires(unmatched: 4, total: 10))
        let saved = [entry(row(), id: "a")]
        let rows = [row(), row("zubat", cp: 1), row("golbat", cp: 2), row("meowth", cp: 3)]
        XCTAssertTrue(BoxMerge.passSearchLooksWrong(plan(rows, saved, .shadow)))
        XCTAssertFalse(BoxMerge.passSearchLooksWrong(plan(rows, saved, nil)), "an ordinary scan is never asked")
    }

    /// Greg's own Dynamax pass of 25 Oct 2026 (61 rows) against his 22 Oct 2026 box (2125 Pokémon). 14 rows (23%) match no entry: 13 of them are species the box did not hold.
    func testTheGuardDoesNotFireOnTheRealDynamaxPass() throws {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let scan = try d.decode(BoxStore.StoredScan.self, from: Data(contentsOf: Self.fixture("greg-dynamax-pass-2026-10-25.result.json")))
        let box = try boxFromCSV(Self.fixture("greg-2026-10-22.box.csv"))
        XCTAssertGreaterThan(box.count, 2100)
        let p = BoxMerge.plan(scanned: scan.rows, into: box, kind: .partial, scanDate: scan.scanDate, gameMaster: gm, pass: .dynamax)
        XCTAssertEqual(scan.rows.count, 61)
        XCTAssertEqual(p.same.count + p.updated.count + p.unsure.count + p.new.count, 61)
        XCTAssertEqual(p.new.count, 14, "unmatched \(p.new.count) of 61, same \(p.same.count), unsure \(p.unsure.count)")
        XCTAssertFalse(BoxMerge.passSearchLooksWrong(p))
        // The row read as CP 66 is matched to a Moltres CP 1966 by its HP: a part read, so the pass does not mark it (P1).
        let part = try XCTUnwrap(p.partMatches.first)
        XCTAssertEqual(p.partMatches.count, 1)
        let answers = Dictionary(uniqueKeysWithValues: p.unsure.map { ($0.scanned, BoxMerge.Resolution.leaveOut) })
        let tally = BoxMerge.passTally(p, resolutions: answers, base: box)
        XCTAssertEqual(tally, BoxMerge.PassTally(marked: 45, new: 14, conflicts: 0, unanswered: 0), "46 Same pairs less the part read")
        let applied = byId(try BoxMerge.apply(p, resolutions: answers, to: box, engine: nil))
        XCTAssertNil(applied[part.savedId]?.row.dynamax, "the part-read match stays unmarked")
        XCTAssertEqual(applied.values.filter { $0.row.dynamax == true }.count, 45 + 14)
        // The same rows against an empty box are all new: a wrong search.
        XCTAssertTrue(BoxMerge.passSearchLooksWrong(BoxMerge.plan(scanned: scan.rows, into: [], kind: .partial, scanDate: scan.scanDate, gameMaster: gm, pass: .dynamax)))
    }

    // MARK: - review round 1

    func testAMegaPairJoinCarriesTheRemovedEntrysShadowMarkAndThePassIsJudgedAgainstIt() throws {
        func pair(_ removedShadow: Int, byPass: Bool?) -> [BoxEntry] {
            var base = entry(row("staraptor", cp: 2819), id: "base"); base.lastSeen = date(2)
            var mega = entry(row("staraptor_mega", cp: 3970), id: "mega"); mega.row.shadow = removedShadow; mega.shadowByPass = byPass
            return [base, mega]
        }
        // A hand Purified on the removed entry; a Shadow pass keeps it and flags it.
        var saved = pair(2, byPass: nil)
        var p = plan([row("staraptor", cp: 2819)], saved, .shadow)
        XCTAssertEqual(p.unsure.first?.kind, .megaPair)
        var out = try BoxMerge.apply(p, resolutions: [0: .existing("base")], to: saved, engine: nil)
        XCTAssertEqual(out.map(\.id), ["base"]); XCTAssertEqual(out[0].row.shadow, 2)
        XCTAssertTrue(out[0].row.flags.contains("pass-conflict:shadow:purified"))
        XCTAssertEqual(BoxMerge.passTally(p, resolutions: [0: .existing("base")], base: saved).conflicts, 1, "the tally sees the join's result too")
        // A Shadow that a pass set on the removed entry; a Purified pass moves it without a conflict.
        saved = pair(1, byPass: true)
        p = plan([row("staraptor", cp: 2819)], saved, .purified)
        out = try BoxMerge.apply(p, resolutions: [0: .existing("base")], to: saved, engine: nil)
        XCTAssertEqual(out[0].row.shadow, 2); XCTAssertFalse(out[0].row.flags.contains { $0.hasPrefix("pass-conflict") })
        XCTAssertEqual(BoxMerge.passTally(p, resolutions: [0: .existing("base")], base: saved).conflicts, 0)
    }

    func testAConflictSurvivesAnOrdinaryUpdateUntilTheMarkMatchesOrThePlayerDecides() throws {
        let saved = [try handShadow(entry(row(), id: "a"), .purified)]
        let flagged = try BoxMerge.apply(plan([row()], saved, .shadow), to: saved, engine: nil)[0]
        let flag = "pass-conflict:shadow:purified"
        XCTAssertTrue(flagged.row.flags.contains(flag))
        XCTAssertTrue(BoxMerge.updated(flagged, with: row(cp: 450), date: date(11)).row.flags.contains(flag), "an ordinary update keeps it")
        var nowShadow = flagged; nowShadow.row.shadow = 1
        XCTAssertFalse(BoxMerge.updated(nowShadow, with: row(cp: 450), date: date(11)).row.flags.contains(flag), "the mark now is what the pass found")
        XCTAssertFalse(BoxMerge.updated(BoxMerge.markChecked(flagged), with: row(cp: 450), date: date(11)).row.flags.contains(flag), "checked")
        let edited = try BoxMerge.correct(flagged, with: BoxMerge.Edit(shadow: .purified), gameMaster: gm)
        XCTAssertFalse(edited.row.flags.contains(flag), "a hand edit of the mark")
        XCTAssertFalse(BoxMerge.updated(edited, with: row(cp: 450), date: date(11)).row.flags.contains(flag))
        // A scanned shadow value never replaces a saved mark, so a pass-set mark stays one; a value a scan fills into a blank mark is not one a pass set.
        var byPass = entry(row(), id: "b"); byPass.shadowByPass = true; byPass.row.shadow = 1
        var scanned = row(cp: 450); scanned.shadow = 2
        let kept = BoxMerge.updated(byPass, with: scanned, date: date(11))
        XCTAssertEqual(kept.row.shadow, 1); XCTAssertEqual(kept.shadowByPass, true)
        var blank = byPass; blank.row.shadow = nil
        let filled = BoxMerge.updated(blank, with: scanned, date: date(11))
        XCTAssertEqual(filled.row.shadow, 2); XCTAssertNil(filled.shadowByPass)
        XCTAssertEqual(BoxMerge.updated(byPass, with: row(cp: 450), date: date(11)).shadowByPass, true, "a scan that carries none keeps it")
    }

    func testTheGuardCountsRowsAnsweredNewAndTheLinesUseTheSameNumber() throws {
        // Eight rows: five unchanged, two power-up questions and one new row. Before any answer 1 of 8 is new; answered "It is new" it is 3 of 8 (37%), over the threshold.
        let species = ["pidgey", "rattata", "weedle", "caterpie", "zubat", "meowth", "geodude"]
        let saved = species.enumerated().map { entry(row($0.element, cp: 100 + $0.offset), id: "s\($0.offset)") }
        var scanned = saved.prefix(5).map(\.row)
        scanned.append(row("meowth", cp: 900)); scanned.append(row("geodude", cp: 901))   // same IVs, higher CP: a power-up question each
        scanned.append(row("kakuna", cp: 77, ivs: IVs(atk: 1, def: 1, hp: 1)))             // new
        let p = plan(scanned, saved, .shadow)
        XCTAssertEqual(p.new.count, 1); XCTAssertEqual(p.unsure.count, 2)
        XCTAssertFalse(BoxMerge.passSearchLooksWrong(p), "1 of 8 before any answer")
        let asNew = Dictionary(uniqueKeysWithValues: p.unsure.map { ($0.scanned, BoxMerge.Resolution.new) })
        let asSame = Dictionary(uniqueKeysWithValues: p.unsure.map { ($0.scanned, BoxMerge.Resolution.existing($0.candidates[0])) })
        XCTAssertEqual(BoxMerge.passUnmatched(p, resolutions: asNew), 3)
        XCTAssertTrue(BoxMerge.passSearchLooksWrong(p, resolutions: asNew), "the answers push it over")
        XCTAssertFalse(BoxMerge.passSearchLooksWrong(p, resolutions: asSame))
        XCTAssertEqual(BoxMerge.passTally(p, resolutions: asNew, base: saved).new, BoxMerge.passUnmatched(p, resolutions: asNew), "Done and Review say the same number")
    }

    func testEveryKeptHandValueHasAReviewLineAndTheFlagReadsNeutrally() throws {
        var moltres = entry(row("moltres", cp: 1966), id: "m")
        moltres = try handShadow(moltres, .purified)
        let saved = [moltres, try handShadow(entry(row("pidgey", cp: 100), id: "x"), .neither)]
        let p = plan([row("moltres", cp: 1966), row("pidgey", cp: 100)], saved, .shadow)
        let lines = BoxMerge.passConflictLines(p, resolutions: [:], base: saved)
        XCTAssertEqual(lines, ["Your box says Purified for Moltres CP 1966; the Shadow search found it.", "Your box says not Shadow or Purified for Pidgey CP 100; the Shadow search found it."])
        XCTAssertTrue(BoxMerge.passConflictLines(plan([row("moltres", cp: 1966)], saved, .dynamax), resolutions: [:], base: saved).isEmpty)
        XCTAssertEqual(FlagInfo.explain("pass-conflict:shadow:purified"), "Your box already said it was Purified; the Shadow search found it. Check it in the game.")
        XCTAssertEqual(FlagInfo.explain("pass-conflict:purified:neither"), "Your box already said it was neither Shadow nor Purified; the Purified search found it. Check it in the game.")
    }

    // MARK: - confirmation fold

    func testAPokemonWithACheckFlagAndAKeptMarkIsOneItemToCheck() throws {
        let saved = [try handShadow(entry(row("moltres", cp: 1966), id: "m"), .purified), try handShadow(entry(row("pidgey", cp: 100), id: "x"), .neither), entry(row("zubat", cp: 50), id: "z")]
        let scanned = [row("moltres", cp: 1966), row("pidgey", cp: 100), row("zubat", cp: 50), row("kakuna", cp: 77)]
        let p = plan(scanned, saved, .shadow)
        // Rows 0 (Moltres, also a kept mark), 2 (Zubat) and 3 (a new Kakuna) carry scan check flags: Moltres counts once; Pidgey's kept mark adds one.
        XCTAssertEqual(BoxMerge.passCheckCount(p, resolutions: [:], base: saved, checkRows: [0, 2, 3]), 4)
        XCTAssertEqual(BoxMerge.passCheckCount(p, resolutions: [:], base: saved, checkRows: []), 2, "kept marks alone")
        XCTAssertEqual(BoxMerge.passCheckCount(plan(scanned, saved, nil), resolutions: [:], base: saved, checkRows: [0, 2, 3]), 3, "an ordinary scan counts its rows")
    }

    func testAMegaJoinCarriesAnUnresolvedConflictFlagToTheBase() throws {
        var base = entry(row("staraptor", cp: 2819), id: "base")
        var mega = entry(row("staraptor_mega", cp: 3970), id: "mega")
        mega.row.shadow = 2; mega.row.flags = ["pass-conflict:shadow:purified"]
        base.lastSeen = date(2)
        let saved = [base, mega]
        let p = plan([row("staraptor", cp: 2819)], saved, nil)
        XCTAssertEqual(p.unsure.first?.kind, .megaPair)
        let out = try BoxMerge.apply(p, resolutions: [0: .existing("base")], to: saved, engine: nil)
        XCTAssertEqual(out[0].row.shadow, 2); XCTAssertTrue(out[0].row.flags.contains("pass-conflict:shadow:purified"))
        // Not when the base's mark already is what that pass found.
        var shadowBase = base; shadowBase.row.shadow = 1
        let other = try BoxMerge.apply(plan([row("staraptor", cp: 2819)], [shadowBase, mega], nil), resolutions: [0: .existing("base")], to: [shadowBase, mega], engine: nil)
        XCTAssertFalse(other[0].row.flags.contains("pass-conflict:shadow:purified"))
    }

    func testAShadowAPassSetSurvivesAnOrdinaryMegaJoinAndAPurifiedPassThenMovesIt() throws {
        var base = entry(row("staraptor", cp: 2819), id: "base"); base.lastSeen = date(2)
        var mega = entry(row("staraptor_mega", cp: 3970), id: "mega"); mega.row.shadow = 1; mega.shadowByPass = true
        let saved = [base, mega]
        let joined = try BoxMerge.apply(plan([row("staraptor", cp: 2819)], saved, nil), resolutions: [0: .existing("base")], to: saved, engine: nil)
        XCTAssertEqual(joined.map(\.id), ["base"]); XCTAssertEqual(joined[0].row.shadow, 1); XCTAssertEqual(joined[0].shadowByPass, true, "the join carries whether a pass set it")
        let purified = try BoxMerge.apply(plan([row("staraptor", cp: 2819)], joined, .purified), to: joined, engine: nil)[0]
        XCTAssertEqual(purified.row.shadow, 2); XCTAssertFalse(purified.row.flags.contains { $0.hasPrefix("pass-conflict") })
    }

    // MARK: - support

    private static var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private static func fixture(_ name: String) -> URL { root.appendingPathComponent("fixtures").appendingPathComponent(name).standardized }

    /// The app's own box export (`BoxExport`) read back into entries: species by dex and form, CP, HP, IVs.
    private func boxFromCSV(_ url: URL) throws -> [BoxEntry] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let head = lines.removeFirst().split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        func col(_ n: String) -> Int? { head.firstIndex(of: n) }
        guard let cDex = col("Pokemon Number"), let cForm = col("Form"), let cCP = col("CP"), let cHP = col("HP"), let cA = col("Atk IV"), let cD = col("Def IV"), let cS = col("Sta IV") else { return [] }
        let bySpecies = Dictionary(grouping: gm.byId.values, by: { $0.dex })
        var out = [BoxEntry]()
        for (i, l) in lines.enumerated() {
            let f = l.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard f.count > cS, let dex = Int(f[cDex]) else { continue }
            let form = f[cForm]
            guard let sp = bySpecies[dex]?.first(where: { s in let nf = GameMaster.nameAndForm(s.name).form; return nf == form || (form.isEmpty && (nf.isEmpty || nf == "Normal")) }) else { continue }
            let nf = GameMaster.nameAndForm(sp.name)
            let iv: IVs? = Int(f[cA]).flatMap { a in Int(f[cD]).flatMap { d in Int(f[cS]).map { IVs(atk: a, def: d, hp: $0) } } }
            let r = ScanRow(index: i + 1, name: nf.name, display: nf.name, form: nf.form, speciesId: sp.id, dex: sp.dex, cp: Int(f[cCP]) ?? 0, hp: Int(f[cHP]), ivs: iv, ivsRead: iv, ivsGuess: nil,
                            level: nil, levelMax: nil, dust: nil, solveStatus: "exact", flags: [], frames: [])
            out.append(BoxEntry(id: "b\(i)", row: r, firstSeen: date(0), lastSeen: date(0)))
        }
        return out
    }
}

private extension ScanRow {
    func withCP(_ cp: Int) -> ScanRow { var r = self; r.cp = cp; return r }

    /// Lucky, Shiny and Background are listed on the Scan screen but cannot be chosen: none is a pass, so none can be stored or saved (eyeball check C1).
    func testComingSoonPassesAreNotPasses() {
        XCTAssertEqual(ScanPass.comingSoon, ["Lucky", "Shiny", "Background"])
        for name in ScanPass.comingSoon { XCTAssertNil(ScanPass(stored: name.lowercased()), name) }
        XCTAssertEqual(ScanPass.allCases.map(\.rawValue), ["shadow", "purified", "dynamax", "gigantamax"])
    }
}
