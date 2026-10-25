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
            XCTAssertTrue(out.row.flags.contains("pass-conflict:\(pass.rawValue)"))
            XCTAssertTrue(out.needsCheck, "a check item")
            XCTAssertEqual(FlagInfo.severity(of: "pass-conflict:\(pass.rawValue)", solveStatus: "exact"), .check)
            XCTAssertEqual(BoxMerge.passTally(p, resolutions: [:], base: saved), BoxMerge.PassTally(marked: 0, new: 0, conflicts: 1, unanswered: 0))
        }
    }

    func testTheMergesCarryOverOfAScannedShadowDoesNotOverrideAHandValue() throws {
        // A saved entry with no IVs is updated when the scan reads them (`ivsNowRead`), and that path copies the scanned row's shadow over the saved one.
        var noIVs = row("rattata", cp: 200, ivs: nil); noIVs.shadow = nil
        let saved = [try handShadow(entry(noIVs, id: "a"), .purified)]
        var scanned = row("rattata", cp: 200, ivs: IVs(atk: 9, def: 9, hp: 9)); scanned.shadow = 1
        let p = plan([scanned], saved, .shadow)
        XCTAssertEqual(p.updated.map(\.savedId), ["a"])
        XCTAssertEqual(BoxMerge.updated(saved[0], with: scanned, date: date(10)).row.shadow, 1, "the generic merge would take the scanned value")
        let out = try BoxMerge.apply(p, to: saved, engine: nil)[0]
        XCTAssertEqual(out.row.shadow, 2, "the hand value stays")
        XCTAssertTrue(out.row.flags.contains("pass-conflict:shadow"))
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
        XCTAssertEqual(kept.row.shadow, 1); XCTAssertTrue(kept.row.flags.contains("pass-conflict:purified"))
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
        // The same rows against an empty box are all new: a wrong search.
        XCTAssertTrue(BoxMerge.passSearchLooksWrong(BoxMerge.plan(scanned: scan.rows, into: [], kind: .partial, scanDate: scan.scanDate, gameMaster: gm, pass: .dynamax)))
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
}
