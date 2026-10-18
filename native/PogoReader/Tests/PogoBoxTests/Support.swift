import Foundation
import XCTest
@testable import PogoBox
import PogoReader

enum Fixture {
    static func url(_ name: String) throws -> URL {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        return try XCTUnwrap(Bundle.module.url(forResource: parts[0], withExtension: parts[1], subdirectory: "Fixtures"), "fixture \(name) missing")
    }
    static func readings() throws -> [FrameReading] { try ReplayReadings.load(url: url("readings.json")).readings }
    static func expected() throws -> ScanResult { try JSONDecoder().decode(ScanResult.self, from: Data(contentsOf: url("expected.json"))) }
    static func expectedCSV() throws -> String { try String(contentsOf: url("expected.csv"), encoding: .utf8) }
}

/// The columns the comparison cares about, as one comparable value.
struct RowKey: Equatable, CustomStringConvertible {
    var name: String, form: String, speciesId: String, cp: Int, hp: Int?, ivs: IVs?, level: Double?, levelMax: Double?, flags: [String]
    init(_ r: ScanRow) { name = r.name; form = r.form; speciesId = r.speciesId; cp = r.cp; hp = r.hp; ivs = r.ivs; level = r.level; levelMax = r.levelMax; flags = r.flags }
    var description: String {
        let ivText: String = ivs.map { "\($0.atk)/\($0.def)/\($0.hp)" } ?? "-"
        let hpText: String = hp.map { String($0) } ?? "-"
        let lv: String = level.map { String($0) } ?? "-"
        let lvMax: String = levelMax.map { String($0) } ?? "-"
        return "\(name)/\(form)/\(speciesId) cp\(cp) hp\(hpText) \(ivText) L\(lv)-\(lvMax) \(flags)"
    }
}

/// One shared engine for the suite (loading the 1.7 MB game master is the slow part), used from the test thread only.
let sharedEngine = CoreEngine()
