import Foundation
import XCTest
@testable import PogoBox
@testable import PogoReader

/// Round 21: the findings of the two reviews of round 15-20 work, as tests that fail on e5fd57c.
final class RoundTwentyOneTests: XCTestCase {
    let gm = try! GameMaster.bundled()
    func date(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(d) * 86_400) }
    func row(_ id: String, cp: Int, hp: Int?, ivs: IVs?, flags: [String] = [], status: String = "exact") -> ScanRow {
        let nf = GameMaster.nameAndForm(gm.byId[id]?.name ?? id)
        return ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: id, dex: gm.byId[id]?.dex, cp: cp, hp: hp, ivs: ivs, ivsRead: ivs, ivsGuess: nil, level: ivs == nil ? nil : 20, levelMax: ivs == nil ? nil : 20,
                       dust: 1000, solveStatus: ivs == nil ? "unknown-ivs" : status, flags: flags, frames: [])
    }
    func entry(_ r: ScanRow, _ id: String, corrections: Corrections = Corrections()) -> BoxEntry { BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0), corrections: corrections) }
    func plan(_ s: [ScanRow], _ v: [BoxEntry], _ k: BoxStore.Kind = .full) -> BoxMerge.Plan { BoxMerge.plan(scanned: s, into: v, kind: k, scanDate: date(5), gameMaster: gm) }
    let sIV = IVs(atk: 15, def: 15, hp: 14)
    func staraptorBox() -> [BoxEntry] { [entry(row("staraptor", cp: 2819, hp: 167, ivs: sIV), "base"), entry(row("staraptor_mega", cp: 3970, hp: 167, ivs: sIV), "mega")] }

    /// A scanned row is in exactly one of same / updated / unsure / new.
    func assertOneHome(_ p: BoxMerge.Plan, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        var homes = [Int: [String]]()
        for x in p.same { homes[x.scanned, default: []].append("same") }
        for x in p.updated { homes[x.scanned, default: []].append("updated") }
        for x in p.unsure { homes[x.scanned, default: []].append("unsure:\(x.kind)") }
        for x in p.new { homes[x, default: []].append("new") }
        for i in p.scanned.indices { XCTAssertEqual(homes[i]?.count, 1, "\(label): row \(i) is in \(homes[i] ?? [])", file: file, line: line) }
    }

    // MARK: S1

    /// A base row at another CP (or with HP unread) is not the base entry: it never raises the Mega-pair question, and a join never changes the base entry's saved values or corrections.
    func testS1ARowAtAnotherCPIsNeverAMegaPairQuestion() throws {
        let box = staraptorBox()
        for s in [row("staraptor", cp: 2950, hp: 167, ivs: sIV), row("staraptor", cp: 1234, hp: nil, ivs: sIV)] {
            let p = plan([s], box)
            XCTAssertFalse(p.unsure.contains { $0.kind == .megaPair }, "CP \(s.cp)")
            assertOneHome(p, "CP \(s.cp)")
        }
        // the ordinary rules decide a higher CP: a question of their own kind (here the base-of-Mega rule), never the Mega-pair join
        let up = plan([row("staraptor", cp: 2950, hp: 167, ivs: sIV)], box)
        XCTAssertEqual(up.unsure.map { $0.kind }, [.megaToBase])
    }

    func testS1JoinKeepsTheBaseEntryExactlyAsSavedAndDropsTheMegaEntryWithItsCorrections() throws {
        var box = staraptorBox()
        box[0].corrections = Corrections(ivs: Fix(was: IVs(atk: 14, def: 15, hp: 14)))
        box[1].corrections = Corrections(ivs: Fix(was: IVs(atk: 13, def: 15, hp: 14)), species: Fix(was: "something"))
        let p = plan([row("staraptor", cp: 2819, hp: 167, ivs: sIV)], box)
        XCTAssertEqual(p.unsure.map { $0.kind }, [.megaPair], "the row that IS the base entry still raises the question")
        let res: [Int: BoxMerge.Resolution] = [0: .existing("base")]
        let out = try BoxMerge.apply(p, resolutions: res, keepGone: BoxMerge.keepSet(plan: p, resolutions: res, markedForRemoval: []), to: box)
        XCTAssertEqual(out.map { $0.id }, ["base"])
        XCTAssertEqual(out[0].row, box[0].row, "values unchanged"); XCTAssertEqual(out[0].corrections, box[0].corrections, "corrections unchanged: the Mega entry's are not copied in")
    }

    // MARK: S2

    /// Two identical base rows beside a base and a Mega entry are two Pokémon: no Mega-pair question, and the second row is asked about (an extra twin), never silently New.
    func testS2TwoIdenticalBaseRowsAreNotOneMegaPairQuestionWithASilentNew() throws {
        let box = staraptorBox()
        let twin = row("staraptor", cp: 2819, hp: 167, ivs: sIV)
        let p = plan([twin, twin], box)
        XCTAssertFalse(p.unsure.contains { $0.kind == .megaPair })
        XCTAssertTrue(p.new.isEmpty, "the second row is not silently added: \(p.new)")
        XCTAssertTrue(p.unsure.contains { $0.kind == .extraTwin }, "\(p.unsure.map { $0.kind })")
        assertOneHome(p, "twins")
    }

    // MARK: S3

    /// A third saved Staraptor with the same IVs used to take the Mega-pair row into the same-IV group as well: one row, two questions.
    func testS3AScannedRowCarriesAtMostOneQuestion() throws {
        let box = staraptorBox() + [entry(row("staraptor", cp: 2000, hp: 140, ivs: sIV), "third")]
        let a = plan([row("staraptor", cp: 2819, hp: 167, ivs: sIV), row("staraptor", cp: 2100, hp: 143, ivs: sIV)], box)
        assertOneHome(a, "P3")
        let b = plan([row("staraptor", cp: 2819, hp: 167, ivs: sIV), row("staraptor", cp: 2100, hp: 143, ivs: sIV), row("staraptor", cp: 2200, hp: 150, ivs: sIV)], box)
        assertOneHome(b, "P5")
        for p in [a, b] {
            // every combination of answers applies without throwing: all new, all left out, and each question alone answered "this one" with its first candidate
            var variants: [[Int: BoxMerge.Resolution]] = [Dictionary(p.unsure.map { ($0.scanned, BoxMerge.Resolution.new) }, uniquingKeysWith: { a, _ in a }), Dictionary(p.unsure.map { ($0.scanned, BoxMerge.Resolution.leaveOut) }, uniquingKeysWith: { a, _ in a })]
            for u in p.unsure { var v = Dictionary(p.unsure.map { ($0.scanned, BoxMerge.Resolution.new) }, uniquingKeysWith: { a, _ in a }); v[u.scanned] = .existing(u.candidates[0]); variants.append(v) }
            for res in variants { XCTAssertNoThrow(try BoxMerge.apply(p, resolutions: res, keepGone: BoxMerge.keepSet(plan: p, resolutions: res, markedForRemoval: []), to: box), "\(res)") }
        }
    }

    // MARK: S4

    /// A part read whose bars were read and clearly disagree with the saved IVs is asked about, not matched; with no contradicting bars the owner's rule stands.
    func testS4PartReadWithContradictingBarsIsAsked() {
        let saved = entry(row("moltres", cp: 1901, hp: 129, ivs: IVs(atk: 10, def: 11, hp: 10)), "m")
        func part(_ read: IVs?) -> ScanRow { var r = row("moltres", cp: 191, hp: 129, ivs: nil, flags: ["no-level-fits"]); r.ivsRead = read; r.solveStatus = "unknown-ivs"; return r }
        let contradicting = plan([part(IVs(atk: 2, def: 3, hp: 4))], [saved])
        XCTAssertTrue(contradicting.partMatches.isEmpty); XCTAssertTrue(contradicting.same.isEmpty); XCTAssertEqual(contradicting.unsure.map { $0.kind }, [.partialRead])
        let none = plan([part(nil)], [saved])
        XCTAssertEqual(none.partMatches.count, 1, "no bars read: matched by its HP as before")
        let near = plan([part(IVs(atk: 10, def: 12, hp: 10))], [saved])
        XCTAssertEqual(near.partMatches.count, 1, "bars one notch off are the misread rule's: still matched")
    }

    /// The run12 and run15 merges: every row has one home.
    func testS3TheRealMergesKeepOneHomePerRow() throws {
        let dev = "/Users/greg-mb/Developer/personal/pogo-frames/device-runs"
        func file(_ dir: String, _ suffix: String) -> URL? {
            (try? FileManager.default.contentsOfDirectory(atPath: dev + "/" + dir))?.filter { $0.hasSuffix(suffix) && !$0.contains(" 2") }.sorted().first.map { URL(fileURLWithPath: dev + "/" + dir + "/" + $0) }
        }
        let hint = PagingHint(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds)
        guard let r12 = file("run12-tap-1500", ".replay.jsonl"), let r15 = file("run15-full-2000-scan-20261003T101008Z-84391adc", ".replay.jsonl"), let csv = file("run12-tap-1500", ".csv") else { throw XCTSkip("device runs not on this machine") }
        let rows12 = try ScanPipeline.process(replay: r12, engine: sharedEngine, paging: hint).scan.rows
        let rows15 = try ScanPipeline.process(replay: r15, engine: sharedEngine, paging: hint).scan.rows
        // run12 against an empty box, and against itself
        assertOneHome(plan(rows12, []), "run12 into empty")
        let own = rows12.enumerated().map { BoxEntry(id: "e\($0.offset)", row: $0.element, firstSeen: date(0), lastSeen: date(0)) }
        assertOneHome(plan(rows12, own), "run12 into itself")
        // run15 against the box rebuilt from run12's csv (the rows run8..run15 joined supply the values the csv lacks)
        let box = try Self.csvBox(csv, gm: gm, date: date(0), supply: [rows12, rows15])
        let p = plan(rows15, box)
        assertOneHome(p, "run15 into run12 csv box")
        print("R15 MERGE box \(box.count): same \(p.same.count) updated \(p.updated.count) unsure \(p.unsure.count) new \(p.new.count) gone \(p.gone.count) \(p.unsure.map { "\($0.kind)" })")
    }

    static func csvBox(_ url: URL, gm: GameMaster, date: Date, supply: [[ScanRow]]) throws -> [BoxEntry] {
        let lines = try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline).map(String.init)
        let head = lines[0].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        func col(_ n: String) -> Int { head.firstIndex(of: n)! }
        func iv(_ i: IVs?) -> String { i.map { "\($0.atk)/\($0.def)/\($0.hp)" } ?? "-" }
        var byNF = [String: String]()
        for (id, sp) in gm.byId.sorted(by: { $0.key < $1.key }) { let nf = GameMaster.nameAndForm(sp.name); let k = "\(nf.name)|\(nf.form)"; if byNF[k] == nil || id.count < byNF[k]!.count { byNF[k] = id } }
        var join = [String: ScanRow]()
        for rows in supply { for r in rows { let k = "\(r.name)|\(r.cp)|\(r.hp.map(String.init) ?? "")|\(iv(r.ivs))"; if join[k] == nil { join[k] = r } } }
        var out = [BoxEntry]()
        for (i, l) in lines.dropFirst().enumerated() {
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
            out.append(BoxEntry(id: "csv\(i + 1)", row: r, firstSeen: date, lastSeen: date))
        }
        return out
    }

    // MARK: M1

    /// Two first rows with different settled IVs stay two; the real case (first row's bars unread, unsettled) still joins.
    func testM1OpeningCardJoinNeedsUnsettledBarsNotJustAnInexactStatus() {
        func fr(_ t: Double) -> FrameLabel { FrameLabel(frame: "f\(t)", time: t) }
        func rows(firstIVs: IVs?) -> ScanResult {
            var a = row("fidough", cp: 768, hp: 89, ivs: firstIVs, status: "ambiguous"); a.frames = stride(from: 0.0, through: 6.0, by: 0.4).map(fr)
            if firstIVs == nil { a.ivsRead = IVs(atk: 9, def: 9, hp: 9); a.solveStatus = "ambiguous" }
            var b = row("fidough", cp: 768, hp: 89, ivs: IVs(atk: 15, def: 11, hp: 12)); b.frames = stride(from: 6.4, through: 7.6, by: 0.4).map(fr); b.index = 2
            var c = row("pidgey", cp: 100, hp: 30, ivs: IVs(atk: 1, def: 1, hp: 1)); c.frames = [fr(7.9), fr(8.3)]; c.index = 3
            return ScanResult(rows: [a, b, c], review: [], unmatched: [])
        }
        let two = Refine.joinOpeningCard(rows(firstIVs: IVs(atk: 15, def: 4, hp: 10)), period: 1.2, ticks: [])
        XCTAssertEqual(two.scan.rows.count, 3, "settled 15/4/10 then 15/11/12: two Pokémon"); XCTAssertTrue(two.marks.isEmpty)
        let near = Refine.joinOpeningCard(rows(firstIVs: IVs(atk: 15, def: 11, hp: 11)), period: 1.2, ticks: [])
        XCTAssertEqual(near.scan.rows.count, 2, "bars one notch off the second's: the same card")
        let unread = Refine.joinOpeningCard(rows(firstIVs: nil), period: 1.2, ticks: [])
        XCTAssertEqual(unread.scan.rows.count, 2, "unread, unsettled bars (the run15 Rayquaza): joined")
    }

    // MARK: P1

    func testP1AScanThatTimedOutIsNeverJudgedFull() {
        let full = ScanKindAdvice.decide(endedAtListEnd: true, pokemonRead: 298, typedCount: 300, logTruncated: false, logFailed: false, commandPeriod: 1.2)
        XCTAssertTrue(full.fullIsSound, "the same numbers at the end of the list are Full")
        let timed = ScanKindAdvice.decide(endedAtListEnd: true, pokemonRead: 298, typedCount: 300, logTruncated: false, logFailed: false, commandPeriod: 1.2, endedByTimeout: true)
        XCTAssertFalse(timed.fullIsSound); XCTAssertTrue((timed.reason ?? "").contains("not resumed"), timed.reason ?? "")
        XCTAssertNil(ScanKindAdvice.matchSentence(pokemonRead: 298, decision: timed))
        let line = ScanStop.summary(lastName: "A", lastCP: 1, read: 298, appraisalClosed: nil, ranOut: false, commandKnown: true, paused: ["A (CP 1), not resumed: the scan finished at the timeout"], byTimeout: true)
        XCTAssertTrue(line.hasPrefix("The scan paused and was not resumed, so it finished after 3 minutes"), line)
        XCTAssertFalse(line.contains("ended by itself")); XCTAssertFalse(line.contains("You finished")); XCTAssertTrue(line.contains("not resumed: the scan finished at the timeout"))
    }

    func testP1TheTimeoutMarkerRoundTrips() {
        XCTAssertEqual(ReplayLog.decode(ReplayLog.encode(.pauseTimedOut(at: 12.5))), .pauseTimedOut(at: 12.5))
        let rs: [ReplayLine] = (0..<50).map { i in var f = FrameReading(); f.name = "A"; f.cp = 100; f.hp = HP(current: 10, max: 10); return .reading(ReplayReading(f, time: Double(i), ms: 1)) }
        XCTAssertTrue(ReplayLog.trimmed(rs + [.pauseTimedOut(at: 49), .end(at: 8, last: 0)]).contains { if case .pauseTimedOut = $0 { return true } else { return false } })
    }
}

