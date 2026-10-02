import XCTest
@testable import PogoReader

final class ReplayLogTests: XCTestCase {
    private func tempURL() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("replay-\(UUID().uuidString).jsonl")
        addTeardownBlock { try? FileManager.default.removeItem(at: u) }
        return u
    }

    private func reading(_ t: Double, cp: Int?, name: String? = "Moltres", hp: Int? = 140) -> FrameReading {
        var r = FrameReading(frame: nil, time: t)
        r.cp = cp; r.cpText = cp.map { "CP\($0)" } ?? ""; r.name = name; r.nameText = name ?? ""; r.nameWeak = name == nil ? nil : false
        r.speciesIds = name.map { n in names.first { $0.display == n }?.speciesIds ?? [] }
        r.hp = hp.map { HP(current: $0, max: $0) }; r.hpText = hp.map { "\($0) / \($0) HP" } ?? ""
        r.ivs = IVs(atk: 15, def: 12, hp: 12); r.ivConfidence = 0.95; r.flags = cp == nil ? ["no-cp-text"] : []
        return r
    }

    func testEveryLineKindRoundTrips() throws {
        var r = reading(1.4, cp: 2409)
        r.nameAttached = true
        let lines: [ReplayLine] = [.reading(ReplayReading(r, time: 1.4, ms: 83.5)), .tick(2.2), .drop(2.4), .reading(ReplayReading(reading(3.0, cp: nil, name: nil, hp: nil), time: 3.0, ms: 4))]
        for line in lines {
            let data = ReplayLog.encode(line)
            XCTAssertFalse(data.contains(UInt8(ascii: "\n")), "one line")
            XCTAssertEqual(ReplayLog.decode(data), line)
        }
        // The reading comes back as the grouper was given it.
        if case .reading(let rr) = ReplayLog.decode(ReplayLog.encode(lines[0]))! {
            XCTAssertEqual(rr.frameReading.cp, 2409); XCTAssertEqual(rr.frameReading.cpReads, [2409]); XCTAssertEqual(rr.frameReading.time, 1.4)
            XCTAssertEqual(rr.frameReading.speciesIds, r.speciesIds); XCTAssertEqual(rr.frameReading.hp, r.hp); XCTAssertEqual(rr.frameReading.nameAttached, true)
        } else { XCTFail("not a reading") }
        XCTAssertNil(ReplayLog.decode(Data("not json".utf8)))
    }

    /// A hand-made log: two identical Pokémon whose swipe left no readings at all, only a tick, then a dropped frame.
    func testAHandMadeLogReplaysThroughTheGrouperInFileOrder() throws {
        let url = tempURL()
        let w = try XCTUnwrap(ReplayWriter(url: url))
        for k in 0..<4 { w.append(.reading(ReplayReading(reading(Double(k) * 0.2, cp: 2409), time: Double(k) * 0.2, ms: 80))) }
        w.append(.drop(0.8)); w.append(.drop(1.0))
        w.append(.tick(1.2))
        for k in 0..<4 { w.append(.reading(ReplayReading(reading(1.6 + Double(k) * 0.2, cp: 2409), time: 1.6 + Double(k) * 0.2, ms: 80))) }
        w.close()
        let lines = ReplayLog.lines(in: url)
        XCTAssertEqual(lines.count, 11)
        let res = ReplayLog.replay(lines, species: table)
        XCTAssertEqual(res.readings, 8); XCTAssertEqual(res.ticks, 1); XCTAssertEqual(res.drops, 2)
        XCTAssertEqual(res.rows.count, 2, "the tick splits the two identical Pokémon: \(res.rows.map { $0.flags })")
        XCTAssertEqual(res.rows.map(\.cp), [2409, 2409])
        // Without the tick line they merge: the replay really feeds the ticks.
        let noTick = ReplayLog.replay(lines.filter { if case .tick = $0 { return false }; return true }, species: table)
        XCTAssertEqual(noTick.rows.count, 1)
    }

    /// A log typed by hand as the extension writes it: readings and a tick in file order, a drop line for the record.
    func testALiteralLogFileReplaysAsTheExtensionWouldHave() throws {
        let line = { (t: Double) in "{\"k\":\"r\",\"t\":\(t),\"cp\":2409,\"cpText\":\"CP2409\",\"name\":\"Moltres\",\"nameText\":\"Moltres\",\"nameWeak\":false,\"hp\":{\"current\":131,\"max\":131},\"hpText\":\"131 / 131 HP\",\"ivs\":{\"atk\":15,\"def\":13,\"hp\":13},\"ivConfidence\":0.95,\"flags\":[],\"ms\":80}" }
        let text = [line(0), line(0.2), "{\"k\":\"d\",\"t\":0.4}", "{\"k\":\"t\",\"t\":0.8}", line(1.4), "garbage"].joined(separator: "\n") + "\n"
        let url = tempURL()
        try text.write(to: url, atomically: true, encoding: .utf8)
        let res = ReplayLog.replay(ReplayLog.lines(in: url), species: table)
        XCTAssertEqual([res.readings, res.ticks, res.drops], [3, 1, 1])
        XCTAssertEqual(res.rows.map(\.frames), [2, 1])      // the tick separates the two identical Pokémon; the garbage line is skipped
    }

    func testTheWriterStopsAtItsCapAndSaysSo() throws {
        let url = tempURL()
        let w = try XCTUnwrap(ReplayWriter(url: url, maxBytes: 400))
        var outcomes = [ReplayWriter.Outcome]()
        for k in 0..<10 { outcomes.append(w.append(.reading(ReplayReading(reading(Double(k), cp: 2409), time: Double(k), ms: 1)))) }
        XCTAssertTrue(w.truncated)
        XCTAssertFalse(w.failed)
        XCTAssertEqual(outcomes.filter { $0 == .truncatedNow }.count, 1, "reported once")
        XCTAssertEqual(outcomes.last, .disabled)
        XCTAssertLessThanOrEqual(w.bytes, 400)
        XCTAssertEqual(ReplayLog.lines(in: url).count, w.lineCount)
        // A half-written last line is skipped, not an error.
        try (try Data(contentsOf: url) + Data("{\"k\":\"t\",\"t\"".utf8)).write(to: url)
        XCTAssertEqual(ReplayLog.lines(in: url).count, w.lineCount)
    }

    func testAFullLogStillTakesTheEndMarker() throws {
        let url = tempURL()
        let w = try XCTUnwrap(ReplayWriter(url: url, maxBytes: 400))
        for k in 0..<10 { w.append(.reading(ReplayReading(reading(Double(k), cp: 2409), time: Double(k), ms: 1))) }
        XCTAssertTrue(w.truncated)
        XCTAssertEqual(w.append(.end(at: 12.5, last: 9)), .written, "the marker has room past the cap")
        XCTAssertEqual(ReplayLog.lines(in: url).last, .end(at: 12.5, last: 9))
        XCTAssertEqual(w.append(.tick(14)), .disabled, "ordinary lines stay refused")
    }

    func testAWriteErrorDisablesTheLogOnceAndNeverThrows() throws {
        struct Boom: Error {}
        var writes = 0
        let w = ReplayWriter(sink: { _ in writes += 1; if writes == 3 { throw Boom() } })
        var outcomes = [ReplayWriter.Outcome]()
        for k in 0..<6 { outcomes.append(w.append(.tick(Double(k)))) }
        XCTAssertEqual(outcomes, [.written, .written, .failedNow, .disabled, .disabled, .disabled])
        XCTAssertTrue(w.failed)
        XCTAssertEqual(writes, 3, "no write after the failure")
        XCTAssertNil(ReplayWriter(url: URL(fileURLWithPath: "/nonexistent-dir-\(UUID().uuidString)/replay.jsonl")), "an unopenable file gives no writer")
        let url = tempURL()
        let closed = try XCTUnwrap(ReplayWriter(url: url))
        closed.close()
        XCTAssertEqual(closed.append(.tick(1)), .disabled)
    }
}
