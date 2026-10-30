import XCTest
@testable import PogoAssist
@testable import PogoBox
import PogoReader

/// My Pokémon's search understands the game's words for the special types (phone feedback item 12), and the Special sets cards open the same lists (item 11): both read
/// `HubCollection.Membership`, so a set's list in the index is exactly the engine's members.
final class BoxSearchWordsTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private let hundo = IVs(atk: 15, def: 15, hp: 15)

    private func entry(_ id: String, _ species: String, ivs: IVs? = IVs(atk: 10, def: 10, hp: 10), cp: Int = 1000, shadow: Int? = nil, dynamax: Bool? = nil,
                       gigantamax: Bool? = nil, lucky: Bool? = nil, buddy: Bool? = nil) -> BoxEntry {
        let s = gm.byId[species]!
        let nf = GameMaster.nameAndForm(s.name)
        let row = ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: species, dex: s.dex, cp: cp, hp: 100, ivs: ivs, ivsRead: ivs, ivsGuess: nil,
                          level: 30, levelMax: 30, dust: nil, solveStatus: "exact", flags: [], frames: [], shadow: shadow, dynamax: dynamax, gigantamax: gigantamax, lucky: lucky,
                          details: buddy.map { CopyDetails(bestBuddy: $0) })
        let d = Date(timeIntervalSince1970: 1_790_000_000)
        return BoxEntry(id: id, row: row, firstSeen: d, lastSeen: d)
    }

    private lazy var box: [BoxEntry] = [
        entry("pika", "pikachu", ivs: hundo),
        entry("pika-shadow", "pikachu", shadow: 1),
        entry("pika-purified", "pikachu", shadow: 2),
        entry("regi", "registeel", lucky: true),
        entry("mew", "mew"),
        entry("nihil", "nihilego", shadow: 1),
        entry("meganium", "meganium"),
        entry("zard", "charizard", dynamax: true, gigantamax: true),
        entry("eevee", "eevee", buddy: true),
        entry("eevee2", "eevee", cp: 2100),
        entry("marshadow", "marshadow"),
        entry("yanmega", "yanmega"),
        entry("mime-shadow", "mr_mime", shadow: 1),
        entry("mime", "mr_mime"),
        entry("farfetchd", "farfetchd"),
        entry("nidoran", "nidoran_female"),
        entry("shadow-1800", "slowbro", cp: 1800, shadow: 1),
        entry("gira-a", "giratina_altered"),
        entry("gira-o", "giratina_origin"),
    ]
    private lazy var index = BoxIndex(entries: box, gm: gm)

    private func ids(_ q: String) -> Set<String> {
        let query = BoxIndex.Query(q)
        return Set(index.items.filter { index.matches($0, query, .all) }.map(\.id))
    }

    // MARK: the parser

    func testPlainSearchesAreAsBefore() {
        XCTAssertEqual(BoxIndex.Query("pika"), .text("pika"))
        XCTAssertEqual(BoxIndex.Query("  Pika  "), .text("pika"))
        XCTAssertEqual(BoxIndex.Query("2819"), .cp(2819...2819))
        XCTAssertEqual(BoxIndex.Query("cp1500-2500"), .cp(1500...2500))
        XCTAssertEqual(BoxIndex.Query(""), .none)
        XCTAssertEqual(BoxIndex.Query("mr. mime"), .text("mr. mime"))
        XCTAssertEqual(BoxIndex.Query("farfetch'd"), .text("farfetch'd"))
        XCTAssertEqual(BoxIndex.Query("nidoran♀"), .text("nidoran♀"))
        XCTAssertEqual(BoxIndex.Query("cp1500-"), .cp(1500...Int.max))
        XCTAssertEqual(BoxIndex.Query("cp-2500"), .cp(0...2500))
    }

    func testTheSpecialWordsAreRecognisedWhole() {
        for (word, expected) in [("shadow", BoxIndex.SearchWord.shadow), ("Purified", .purified), ("LUCKY", .lucky), ("dynamax", .dynamax), ("max", .dynamax),
                                 ("gigantamax", .gigantamax), ("gmax", .gigantamax), ("legendary", .legendary), ("mythical", .mythical),
                                 ("ultra beasts", .ultraBeast), ("ultra beast", .ultraBeast), ("ultrabeast", .ultraBeast), ("ultra-beast", .ultraBeast), ("ultra-beasts", .ultraBeast),
                                 ("g-max", .gigantamax), ("best buddies", .buddy), ("shadow,", .shadow), ("hundo.", .hundo), ("mega", .mega),
                                 ("100%", .hundo), ("hundo", .hundo), ("buddy", .buddy), ("best buddy", .buddy)] {
            guard case .words(let w) = BoxIndex.Query(word) else { return XCTFail("\(word) is a special word") }
            XCTAssertEqual(w.tokens.map(\.word), [expected], word)
        }
        // Not whole: a piece of a longer word stays a piece of a name.
        XCTAssertEqual(BoxIndex.Query("shadowy"), .text("shadowy"))
        XCTAssertEqual(BoxIndex.Query("maxi"), .text("maxi"))
    }

    func testSeveralWordsSplitAtSpacesAndAmpersands() {
        guard case .words(let a) = BoxIndex.Query("shadow legendary"), case .words(let b) = BoxIndex.Query("shadow&legendary"), case .words(let c) = BoxIndex.Query("shadow & legendary") else { return XCTFail() }
        XCTAssertEqual(a.tokens.map(\.word), [.shadow, .legendary])
        XCTAssertEqual(b.tokens.map(\.word), [.shadow, .legendary])
        XCTAssertEqual(c.tokens.map(\.word), [.shadow, .legendary])
        guard case .words(let d) = BoxIndex.Query("ultra beasts shadow"), case .words(let e) = BoxIndex.Query("pika best buddy") else { return XCTFail() }
        XCTAssertEqual(d.tokens.map(\.word), [.ultraBeast, .shadow])
        XCTAssertEqual(e.tokens.map(\.text), ["pika", "best buddy"])
    }

    // MARK: matching

    func testEachWordFindsItsCopies() {
        XCTAssertEqual(ids("shadow"), ["pika-shadow", "nihil", "mime-shadow", "shadow-1800"])
        XCTAssertEqual(ids("purified"), ["pika-purified"])
        XCTAssertEqual(ids("lucky"), ["regi"])
        XCTAssertEqual(ids("dynamax"), ["zard"])
        XCTAssertEqual(ids("max"), ["zard"])
        XCTAssertEqual(ids("gmax"), ["zard"])
        XCTAssertEqual(ids("gigantamax"), ["zard"])
        XCTAssertEqual(ids("legendary"), ["regi", "gira-a", "gira-o"])
        XCTAssertEqual(ids("mythical"), ["mew", "marshadow"])
        XCTAssertEqual(ids("ultra beasts"), ["nihil"])
        XCTAssertEqual(ids("ultrabeast"), ["nihil"])
        XCTAssertEqual(ids("hundo"), ["pika"])
        XCTAssertEqual(ids("100%"), ["pika"])
        XCTAssertEqual(ids("buddy"), ["eevee"])
        XCTAssertEqual(ids("best buddy"), ["eevee"])
        XCTAssertEqual(ids("SHADOW"), ["pika-shadow", "nihil", "mime-shadow", "shadow-1800"], "case does not matter")
    }

    func testCombinationsNeedEveryWord() {
        XCTAssertEqual(ids("shadow ultra beasts"), ["nihil"])
        XCTAssertEqual(ids("shadow & legendary"), [])
        XCTAssertEqual(ids("shadow & mythical"), [])
        XCTAssertEqual(ids("mythical hundo"), [])
    }

    func testANameWithAWordKeepsTheNamePart() {
        XCTAssertEqual(ids("pika shadow"), ["pika-shadow"])
        XCTAssertEqual(ids("pikachu hundo"), ["pika"])
        XCTAssertEqual(ids("eevee best buddy"), ["eevee"])
    }

    func testAWordThatStartsANameReturnsTheUnion() {
        // "mega": Charizard (Mega-capable) and Meganium (a name that starts with it); not Yanmega, which only contains it.
        XCTAssertTrue(ids("mega").isSuperset(of: ["zard", "meganium"]))
        XCTAssertFalse(ids("mega").contains("yanmega"))
        XCTAssertFalse(ids("shadow").contains("marshadow"), "Marshadow only contains the word")
        XCTAssertEqual(ids("max"), ["zard"], "no name starts with max")
        // A plain piece of a name stays a substring.
        XCTAssertEqual(ids("shadow").contains("marshadow"), false)
        XCTAssertTrue(ids("adow").contains("marshadow"))
        XCTAssertTrue(ids("mega").isDisjoint(with: ["marshadow", "pika-shadow", "nihil"]))
    }

    func testNamesWithPunctuationAndWordsTogether() {
        XCTAssertEqual(ids("farfetch'd"), ["farfetchd"])
        XCTAssertEqual(ids("nidoran♀"), [], "the game master spells it Nidoran Female, as before")
        XCTAssertEqual(ids("mr. mime"), ["mime-shadow", "mime"])
        XCTAssertEqual(ids("mr. mime shadow"), ["mime-shadow"])
        XCTAssertEqual(ids("mr mime, shadow"), ["mime-shadow"])
    }

    func testCPCombinesWithWords() {
        XCTAssertEqual(ids("shadow cp1500-2500"), ["shadow-1800"])
        XCTAssertEqual(ids("shadow&cp1500-2500"), ["shadow-1800"])
        XCTAssertEqual(ids("shadow cp1500-"), ["shadow-1800"])
        XCTAssertEqual(ids("shadow cp-1100"), ["pika-shadow", "nihil", "mime-shadow"])
        XCTAssertEqual(ids("shadow cp1800"), ["shadow-1800"])
        XCTAssertEqual(ids("eevee cp2000-"), ["eevee2"])
        XCTAssertEqual(ids("eevee 2100"), [], "a bare number among words is a piece of a name")
    }

    /// The sheet lists a species set's forms as separate rows; grouped by dex number they are the card's species count.
    func testASpeciesSetsRowsGroupedByDexAreTheCardsCount() {
        let sets = HubCollection.specialSets(entries: box, gm: gm)
        let legendary = sets.first { $0.name == "Legendary" }!
        let rows = index.sections(query: .keyword(.legendary), chip: .all, sort: .name).flatMap(\.rows)
        XCTAssertTrue(rows.contains { $0.title.hasPrefix("Giratina (Altered") } && rows.contains { $0.title.hasPrefix("Giratina (Origin") }, "forms are rows of their own")
        XCTAssertEqual(Set(rows.compactMap { gm.byId[$0.speciesId]?.dex }).count, legendary.owned, "one species each")
        XCTAssertGreaterThan(rows.count, legendary.owned ?? 0)
    }

    func testCPSearchesStillWork() {
        XCTAssertEqual(ids("2100"), ["eevee2"])
        XCTAssertEqual(ids("cp900-1100").contains("pika"), true)
        XCTAssertEqual(ids("cp2000-2200"), ["eevee2"])
        XCTAssertEqual(ids("meganium"), ["meganium"])
    }

    // MARK: the Special sets lists

    /// A card's list is the engine's members: the index asked for the set's word returns the same copies, for every set.
    func testEachSetsListInTheIndexIsTheEnginesMembers() {
        let lucky: (BoxEntry) -> Bool = HubCollection.isLuckyMarked
        for kind in HubCollection.SetKind.allCases {
            let members = Set(HubCollection.members(of: kind, entries: box, gm: gm, isLucky: lucky).map(\.id))
            let query = BoxIndex.Query.keyword(BoxIndex.SearchWord(kind))
            let listed = Set(index.items.filter { index.matches($0, query, .all) }.map(\.id))
            XCTAssertEqual(listed, members, kind.name)
            let sectioned = index.sections(query: query, chip: .all, sort: .name).flatMap(\.rows).reduce(0) { $0 + $1.stats.count }
            XCTAssertEqual(sectioned, members.count, "\(kind.name): the sheet's rows count the same copies")
        }
        let sets = HubCollection.specialSets(entries: box, gm: gm)
        XCTAssertEqual(sets.first { $0.name == "Lucky" }?.owned, 1)
    }

    func testAnEmptyLuckySetListsNothing() {
        let none = [entry("a", "pikachu")]
        let idx = BoxIndex(entries: none, gm: gm)
        XCTAssertEqual(idx.sections(query: .keyword(.lucky), chip: .all, sort: .name).count, 0)
        XCTAssertEqual(HubCollection.specialSets(entries: none, gm: gm).first { $0.name == "Lucky" }?.note, "Not in your scans yet")
    }

    /// The sheet shows its sections only with the index they were built for (a row is a position in that index).
    func testTheSheetShowsSectionsOnlyForTheIndexTheyWereBuiltFor() {
        XCTAssertTrue(CollectionSetSheet.showsSections(computedFor: "Greg|3", storeKey: "Greg|3"))
        XCTAssertFalse(CollectionSetSheet.showsSections(computedFor: "Greg|3", storeKey: "Greg|4"), "a newer index: the old rows would point at the wrong copies")
        XCTAssertFalse(CollectionSetSheet.showsSections(computedFor: "Greg|3", storeKey: nil))
        XCTAssertFalse(CollectionSetSheet.showsSections(computedFor: nil, storeKey: nil))
    }
}