extension RoundTwentyOneTests {
    /// A Full scan needs a valid count; without one the extension runs it as Add and update (no pause), and a count-less Full scan is never judged Full.
    func testAFullScanRequiresACountAndTheBackstopNeverPauses() throws {
        XCTAssertTrue(ScanEndDecision.fullScanNeedsCount(isFull: true, storageCount: nil)); XCTAssertTrue(ScanEndDecision.fullScanNeedsCount(isFull: true, storageCount: 0))
        XCTAssertFalse(ScanEndDecision.fullScanNeedsCount(isFull: true, storageCount: 1698)); XCTAssertFalse(ScanEndDecision.fullScanNeedsCount(isFull: false, storageCount: nil), "Add and update needs none")
        XCTAssertFalse(ScanEndDecision.pausesAllowed(isFull: true, storageCount: nil)); XCTAssertFalse(ScanEndDecision.pausesAllowed(isFull: false, storageCount: 1698))
        XCTAssertTrue(ScanEndDecision.pausesAllowed(isFull: true, storageCount: 1698))
        // the controller built the way the extension builds it, on a stalled log with no count: finishes at the end wait, never pauses
        let rs = ReplayLog.lines(in: try Fixture.url("device-run10-tap-25-autoend.replay.jsonl")).compactMap { l -> ReplayReading? in if case .reading(let r) = l { return r } else { return nil } }.sorted { $0.t < $1.t }
        var c = ScanEndController(period: 1.2, storageCount: nil, pausesAllowed: ScanEndDecision.pausesAllowed(isFull: true, storageCount: nil))!
        var events = [ScanEndController.Event](), g = LiveGrouper(species: try? SpeciesTable.bundled())
        for r in rs { g.add(r.frameReading); let e = c.feed(r.frameReading, time: r.t, read: g.rows.count); if e != .none { events.append(e); break } }
        guard case .finish? = events.first else { return XCTFail("\(events)") }
        // and "no count -> never Full" stays
        XCTAssertFalse(ScanKindAdvice.decide(endedAtListEnd: true, pokemonRead: 11, typedCount: nil, logTruncated: false, logFailed: false, commandPeriod: 1.2).fullIsSound)
    }
}
