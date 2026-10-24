import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// The Hub's derivations, pinned on the report the advisor gives for the fixture box.
final class HubModelTests: XCTestCase {
    private func advice() throws -> BoxAdvice {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 12))!
        let es = try Fixture.expected().rows.enumerated().map { i, r in BoxEntry(id: "e\(i)", row: r, firstSeen: date, lastSeen: date) }
        return BoxAdvice.make(from: try sharedEngine.advise(rows: es.map(\.row)), entries: es)
    }

    /// A fixture build with its figures changed, for the cases the five fixture builds do not reach.
    private func variant(_ b: BoxAdvice.Build, areas: [String]? = nil, dust: Int? = nil, candy: Int? = nil) -> BoxAdvice.Build {
        var v = b
        if let areas { v.areas = areas }
        if let dust { v.dust = dust }
        if let candy { v.candy = candy }
        return v
    }

    func testCountsPerScreenOnTheFixture() throws {
        let b = try advice().builds
        XCTAssertEqual(b.map(\.targetName), ["Lucario", "Zamazenta (Crowned Shield)", "Xerneas", "Staraptor", "Moltres"])
        let counts = Dictionary(uniqueKeysWithValues: ContentKey.allCases.map { ($0.rawValue, HubModel.count(b, for: $0)) })
        XCTAssertEqual(counts, ["everything": 5, "raids": 5, "gym": 0, "rocket": 1, "pvp": 2, "max": 1])
        XCTAssertEqual(HubModel.builds(b, for: .pvp).map(\.targetName), ["Zamazenta (Crowned Shield)", "Xerneas"])
        XCTAssertEqual(HubModel.builds(b, for: .rocket).map(\.targetName), ["Lucario"])
    }

    func testHeadlineCardWording() throws {
        let b = try advice().builds
        XCTAssertEqual(b.map(HubModel.headline(for:)), ["Mega evolve Lucario", "Form change Zamazenta (Hero) → Zamazenta (Crowned Shield)", "Power up Xerneas", "Staraptor (Mega)", "Power up Moltres"])
        XCTAssertEqual(b.map(HubModel.cardLine(for:)), ["75k dust · Raids", "206k dust · Raids", "206k dust · Raids", "Free · Raids", "137k dust · Raids"])
        var eevee = b[4]; eevee.title = "Eevee"; eevee.targetName = "Flareon"; eevee.dust = 6_600
        eevee.steps = [.init(kind: "evolve", to: "Flareon", candy: 25)]; eevee.areas = ["GL"]
        XCTAssertEqual(HubModel.headline(for: eevee), "Evolve Eevee → Flareon")
        XCTAssertEqual(HubModel.cardLine(for: eevee), "6,600 dust · Great League")
    }

    func testGapsFollowTheirArea() {
        let g = [BoxAdvice.Gap(area: "Raids", section: "Dark", tier: "S", name: "Tyranitar", obtain: nil, haveBase: false),
                 BoxAdvice.Gap(area: "GL", section: nil, tier: "A", name: "Azumarill", obtain: nil, haveBase: false),
                 BoxAdvice.Gap(area: "ML", section: nil, tier: "S", name: "Dialga", obtain: nil, haveBase: false)]
        XCTAssertEqual(HubModel.gaps(g, for: .everything).count, 3)
        XCTAssertEqual(HubModel.gaps(g, for: .pvp).map(\.name), ["Azumarill", "Dialga"])
        XCTAssertEqual(HubModel.gaps(g, for: .raids).map(\.name), ["Tyranitar"])
        XCTAssertTrue(HubModel.gaps(g, for: .max).isEmpty)
    }

    func testFittingStopsAtTheFirstBuildThatDoesNotFit() throws {
        let b = try advice().builds
        let none = HubModel.fitting(b, stardust: 0)
        XCTAssertEqual(none.fits.map(\.targetName), ["Staraptor"], "with no stardust only the free build fits")
        XCTAssertEqual(none.used, 0); XCTAssertEqual(none.left, 0)
        let some = HubModel.fitting(b, stardust: 100_000)
        XCTAssertEqual(some.fits.map(\.targetName), ["Lucario", "Staraptor"])
        XCTAssertEqual(some.used, 75_000); XCTAssertEqual(some.left, 25_000)
        let most = HubModel.fitting(b, stardust: 612_400)
        XCTAssertEqual(most.fits.map(\.targetName), ["Lucario", "Zamazenta (Crowned Shield)", "Xerneas", "Staraptor"])
        XCTAssertEqual(most.used, 487_000); XCTAssertEqual(most.left, 125_400)
        // Moltres (137,000) would not fit the 125,400 left, and a cheaper later build must not jump the queue; a free one still does.
        let queue = [b[0], variant(b[4], dust: 300_000), variant(b[2], dust: 1_000), variant(b[3])]
        let r = HubModel.fitting(queue, stardust: 100_000)
        XCTAssertEqual(r.fits.map(\.id), [b[0].id, b[3].id])
    }

    func testHeadlinesOnTheFixture() throws {
        let b = try advice().builds
        let unknown = HubModel.headlines(b, stardust: nil)
        XCTAssertEqual(unknown.doFirst?.targetName, "Lucario")
        XCTAssertEqual(unknown.cheapWin?.targetName, "Zamazenta (Crowned Shield)", "ties on dust and candy keep the advisor's order")
        XCTAssertEqual(unknown.worthSavingFor?.targetName, "Xerneas", "no stardust: the highest-dust S build left")
        let low = HubModel.headlines(b, stardust: 100_000)
        XCTAssertEqual(low.worthSavingFor?.targetName, "Xerneas", "dearer than the stardust, highest score of Xerneas 2.86 and Moltres 1.84")
        let high = HubModel.headlines(b, stardust: 612_400)
        XCTAssertEqual(high.cheapWin?.targetName, "Zamazenta (Crowned Shield)")
        XCTAssertNil(high.worthSavingFor, "nothing costs more than 612,400")
        XCTAssertNil(HubModel.headlines([], stardust: nil).doFirst)
    }

    func testCheapWinSkipsFinishedBuildsAndLowerTiers() throws {
        let b = try advice().builds
        // Staraptor (Mega) is tier B and already built; making it A still leaves it out (nothing to do).
        var built = b[3]; built.tier = "A"
        XCTAssertEqual(HubModel.headlines([b[0], built, b[4]], stardust: nil).cheapWin?.targetName, nil, "Moltres is B, Staraptor has no step left")
        var cheap = b[4]; cheap.tier = "A"; cheap.dust = 5_000
        XCTAssertEqual(HubModel.headlines([b[0], b[1], cheap], stardust: nil).cheapWin?.targetName, "Moltres")
    }

    func testDustShort() {
        XCTAssertEqual(HubModel.dustShort(0), "0")
        XCTAssertEqual(HubModel.dustShort(6_600), "6,600")
        XCTAssertEqual(HubModel.dustShort(9_999), "9,999")
        XCTAssertEqual(HubModel.dustShort(10_000), "10k")
        XCTAssertEqual(HubModel.dustShort(57_000), "57k")
        XCTAssertEqual(HubModel.dustShort(488_800), "489k")
        XCTAssertEqual(HubModel.dustShort(999_600), "1M")
        XCTAssertEqual(HubModel.dustShort(1_200_000), "1.2M")
        XCTAssertEqual(HubModel.dustShort(1_249_999), "1.2M")
    }

    func testAreaLabelIsTheDesignsSubLine() throws {
        let b = try advice().builds
        XCTAssertEqual(HubModel.areaLabel(for: b[0]), "Raids, Rocket · 75k dust")
        XCTAssertEqual(HubModel.areaLabel(for: b[1]), "Raids, Max, PvP · 206k dust")
        XCTAssertEqual(HubModel.areaLabel(for: b[2]), "Raids, PvP · 206k dust")
        XCTAssertEqual(HubModel.areaLabel(for: b[3]), "Raids · Free")
        XCTAssertEqual(HubModel.areaLabel(for: variant(b[4], areas: ["Gym", "Max"], dust: 10_000)), "Gym, Max · 10k dust")
        XCTAssertEqual(HubModel.areaLabel(for: variant(b[4], areas: ["GL"], dust: 52_000)), "Great League · 52k dust")
        XCTAssertEqual(HubModel.areaLabel(for: variant(b[4], areas: ["GL", "UL"], dust: 6_600)), "PvP · 6,600 dust")
        XCTAssertEqual(HubModel.areaLabel(for: variant(b[4], areas: ["Raids", "Rocket", "GL"], dust: 0, candy: 100)), "Raids, Rocket, PvP · 100 candy")
    }

    func testEventsStripIsSortedAndDropsPastEvents() throws {
        let events = try HubData.bundled().events
        let today = "2026-10-25"
        let strip = HubModel.upcoming(events, today: today)
        XCTAssertEqual(strip.first?.title, "GO Battle League: Twilight Trails", "it began on 8 Sep and runs to 1 Dec")
        XCTAssertFalse(strip.contains { $0.title == "Zorua Community Day" }, "10 Oct is past")
        XCTAssertEqual(strip.map(\.from), strip.map(\.from).sorted())
        XCTAssertEqual(strip.count, events.count - 1)
        XCTAssertEqual(HubModel.upcoming(events, today: "2026-11-21").first?.title, "GO Battle League: Twilight Trails")
        XCTAssertTrue(HubModel.upcoming(events, today: "2026-12-02").isEmpty)
        // An event on its last day is still shown.
        XCTAssertTrue(HubModel.upcoming(events, today: "2026-12-01").contains { $0.to == "2026-12-01" })
    }

    func testEventDates() {
        let today = "2026-10-25"
        XCTAssertEqual(HubModel.span(from: "2026-11-01", to: "2026-11-05", today: today).kicker, "1 – 5 NOV")
        XCTAssertEqual(HubModel.span(from: "2026-11-01", to: "2026-11-05", today: today).spoken, "1 to 5 November")
        XCTAssertEqual(HubModel.span(from: "2026-11-21", to: "2026-11-21", today: today).kicker, "21 NOV")
        XCTAssertEqual(HubModel.span(from: "2026-09-08", to: "2026-12-01", today: today).kicker, "NOW TO 1 DEC")
        XCTAssertEqual(HubModel.span(from: "2026-09-08", to: "2026-12-01", today: today).spoken, "now to 1 December")
        XCTAssertEqual(HubModel.span(from: "2026-10-28", to: "2026-11-03", today: today).kicker, "28 OCT – 3 NOV")
        XCTAssertEqual(HubModel.span(from: "2026-10-25", to: "2026-10-25", today: today).kicker, "25 OCT", "a one-day event today")
        XCTAssertEqual(HubModel.span(from: "2026-10-25", to: "2026-10-27", today: today).kicker, "25 – 27 OCT", "starts today: not yet 'now to'")
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Australia/Sydney")!
        let d = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 23, minute: 30))!
        XCTAssertEqual(HubModel.dayKey(d, calendar: cal), "2026-10-25")
    }
}
