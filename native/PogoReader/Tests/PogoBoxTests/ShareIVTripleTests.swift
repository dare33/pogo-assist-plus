import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// A saved entry is offered as "the same Pokémon" only when one IV triple could explain both readings, judged conservatively: it may only veto when the mismatch is
/// beyond what a small misread explains (HP within 1, CP exact where the IVs are read and within 1 where they are not, read IVs one notch off, any levels).
final class ShareIVTripleTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private let dev = NSString(string: "~/Developer/personal/pogo-frames/device-runs").expandingTildeInPath
    private func date(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(d) * 86_400) }
    private func row(_ id: String, cp: Int, hp: Int?, ivs: IVs?, flags: [String] = []) -> ScanRow {
        let nf = GameMaster.nameAndForm(gm.byId[id]?.name ?? id)
        return ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: id, dex: gm.byId[id]?.dex, cp: cp, hp: hp, ivs: ivs, ivsRead: ivs, ivsGuess: nil,
                       level: 20, levelMax: 20, dust: 1000, solveStatus: ivs == nil ? "unknown-ivs" : "exact", flags: flags, frames: [])
    }
    private func entry(_ r: ScanRow, _ id: String) -> BoxEntry { BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0)) }
    private func plan(_ s: [ScanRow], _ v: [BoxEntry], _ k: BoxStore.Kind = .full) -> BoxMerge.Plan { BoxMerge.plan(scanned: s, into: v, kind: k, scanDate: date(5), gameMaster: gm) }
    private let max = IVs(atk: 15, def: 15, hp: 15)
    private func at(_ id: String, _ level: Double, _ ivs: IVs) -> (cp: Int, hp: Int) { let b = gm.byId[id]!.baseStats!; return (cpAt(b, ivs, level), hpAt(b, ivs, level)) }

    // MARK: real numbers from the first long scan

    func testAnUnflaggedSavedMeowth65WithHP29FitsNothingSoItIsNotACandidateButTheFlaggedRealEntryIsNotJudged() {
        let scanned = row("meowth", cp: 534, hp: 90, ivs: max)
        XCTAssertTrue(plan([scanned], [entry(row("meowth", cp: 65, hp: 29, ivs: nil), "m")]).unsure.isEmpty, "unflagged and impossible (no IVs give CP 65 with HP 29): nothing fits")
        XCTAssertEqual(plan([scanned], [entry(row("meowth", cp: 65, hp: 29, ivs: nil, flags: ["no-level-fits"]), "m")]).unsure.map { $0.candidates }, [["m"]], "the real entry is flagged no-level-fits: not judged, so asked")
    }

    func testCombeeAndAGenuinePowerUpAreStillAsked() {
        let p = plan([row("combee", cp: 367, hp: 79, ivs: max), row("combee", cp: 296, hp: 71, ivs: max)], [entry(row("combee", cp: 51, hp: 29, ivs: max), "c")])
        XCTAssertEqual(p.unsure.map { $0.candidates }, [["c"], ["c"]])
        XCTAssertEqual(plan([row("combee", cp: 367, hp: 79, ivs: nil)], [entry(row("combee", cp: 51, hp: 29, ivs: max), "c")]).unsure.map { $0.candidates }, [["c"]])
        let ivs = IVs(atk: 10, def: 11, hp: 12), a = at("pikachu", 10, ivs), b = at("pikachu", 20, ivs)
        XCTAssertEqual(plan([row("pikachu", cp: b.cp, hp: b.hp, ivs: ivs)], [entry(row("pikachu", cp: a.cp, hp: a.hp, ivs: nil), "s")]).unsure.map { $0.candidates }, [["s"]])
        XCTAssertEqual(plan([row("pikachu", cp: b.cp, hp: b.hp, ivs: nil)], [entry(row("pikachu", cp: a.cp, hp: a.hp, ivs: ivs), "s")]).unsure.map { $0.candidates }, [["s"]])
    }

    func testAZubatThatCannotBeTheSavedOneAndAPsyduckThatCannotAreNotCandidates() {
        // saved Zubat CP 61 / HP 29 fits no IVs at all, unflagged: not a candidate for any Zubat
        XCTAssertTrue(plan([row("zubat", cp: 362, hp: 80, ivs: IVs(atk: 13, def: 10, hp: 15))], [entry(row("zubat", cp: 61, hp: 29, ivs: nil), "z")]).unsure.isEmpty)
        // the real saved Zubat has no HP read: it fits, so it IS asked (the phone asked these too)
        XCTAssertEqual(plan([row("zubat", cp: 218, hp: 59, ivs: IVs(atk: 8, def: 14, hp: 3))], [entry(row("zubat", cp: 61, hp: nil, ivs: nil), "z")]).unsure.map { $0.candidates }, [["z"]], "a Zubat of the scan that the rule keeps asking")
        // Psyduck 40 / HP 24 with 2/0/11 against a Psyduck of CP 166 / HP 48 with 15/15/15: those IVs cannot give both
        let up = plan([row("psyduck", cp: 166, hp: 48, ivs: max)], [entry(row("psyduck", cp: 40, hp: 24, ivs: IVs(atk: 2, def: 0, hp: 11)), "p")])
        XCTAssertTrue(up.unsure.isEmpty && up.updated.isEmpty)
    }

    // MARK: the reviewer's misread attacks: every real power-up must still be ASKED

    func testAMisreadThatStillFitsSomeOtherTripleNeverTurnsARealPowerUpIntoNew() {
        let ivs = IVs(atk: 10, def: 11, hp: 12)
        for id in ["pikachu", "machamp", "combee", "zubat", "meowth", "psyduck"] {
            let lo = at(id, 12, ivs), hi = at(id, 22, ivs)
            func asked(_ saved: ScanRow, _ scanned: ScanRow) -> Bool { plan([scanned], [entry(saved, "s")]).unsure.map { $0.candidates } == [["s"]] }
            for dh in [-1, 1] {
                XCTAssertTrue(asked(row(id, cp: lo.cp, hp: lo.hp + dh, ivs: nil), row(id, cp: hi.cp, hp: hi.hp, ivs: ivs)), "\(id): saved IVs unread, HP off by \(dh)")
                XCTAssertTrue(asked(row(id, cp: lo.cp, hp: lo.hp, ivs: ivs), row(id, cp: hi.cp, hp: hi.hp + dh, ivs: nil)), "\(id): scanned bars unread, HP off by \(dh)")
            }
            XCTAssertTrue(asked(row(id, cp: lo.cp + 1, hp: lo.hp, ivs: nil), row(id, cp: hi.cp, hp: hi.hp, ivs: ivs)), "\(id): saved IVs unread, CP last digit off by 1")
            XCTAssertTrue(asked(row(id, cp: lo.cp, hp: lo.hp, ivs: ivs), row(id, cp: hi.cp - 1, hp: hi.hp, ivs: nil)), "\(id): scanned bars unread, CP off by 1")
            // bars one notch off on the saved side (still solving), the later scan has its bars unread
            let off = IVs(atk: ivs.atk + 1, def: ivs.def, hp: ivs.hp)
            XCTAssertTrue(asked(row(id, cp: lo.cp, hp: lo.hp, ivs: off), row(id, cp: hi.cp, hp: hi.hp, ivs: nil)), "\(id): saved bars one notch off")
        }
    }

    func testTrapinchAndItsEvolutionsAreAskedWhateverTheLevelsAreAndANonRelativeIsNot() {
        let ivs = IVs(atk: 12, def: 13, hp: 14)
        let trapinch = at("trapinch", 20, ivs), vibrava = at("vibrava", 20.5, ivs)
        XCTAssertGreaterThan(trapinch.cp, vibrava.cp, "the CP goes DOWN with this evolution")
        XCTAssertEqual(plan([row("vibrava", cp: vibrava.cp, hp: vibrava.hp, ivs: nil)], [entry(row("trapinch", cp: trapinch.cp, hp: trapinch.hp, ivs: ivs), "t")]).unsure.map { $0.candidates }, [["t"]])
        let machop = at("machop", 15, ivs)
        XCTAssertTrue(plan([row("machoke", cp: at("machoke", 40, IVs(atk: 0, def: 0, hp: 0)).cp, hp: at("machoke", 40, IVs(atk: 0, def: 0, hp: 0)).hp, ivs: nil)],
                           [entry(row("machop", cp: machop.cp, hp: machop.hp, ivs: IVs(atk: 15, def: 15, hp: 15)), "m")]).unsure.isEmpty, "a 15/15/15 Machop cannot be a Machoke that needs about 0/0/0")
    }

    func testEachSideIsJudgedOnItsOwn() {
        // a flagged saved entry is not judged, but the unflagged scanned row on the other side must still fit by itself
        let flagged = entry(row("meowth", cp: 65, hp: 29, ivs: nil, flags: ["no-level-fits"]), "m")
        XCTAssertTrue(plan([row("meowth", cp: 534, hp: 12, ivs: nil)], [flagged]).unsure.isEmpty, "534 with HP 12 fits no Meowth: nothing fits on the unflagged side")
        XCTAssertEqual(plan([row("meowth", cp: 534, hp: 90, ivs: nil)], [flagged]).unsure.map { $0.candidates }, [["m"]])
    }

    // MARK: the phone's box, as it was before run12 (needs the logs on this machine)

    private func file(_ dir: String, _ suffix: String) -> URL? {
        let p = dev + "/" + dir
        guard let f = (try? FileManager.default.contentsOfDirectory(atPath: p))?.filter({ $0.hasSuffix(suffix) && !$0.contains(" 2") }).sorted().first else { return nil }
        return URL(fileURLWithPath: p + "/" + f)
    }
    private func result(_ dir: String) -> ScanResult? { file(dir, ".result.json").flatMap { try? JSONDecoder().decode(ScanResult.self, from: Data(contentsOf: $0)) } }
    private func iv(_ i: IVs?) -> String { i.map { "\($0.atk)/\($0.def)/\($0.hp)" } ?? "-" }

    /// The box CSV the phone wrote after run12, as entries, with the scan results' flags joined on where the values match (the CSV has none).
    private func csvBox(upTo limit: Int = Int.max) throws -> [BoxEntry] {
        let url = try XCTUnwrap(file("run12-tap-1500", ".csv"), "run12 is not on this machine")
        let lines = try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline).map(String.init)
        let head = lines[0].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        func col(_ n: String) -> Int { head.firstIndex(of: n)! }
        var byNF = [String: String]()
        for (id, sp) in gm.byId.sorted(by: { $0.key < $1.key }) { let nf = GameMaster.nameAndForm(sp.name); let k = "\(nf.name)|\(nf.form)"; if byNF[k] == nil || id.count < byNF[k]!.count { byNF[k] = id } }
        var join = [String: ScanRow]()
        for dir in ["run12-tap-1500", "run13-tap-200-tail", "run9-tap-300b", "run8-tap-300"] { for r in result(dir)?.rows ?? [] { let k = "\(r.name)|\(r.cp)|\(r.hp.map(String.init) ?? "")|\(iv(r.ivs))"; if join[k] == nil { join[k] = r } } }
        var out = [BoxEntry]()
        for (i, l) in lines.dropFirst().enumerated() where i < limit {
            let f = l.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            let name = f[col("Name")], form = f[col("Form")], cp = Int(f[col("CP")]) ?? 0, hp = Int(f[col("HP")])
            let ivs: IVs? = Int(f[col("Atk IV")]).flatMap { a in Int(f[col("Def IV")]).flatMap { d in Int(f[col("Sta IV")]).map { IVs(atk: a, def: d, hp: $0) } } }
            let k = "\(name)|\(cp)|\(hp.map(String.init) ?? "")|\(iv(ivs))"
            var r: ScanRow
            if let j = join[k] { r = j } else {
                let id = byNF["\(name)|\(form)"] ?? byNF["\(name)|"] ?? name.lowercased()
                let lv = Double(f[col("Level Min")]), lvx = Double(f[col("Level Max")])
                r = ScanRow(index: i + 1, name: name, display: name, form: form, speciesId: id, dex: Int(f[col("Pokemon Number")]), cp: cp, hp: hp, ivs: ivs, ivsRead: ivs, ivsGuess: nil, level: lv, levelMax: lvx, dust: nil,
                            solveStatus: ivs != nil ? "exact" : (lv == nil ? "none" : "unknown-ivs"), flags: lv == nil && cp > 0 ? ["no-level-fits"] : (ivs == nil ? ["ivs-unread"] : []), frames: [])
            }
            out.append(BoxEntry(id: "csv\(i + 1)", row: r, firstSeen: date(0), lastSeen: date(0)))
        }
        return out
    }

    private func counts(_ p: BoxMerge.Plan) -> String { "same \(p.same.count) updated \(p.updated.count) unsure \(p.unsure.count) new \(p.new.count) gone \(p.gone.count)" }

    /// run12 into the box as it was before it: CSV rows 1-618 with the Zubat entry set back to CP 61, HP and IVs unread. With the rule off this asks the 29 questions the phone asked.
    func testRun12IntoTheBoxBeforeItAsksTwentyNineWithTheRuleOffAndFewerWithItOn() throws {
        var pre = try csvBox(upTo: 618)
        let i = try XCTUnwrap(pre.firstIndex { $0.id == "csv422" })
        var z = pre[i].row; z.cp = 61; z.hp = nil; z.ivs = nil; z.ivsRead = nil; z.level = nil; z.levelMax = nil; z.solveStatus = "unknown-ivs"; z.flags = ["ivs-unread", "hp-unread"]
        pre[i] = entry(z, "csv422")
        let rows = try XCTUnwrap(result("run12-tap-1500")).rows
        let off = BoxMerge.plan(scanned: rows, into: pre, kind: .partial, scanDate: date(5), gameMaster: gm, shareIVs: false)
        let on = BoxMerge.plan(scanned: rows, into: pre, kind: .partial, scanDate: date(5), gameMaster: gm)
        let byId = Dictionary(uniqueKeysWithValues: pre.map { ($0.id, $0) })
        print("PRE12 rule off: \(counts(off)); rule on: \(counts(on))")
        for u in on.unsure { print("PRE12 remains \(u.kind) \(rows[u.scanned].name) CP \(rows[u.scanned].cp) HP \(rows[u.scanned].hp.map(String.init) ?? "-") IVs \(iv(rows[u.scanned].ivs)) vs \(u.candidates.map { "CP \(byId[$0]!.row.cp) HP \(byId[$0]!.row.hp.map(String.init) ?? "-") IVs \(iv(byId[$0]!.row.ivs))" })") }
        XCTAssertEqual(off.unsure.count, 29, "the phone asked 29")
        // Round 16 (R2) asks a power-up whose bars were read one notch off on a stat (both IV triples read, different, within a notch, one triple explains both). Without those
        // the shared-triple rule asks fewer than the phone did; with them it asks 14 more on this box, which lacks the 1,037 Pokémon the scan adds (most of those rows are new).
        func notch(_ u: BoxMerge.Unsure) -> Bool { u.candidates.contains { id in
            guard let a = rows[u.scanned].ivs, let b = byId[id]?.row.ivs else { return false }
            return a != b && IVFit.near(IVFit.index(a), b) && !(rows[u.scanned].cp == byId[id]!.row.cp && rows[u.scanned].hp == byId[id]!.row.hp) } }
        let oneNotch = on.unsure.filter(notch).count
        XCTAssertEqual(oneNotch, 14, "questions added by R2")
        XCTAssertLessThan(on.unsure.count - oneNotch, off.unsure.count)
        // every question that is kept still has its candidate; the ones the owner answered "new" for impossible pairs are what goes
        XCTAssertTrue(on.unsure.allSatisfy { !$0.candidates.isEmpty })
    }

    /// The later scans merged into the phone's box: unchanged by the rule apart from the known new and unsure ones.
    func testLaterScansIntoThePhonesBoxAreNotChangedByTheRule() throws {
        let box = try csvBox()
        for dir in ["run13-tap-200-tail", "stall-scan-20261003T054229Z-b1f94047", "stall-scan-20261003T055448Z-6b2b1f4e", "stall-scan-20261003T065119Z-2fd03e3a-horsea", "run14-tail-from-horsea-scan-20261003T070213Z-08997070"] {
            guard let rows = result(dir)?.rows else { print("LATER missing \(dir)"); continue }
            let off = BoxMerge.plan(scanned: rows, into: box, kind: .partial, scanDate: date(5), gameMaster: gm, shareIVs: false)
            let on = BoxMerge.plan(scanned: rows, into: box, kind: .partial, scanDate: date(5), gameMaster: gm)
            print("LATER \(dir) (\(rows.count) rows) rule off: \(counts(off)) | on: \(counts(on))")
            XCTAssertEqual(on.same.count, off.same.count, dir); XCTAssertLessThanOrEqual(on.unsure.count, off.unsure.count, dir)
            XCTAssertEqual(on.new.count + on.unsure.count, off.new.count + off.unsure.count, "only questions may turn into new rows or stay questions: \(dir)")
        }
    }

    func testRun9IntoTheRun8BoxStillHasTheSameCountsAndNoMoreQuestions() throws {
        let hint = PagingHint(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds)
        let r8 = try ScanPipeline.process(replay: Fixture.url("device-run8-tap-300.replay.jsonl"), engine: sharedEngine, paging: hint)
        let r9 = try ScanPipeline.process(replay: Fixture.url("device-run9-tap-300b.replay.jsonl"), engine: sharedEngine, paging: hint)
        let box = r8.scan.rows.enumerated().map { BoxEntry(id: "e\($0.offset)", row: $0.element, firstSeen: date(0), lastSeen: date(0)) }
        let before = BoxMerge.plan(scanned: r9.scan.rows, into: box, kind: .full, scanDate: date(5), gameMaster: gm, shareIVs: false)
        let after = BoxMerge.plan(scanned: r9.scan.rows, into: box, kind: .full, scanDate: date(5), gameMaster: gm)
        print("RUN9INTO8 before: \(counts(before)); after: \(counts(after))")
        XCTAssertGreaterThanOrEqual(after.same.count, before.same.count)
        XCTAssertLessThanOrEqual(after.unsure.count, before.unsure.count)
    }
}
