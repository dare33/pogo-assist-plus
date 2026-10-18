import Foundation
import XCTest
@testable import PogoBox
import PogoReader

final class EngineErrorTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-engine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    /// The bundled data files, so a test can swap just the script.
    private func engine(script: String) throws -> CoreEngine {
        let url = dir.appendingPathComponent("s.js")
        try Data(script.utf8).write(to: url)
        for f in ["gamemaster.json", "tiers.json", "pvp-rankings.json"] { try Data("{}".utf8).write(to: dir.appendingPathComponent(f)) }
        return CoreEngine(scriptURL: url, dataDirectory: dir)
    }

    func testExceptionInACallSurfacesWithMessageAndLine() throws {
        let e = try engine(script: "globalThis.PogoCore = {\n load() { return true; },\n finishJSON() {\n  throw new Error('boom from finish');\n } };")
        XCTAssertThrowsError(try e.finish(readings: [])) { error in
            guard case CoreEngine.Failure.script(let message, let line) = error else { return XCTFail("wrong error \(error)") }
            XCTAssertTrue(message.contains("boom from finish"), message)
            XCTAssertEqual(line, 4)
            XCTAssertTrue(error.localizedDescription.contains("line 4"))
        }
        // the engine is still usable and reports the next error too (the exception was cleared)
        XCTAssertThrowsError(try e.finish(readings: []))
    }

    func testSyntaxErrorInTheScriptSurfaces() throws {
        let e = try engine(script: "globalThis.PogoCore = {\n load( {\n")
        XCTAssertThrowsError(try e.prepare()) { error in
            guard case CoreEngine.Failure.script(let message, _) = error else { return XCTFail("wrong error \(error)") }
            XCTAssertTrue(message.contains("SyntaxError"), message)
        }
    }

    func testScriptThatDefinesNothingIsRejected() throws {
        let e = try engine(script: "var x = 1;")
        XCTAssertThrowsError(try e.prepare()) { XCTAssertEqual($0 as? CoreEngine.Failure, .badResult("pogo-core.js did not define PogoCore")) }
    }

    func testMissingDataFileIsNamed() throws {
        let e = try engine(script: "globalThis.PogoCore = { load() {} };")
        try FileManager.default.removeItem(at: dir.appendingPathComponent("tiers.json"))
        XCTAssertThrowsError(try e.prepare()) {
            guard case CoreEngine.Failure.resourceMissing(let n) = $0 else { return XCTFail("wrong error \($0)") }
            XCTAssertTrue(n.hasSuffix("tiers.json"))
        }
    }

    func testBadJsonFromTheDataIsAnExceptionNotACrash() throws {
        let e = try engine(script: "globalThis.PogoCore = { load(g) { JSON.parse(g); } };")
        try Data("{not json".utf8).write(to: dir.appendingPathComponent("gamemaster.json"))
        XCTAssertThrowsError(try e.prepare()) {
            guard case CoreEngine.Failure.script(let m, _) = $0 else { return XCTFail("wrong error \($0)") }
            XCTAssertTrue(m.contains("JSON"), m)
        }
    }
}
