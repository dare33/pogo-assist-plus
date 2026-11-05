import Foundation

/// Which species can take part in a Max Battle, and which have a G-Max move: the two lists the strength bars' "best in the game" on Max needs. Neither is in the game
/// master files the app reads (PvPoke's and PokeMiners'), so they are sourced constants, in the pattern of `HubCollection.releasedInGoDespiteFlag`.
///
/// Source: Pokemon GO Wiki (pokemongo.fandom.com), read through its MediaWiki API on 1 Nov 2026. Bulbapedia, the source first asked for, answers a script with a Cloudflare
/// challenge page, so it was not read. Pages and revisions:
/// - "Template:Data/Dynamax", revision 190794: the wiki's list of released Dynamax species (the entries marked "Yes": 148 names). `darmanitan_standard` stands for Darmanitan
///   and the two Urshifu styles for Urshifu, which the file names by species alone, and the three species below are added from "Max Moves": the array holds 152 ids.
/// - "Max Moves", revision 187269: Crowned Sword Zacian, Crowned Shield Zamazenta and Eternatus have their own Max Moves, so they are added.
/// - "Gigantamax", revision 190416, section "List of Gigantamax Pokémon": the Gigantamax forms released in Pokémon GO (17); "Max Moves", section "List of G-Max Moves": each
///   one's G-Max move and its type. Gigantamax forms the wiki lists as not released (Duraludon, Urshifu) are left out.
public enum MaxBattleSpecies {
    /// Game master ids of the species released in GO as Dynamax-capable.
    public static let dynamax: Set<String> = [
        "abra", "alakazam", "arcanine", "articuno", "azelf", "beldum",
        "blastoise", "blissey", "boldore", "bounsweet", "bulbasaur", "butterfree",
        "caterpie", "centiskorch", "chansey", "charizard", "charmander", "charmeleon",
        "cinderace", "combee", "corviknight", "corvisquire", "cottonee", "cryogonal",
        "darmanitan_standard", "darumaka", "deino", "drampa", "drilbur", "drizzile",
        "dubwool", "duraludon", "eevee", "electabuzz", "electivire", "entei",
        "espeon", "excadrill", "falinks", "feebas", "flareon", "flygon",
        "gallade", "garbodor", "gardevoir", "gastly", "gengar", "gigalith",
        "glaceon", "greedent", "grookey", "growlithe", "gyarados", "hatenna",
        "hatterene", "hattrem", "haunter", "hitmonchan", "hitmonlee", "hitmontop",
        "ho_oh", "hoothoot", "hydreigon", "inkay", "inteleon", "ivysaur",
        "jolteon", "kabuto", "kabutops", "kadabra", "kingler", "kirlia",
        "krabby", "kubfu", "latias", "latios", "leafeon", "lugia",
        "machamp", "machoke", "machop", "magikarp", "magmar", "magmortar",
        "malamar", "mesprit", "metagross", "metang", "metapod", "milotic",
        "moltres", "noctowl", "omanyte", "omastar", "passimian", "pidove",
        "pikachu", "raboot", "raichu", "raikou", "ralts", "regice",
        "regirock", "registeel", "rhydon", "rhyhorn", "rhyperior", "rillaboom",
        "roggenrola", "rookidee", "sableye", "scorbunny", "sealeo", "shuckle",
        "sizzlipede", "skwovet", "sneasel", "sobble", "spheal", "squirtle",
        "steenee", "suicune", "swoobat", "sylveon", "thwackey", "toxtricity",
        "tranquill", "trapinch", "trubbish", "tsareena", "umbreon", "unfezant",
        "urshifu_rapid_strike", "urshifu_single_strike", "uxie", "vaporeon", "venusaur", "vespiquen",
        "vibrava", "wailmer", "wailord", "walrein", "wartortle", "weavile",
        "whimsicott", "woobat", "wooloo", "zapdos", "zweilous",
        "zacian_crowned_sword", "zamazenta_crowned_shield", "eternatus",
    ]

    /// Gigantamax species released in GO with the type of their G-Max move. A Gigantamax copy's Max Attack is this move (power 350 at level 1), whatever its fast move's type.
    public static let gigantamax: [String: String] = [
        "venusaur": "grass",
        "charizard": "fire",
        "blastoise": "water",
        "butterfree": "bug",
        "pikachu": "electric",
        "meowth": "normal",
        "machamp": "fighting",
        "gengar": "ghost",
        "kingler": "water",
        "lapras": "ice",
        "snorlax": "normal",
        "garbodor": "poison",
        "rillaboom": "grass",
        "cinderace": "fire",
        "inteleon": "water",
        "toxtricity": "electric",
        "grimmsnarl": "dark",
    ]

    /// Max Moves that are fixed for a species, whatever its fast move ("Max Moves", revision 187269, "Details"): Crowned Sword Zacian has Max Behemoth Blade and Crowned Shield
    /// Zamazenta Max Behemoth Bash (Steel, the standard Max Attack power), Eternatus Max Dynamax Cannon (Dragon, at the G-Max power). The same page: a Dynamax Pokémon
    /// that knows Hidden Power as its fast move always gets Max Strike (Normal).
    public struct FixedMove { public var type: String; public var atGMaxPower: Bool }
    public static let fixedMaxMove: [String: FixedMove] = [
        "zacian_crowned_sword": FixedMove(type: "steel", atGMaxPower: false),
        "zamazenta_crowned_shield": FixedMove(type: "steel", atGMaxPower: false),
        "eternatus": FixedMove(type: "dragon", atGMaxPower: true),
    ]

    /// Every species that can take part: the Dynamax-capable ones and the Gigantamax ones (Meowth, Lapras, Snorlax and Grimmsnarl have no Dynamax form released).
    public static var capable: Set<String> { dynamax.union(gigantamax.keys) }
}
