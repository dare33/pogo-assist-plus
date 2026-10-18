import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// A Mega pair is one box entry with an optional Mega form (`BoxEntry.megaForm`).
final class MegaFormTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private func date(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(d) * 86_400) }
    private let ivs = IVs(atk: 15, def: 15, hp: 14)
    private func row(_ id: String, cp: Int, hp: Int? = 167, ivs: IVs? = IVs(atk: 15, def: 15, hp: 14), flags: [String] = []) -> ScanRow {
        let nf = GameMaster.nameAndForm(gm.byId[id]?.name ?? id)
        return ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: id, dex: gm.byId[id]?.dex, cp: cp, hp: hp, ivs: ivs, ivsRead: ivs, ivsGuess: nil,
                       level: 50, levelMax: 50, dust: 0, solveStatus: "exact", flags: flags, frames: [])
    }
    private func entry(_ r: ScanRow, _ id: String) -> BoxEntry { BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0)) }
    private func plan(_ s: [ScanRow], _ v: [BoxEntry], _ k: BoxStore.Kind = .partial, day: Int = 5) -> BoxMerge.Plan { BoxMerge.plan(scanned: s, into: v, kind: k, scanDate: date(day), gameMaster: gm) }

    func testAMegaRowWithOneMatchingBaseEntryIsPairedAndItsValuesAreStoredAsTheMegaForm() throws {
        let saved = entry(row("staraptor", cp: 2819), "a")
        let p = plan([row("staraptor_mega", cp: 3970, hp: 190)], [saved], .full)
        XCTAssertEqual(p.same, [BoxMerge.Pair(scanned: 0, savedId: "a", mega: true)])
        XCTAssertTrue(p.new.isEmpty && p.gone.isEmpty && p.unsure.isEmpty)
        XCTAssertTrue(BoxMerge.goneReport(p, resolutions: [:]).gone.isEmpty)
        let out = try BoxMerge.apply(p, to: [saved])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].row, saved.row, "the base values are untouched")
        let mf = try XCTUnwrap(out[0].megaForm)
        XCTAssertEqual(mf.speciesId, "staraptor_mega"); XCTAssertEqual(mf.cp, 3970); XCTAssertEqual(mf.hp, 190); XCTAssertEqual(mf.level, 50)
        XCTAssertEqual(mf.firstSeen, date(5)); XCTAssertEqual(mf.lastSeen, date(5)); XCTAssertEqual(out[0].megaWhenScanned, true)
    }

    func testTheBaseScannedLaterKeepsTheMegaFormAndALaterMegaScanUpdatesIt() throws {
        let saved = entry(row("staraptor", cp: 2819), "a")
        let withMega = try BoxMerge.apply(plan([row("staraptor_mega", cp: 3970, hp: 190)], [saved]), to: [saved])
        // the base form again, as a power-up the person confirms: base values update, the Mega form stays
        let up = plan([row("staraptor", cp: 2900, hp: 170)], withMega, day: 6)
        XCTAssertEqual(up.unsure.first?.kind, .poweredUp)
        let after = try BoxMerge.apply(up, resolutions: [0: .existing("a")], to: withMega)
        XCTAssertEqual(after[0].row.cp, 2900); XCTAssertNil(after[0].megaWhenScanned)
        XCTAssertEqual(after[0].megaForm, withMega[0].megaForm)
        // an unchanged base scan leaves it too
        let same = try BoxMerge.apply(plan([row("staraptor", cp: 2819)], withMega, day: 7), to: withMega)
        XCTAssertEqual(same[0].megaForm, withMega[0].megaForm)
        // a later Mega scan replaces the Mega values it read and keeps the first-seen date
        let again = try BoxMerge.apply(plan([row("staraptor_mega", cp: 4000, hp: 191)], withMega, day: 8), to: withMega)
        XCTAssertEqual(again[0].megaForm?.cp, 4000); XCTAssertEqual(again[0].megaForm?.hp, 191)
        XCTAssertEqual(again[0].megaForm?.firstSeen, date(5)); XCTAssertEqual(again[0].megaForm?.lastSeen, date(8)); XCTAssertEqual(again[0].row.cp, 2819)
    }

    func testAMegaRowWhoseCPFitsNoLevelStoresNoMegaForm() throws {
        let saved = entry(row("staraptor", cp: 2819), "a")
        let p = plan([row("staraptor_mega", cp: 3970, hp: 190, flags: ["no-level-fits"])], [saved])
        let out = try BoxMerge.apply(p, resolutions: Dictionary(uniqueKeysWithValues: p.unsure.map { ($0.scanned, BoxMerge.Resolution.existing("a")) }), to: [saved])
        XCTAssertNil(out[0].megaForm)
    }

    func testTwoMatchingBaseEntriesStayAQuestionAndTheChosenOneGetsTheMegaForm() throws {
        let a = entry(row("staraptor", cp: 2819), "a"), b = entry(row("staraptor", cp: 2500, hp: 160), "b")
        let p = plan([row("staraptor_mega", cp: 3970)], [a, b])
        XCTAssertEqual(p.unsure, [BoxMerge.Unsure(scanned: 0, candidates: ["a", "b"])])
        XCTAssertTrue(p.same.isEmpty && p.new.isEmpty)
        let picked = try BoxMerge.apply(p, resolutions: [0: .existing("b")], to: [a, b])
        XCTAssertNil(picked[0].megaForm); XCTAssertEqual(picked[1].megaForm?.cp, 3970); XCTAssertEqual(picked[1].row.cp, 2500)
        // "new" is as before: the base species without CP, no Mega form
        let asNew = try BoxMerge.apply(p, resolutions: [0: .new], to: [a, b], makeID: { "n" })
        XCTAssertEqual(asNew[2].row.cp, 0); XCTAssertNil(asNew[2].megaForm)
        // no base entry at all: New as before
        XCTAssertEqual(plan([row("staraptor_mega", cp: 3970)], []).new, [0])
    }

    private func savedPair() -> [BoxEntry] {
        var base = entry(row("staraptor", cp: 2819), "base"); base.lastSeen = date(2)
        var mega = entry(row("staraptor_mega", cp: 3970), "mega"); mega.firstSeen = date(-3); mega.lastSeen = date(3)
        return [base, mega]
    }

    func testJoiningASavedMegaPairKeepsTheBaseEntryAndMovesTheOtherEntrysValuesIntoItsMegaForm() throws {
        let saved = savedPair()
        let p = plan([row("staraptor", cp: 2819)], saved, .full)
        XCTAssertEqual(p.unsure, [BoxMerge.Unsure(scanned: 0, candidates: ["base", "mega"], kind: .megaPair)])
        let out = try BoxMerge.apply(p, resolutions: [0: .existing("base")], to: saved)
        XCTAssertEqual(out.map { $0.id }, ["base"])
        XCTAssertEqual(out[0].row, saved[0].row); XCTAssertEqual(out[0].firstSeen, date(-3)); XCTAssertEqual(out[0].lastSeen, date(5))
        let mf = try XCTUnwrap(out[0].megaForm)
        XCTAssertEqual(mf.speciesId, "staraptor_mega"); XCTAssertEqual(mf.cp, 3970); XCTAssertEqual(mf.hp, 167); XCTAssertEqual(mf.level, 50)
        XCTAssertEqual(mf.firstSeen, date(-3)); XCTAssertEqual(mf.lastSeen, date(3), "a base scan did not see the Mega form")
        XCTAssertNil(out[0].megaWhenScanned)
        // the scan read the Mega form: it was seen now
        let viaMega = try BoxMerge.apply(plan([row("staraptor_mega", cp: 3970)], saved, .full), resolutions: [0: .existing("base")], to: saved)
        XCTAssertEqual(viaMega[0].megaForm?.lastSeen, date(5)); XCTAssertEqual(viaMega[0].megaWhenScanned, true)
        // a Mega form the base already had is never overwritten by an older one
        var withForm = saved; withForm[0].megaForm = MegaForm(row: row("staraptor_mega", cp: 4100), firstSeen: date(1), lastSeen: date(4))
        let kept = try BoxMerge.apply(p, resolutions: [0: .existing("base")], to: withForm)
        XCTAssertEqual(kept[0].megaForm?.cp, 4100); XCTAssertEqual(kept[0].megaForm?.firstSeen, date(-3))
    }

    func testKeepingBothOfASavedMegaPairIsAsBefore() throws {
        let saved = savedPair()
        let p = plan([row("staraptor", cp: 2819)], saved, .full)
        let out = try BoxMerge.apply(p, resolutions: [0: .leaveOut], to: saved)
        XCTAssertEqual(out.map { $0.id }, ["base", "mega"]); XCTAssertTrue(out.allSatisfy { $0.megaForm == nil })
        XCTAssertEqual(out[0].row, saved[0].row); XCTAssertEqual(out[1].row, saved[1].row)
        XCTAssertTrue(BoxMerge.goneReport(p, resolutions: [0: .leaveOut]).gone.isEmpty)
    }

    func testABaseRowForAnEntryFirstSavedAsMegaKeepsTheMegaValuesAsTheMegaForm() throws {
        let megaEntry = entry(row("staraptor_mega", cp: 3970, hp: 190), "m")
        let p = plan([row("staraptor", cp: 2819)], [megaEntry])
        let u = try XCTUnwrap(p.unsure.first)
        XCTAssertTrue(BoxMerge.keepsSavedMegaAsMegaForm(p, u, candidate: megaEntry, gameMaster: gm))
        let out = try BoxMerge.apply(p, resolutions: [0: .existing("m")], to: [megaEntry])
        XCTAssertEqual(out[0].row.speciesId, "staraptor"); XCTAssertEqual(out[0].row.cp, 2819)
        XCTAssertEqual(out[0].megaForm?.speciesId, "staraptor_mega"); XCTAssertEqual(out[0].megaForm?.cp, 3970); XCTAssertEqual(out[0].megaForm?.hp, 190)
        // "new" leaves the saved entry as it was
        let asNew = try BoxMerge.apply(p, resolutions: [0: .new], to: [megaEntry], makeID: { "n" })
        XCTAssertEqual(asNew[0], megaEntry)
    }

    func testAFullScanThatSawOnlyTheMegaFormDoesNotListTheBaseAsNotSeen() throws {
        let other = entry(row("pidgey", cp: 100, hp: 40, ivs: IVs(atk: 1, def: 2, hp: 3)), "other")
        let saved = [entry(row("staraptor", cp: 2819), "a"), other]
        let p = plan([row("staraptor_mega", cp: 3970, hp: 190)], saved, .full)
        XCTAssertEqual(p.gone, ["other"], "the Pokémon the scan did not see is listed, the paired base is not")
        XCTAssertEqual(BoxMerge.goneReport(p, resolutions: [:]).gone, ["other"], "only the entry the scan did not see")
        XCTAssertFalse(p.unpaired.contains { $0.id == "a" })
    }

    func testOneEntryWithAMegaFormIsOnePokemonInTheCountAdviceAndCSV() throws {
        let saved = entry(row("staraptor", cp: 2819), "a")
        let out = try BoxMerge.apply(plan([row("staraptor_mega", cp: 3970, hp: 190)], [saved]), to: [saved])
        XCTAssertEqual(out.count, 1)
        let rows = out.enumerated().map { i, e -> ScanRow in var r = e.row; r.index = i + 1; return r }
        let engine = try CoreEngine()
        let csv = try engine.csv(rows: rows, scanDate: date(5))
        XCTAssertEqual(csv.split(separator: "\n").count, 2, "a header and one Pokémon: the entry's base row, no second row for the Mega form")
        XCTAssertFalse(csv.contains("Mega"))
        XCTAssertNoThrow(try engine.advise(rows: rows, scanDate: date(5)))
    }

    // MARK: - format

    func testABoxWithoutAMegaFormEncodesAndDecodesAsBefore() throws {
        let e = entry(row("staraptor", cp: 2819), "a")
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(e)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("megaForm"), "no key when there is no Mega form")
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try dec.decode(BoxEntry.self, from: data), e)
        var withForm = e; withForm.megaForm = MegaForm(row: row("staraptor_mega", cp: 3970), firstSeen: date(1), lastSeen: date(2))
        XCTAssertEqual(try dec.decode(BoxEntry.self, from: try enc.encode(withForm)), withForm)
    }

    /// The entry as the build before the Mega form knew it (no `megaForm` key).
    private struct OldEntry: Codable, Equatable {
        var id: String; var row: ScanRow; var firstSeen: Date; var lastSeen: Date; var corrections: Corrections; var megaWhenScanned: Bool?
    }
    private func jsonKeys(_ data: Data) throws -> Set<String> { Set((try JSONSerialization.jsonObject(with: data) as! [String: Any]).keys) }

    func testABoxHoldingAMegaFormIsWrittenAsSchema1AndAnOlderBuildReadsItLosingOnlyTheMegaForm() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-mega-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = BoxLibrary(root: dir)
        try lib.createAccount("A")
        let plain = entry(row("staraptor", cp: 2819), "a")
        var with = plain; with.megaForm = MegaForm(row: row("staraptor_mega", cp: 3970), firstSeen: date(1), lastSeen: date(2)); with.megaWhenScanned = true
        let v1 = try lib.commit(account: "A", entries: [plain], reason: .scan, note: "plain", now: date(1))
        let v2 = try lib.commit(account: "A", entries: [with], reason: .scan, note: "mega", now: date(2))
        XCTAssertEqual(BoxLibrary.schemaVersion, 1); XCTAssertEqual(v1.schema, 1); XCTAssertEqual(v2.schema, 1)
        XCTAssertEqual(try lib.current(account: "A")?.entries, [with])
        XCTAssertNil(lib.newerVersion(account: "A"), "nothing here is 'saved by a newer version'")
        // the written file, read as the older build's entry shape: only megaForm is lost
        let files = FileManager.default.enumerator(atPath: dir.path)!.compactMap { $0 as? String }.filter { $0.hasSuffix("2.json") }
        let data = try Data(contentsOf: dir.appendingPathComponent(files[0]))
        let raw = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(raw["schema"] as? Int, 1)
        struct OldSnapshot: Decodable { var entries: [OldEntry] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let old = try dec.decode(OldSnapshot.self, from: data).entries
        XCTAssertEqual(old, [OldEntry(id: with.id, row: with.row, firstSeen: with.firstSeen, lastSeen: with.lastSeen, corrections: with.corrections, megaWhenScanned: true)])
    }

    func testAnEntryWithoutAMegaFormHasTheSameKeysAsBeforeTheChange() throws {
        let e = entry(row("staraptor", cp: 2819), "a")
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let old = OldEntry(id: e.id, row: e.row, firstSeen: e.firstSeen, lastSeen: e.lastSeen, corrections: e.corrections, megaWhenScanned: e.megaWhenScanned)
        XCTAssertEqual(try jsonKeys(try enc.encode(e)), try jsonKeys(try enc.encode(old)))
        XCTAssertFalse(try jsonKeys(try enc.encode(e)).contains("megaForm"))
    }

    func testAVersionAboveThisBuildsSchemaStillStopsAsSavedByANewerVersion() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-mega-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = BoxLibrary(root: dir)
        try lib.createAccount("A")
        try lib.commit(account: "A", entries: [entry(row("staraptor", cp: 2819), "a")], reason: .scan, note: "x", now: date(1))
        let file = FileManager.default.enumerator(atPath: dir.path)!.compactMap { $0 as? String }.first { $0.hasSuffix("1.json") }!
        var obj = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent(file))) as! [String: Any]
        obj["schema"] = BoxLibrary.schemaVersion + 1
        try JSONSerialization.data(withJSONObject: obj).write(to: dir.appendingPathComponent(file))
        XCTAssertEqual(BoxLibrary(root: dir).newerVersion(account: "A"), 1)
    }

    /// A box saved by the previous build, then scanned again (what a reread starts from): it loads, merges and saves with the Mega form.
    func testAnOlderBoxFileLoadsAndTheNextScanSavesTheMegaForm() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-mega-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = BoxLibrary(root: dir)
        try lib.createAccount("A")
        let plain = entry(row("staraptor", cp: 2819), "a")
        try lib.commit(account: "A", entries: [plain], reason: .scan, note: "old", now: date(1))
        let base = try XCTUnwrap(try lib.current(account: "A")).entries
        let out = try BoxMerge.apply(plan([row("staraptor_mega", cp: 3970, hp: 190)], base, .full), to: base)
        let snap = try lib.commit(account: "A", entries: out, reason: .scan, note: "new", now: date(5))
        XCTAssertEqual(snap.schema, 1); XCTAssertEqual(try lib.current(account: "A")?.entries.first?.megaForm?.cp, 3970)
    }

    private func megaRow(level: Double, dust: Int, cp: Int = 3970) -> ScanRow { var r = row("staraptor_mega", cp: cp); r.level = level; r.levelMax = level; r.dust = dust; return r }

    /// A join through a Mega row: the other entry's older values never beat a more recently seen Mega form, and what the scan read is what the form holds.
    func testJoiningThroughAMegaRowHoldsTheValuesReadNowAndNeverStampsOlderOnes() throws {
        var saved = savedPair()   // base last seen day 2; Mega entry (CP 3970) last seen day 3
        saved[0].megaForm = MegaForm(row: megaRow(level: 40, dust: 10000), firstSeen: date(1), lastSeen: date(4))
        var old = saved[1].row; old.level = 39; old.levelMax = 39; old.dust = 9000; saved[1].row = old
        let p = plan([megaRow(level: 40, dust: 10000)], saved, .full)
        XCTAssertEqual(p.unsure.first?.kind, .megaPair)
        let out = try BoxMerge.apply(p, resolutions: [0: .existing("base")], to: saved)
        let mf = try XCTUnwrap(out[0].megaForm)
        XCTAssertEqual(mf.level, 40); XCTAssertEqual(mf.dust, 10000); XCTAssertEqual(mf.lastSeen, date(5)); XCTAssertEqual(mf.firstSeen, date(-3), "the earliest of the forms")
        // read at a trusted CP only: a Mega row whose CP fits no level stores nothing, and the older values do not beat the newer form
        let flagged = plan([row("staraptor_mega", cp: 3970, flags: ["no-level-fits"])], saved, .full)
        XCTAssertEqual(flagged.unsure.first?.kind, .megaPair)
        let o = try BoxMerge.apply(flagged, resolutions: [0: .existing("base")], to: saved)
        XCTAssertEqual(o[0].megaForm?.level, 40); XCTAssertEqual(o[0].megaForm?.lastSeen, date(4))
    }

    /// Joining merges field by field: a more recently seen Mega entry that never read its CP, level or dust does not blank what the base entry's Mega form knows.
    func testJoiningNeverLetsUnreadValuesReplaceKnownOnes() throws {
        var saved = savedPair()   // the Mega entry was last seen day 3
        saved[0].megaForm = MegaForm(row: megaRow(level: 40, dust: 10000), firstSeen: date(1), lastSeen: date(2))
        var blank = saved[1].row; blank.cp = 0; blank.level = nil; blank.levelMax = nil; blank.dust = nil; saved[1].row = blank
        let p = plan([row("staraptor", cp: 2819)], saved, .full)
        XCTAssertEqual(p.unsure.first?.kind, .megaPair)
        let mf = try XCTUnwrap(try BoxMerge.apply(p, resolutions: [0: .existing("base")], to: saved)[0].megaForm)
        XCTAssertEqual(mf.cp, 3970); XCTAssertEqual(mf.level, 40); XCTAssertEqual(mf.levelMax, 40); XCTAssertEqual(mf.dust, 10000); XCTAssertEqual(mf.hp, 167)
        XCTAssertEqual(mf.firstSeen, date(-3)); XCTAssertEqual(mf.lastSeen, date(3))
    }

    /// The removed Mega-species entry's own row (a hand correction included) is adopted; its older megaForm only fills what the row lacks.
    func testJoiningAdoptsTheRemovedEntrysOwnRowNotItsOlderMegaForm() throws {
        var saved = savedPair()
        saved[1].row.cp = 4000; saved[1].row.dust = nil
        saved[1].megaForm = MegaForm(row: megaRow(level: 38, dust: 8000, cp: 3970), firstSeen: date(-5), lastSeen: date(1))
        let p = plan([row("staraptor", cp: 2819)], saved, .full)
        XCTAssertEqual(p.unsure.first?.kind, .megaPair)
        let mf = try XCTUnwrap(try BoxMerge.apply(p, resolutions: [0: .existing("base")], to: saved)[0].megaForm)
        XCTAssertEqual(mf.cp, 4000, "the corrected value"); XCTAssertEqual(mf.level, 50, "the row's own level"); XCTAssertEqual(mf.dust, 8000, "filled from the older form")
        XCTAssertEqual(mf.firstSeen, date(-5)); XCTAssertEqual(mf.lastSeen, date(3))
    }

    func testJoiningThroughTheBaseRowKeepsTheAdoptedValuesOwnDatesAndALaterFormWins() throws {
        var saved = savedPair()
        saved[1].row.level = 39
        let viaBase = try BoxMerge.apply(plan([row("staraptor", cp: 2819)], saved, .full), resolutions: [0: .existing("base")], to: saved)
        XCTAssertEqual(viaBase[0].megaForm?.level, 39); XCTAssertEqual(viaBase[0].megaForm?.lastSeen, date(3)); XCTAssertEqual(viaBase[0].megaForm?.firstSeen, date(-3))
        saved[0].megaForm = MegaForm(row: megaRow(level: 40, dust: 10000), firstSeen: date(1), lastSeen: date(4))
        let kept = try BoxMerge.apply(plan([row("staraptor", cp: 2819)], saved, .full), resolutions: [0: .existing("base")], to: saved)
        XCTAssertEqual(kept[0].megaForm?.level, 40); XCTAssertEqual(kept[0].megaForm?.lastSeen, date(4))
    }

    /// A Mega row whose CP fits no level, or that has no CP, never stores a Mega form, whichever way it reaches the entry.
    func testAnUntrustedMegaRowAnsweredItIsThisOneStoresNoMegaForm() throws {
        let a = entry(row("staraptor", cp: 2819), "a"), b = entry(row("staraptor", cp: 2500, hp: 160), "b")
        for bad in [row("staraptor_mega", cp: 3970, flags: ["no-level-fits"]), row("staraptor_mega", cp: 0)] {
            let p = plan([bad], [a, b])
            let u = try XCTUnwrap(p.unsure.first, "cp \(bad.cp) flags \(bad.flags) must reach a question")
            for c in u.candidates {
                let out = try BoxMerge.apply(p, resolutions: [0: .existing(c)], to: [a, b])
                XCTAssertTrue(out.allSatisfy { $0.megaForm == nil }, "cp \(bad.cp) flags \(bad.flags) candidate \(c)")
            }
            XCTAssertNotEqual(BoxMerge.effect(p, u, candidate: [a, b].first { $0.id == u.candidates[0] }!, gameMaster: gm), .replacesValues)
        }
    }
}
