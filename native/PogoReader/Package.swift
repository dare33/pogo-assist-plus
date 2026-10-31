// swift-tools-version: 5.9
import PackageDescription

// Swift 5 language mode on purpose: the Vision and vImage callbacks are not worth fighting strict
// concurrency over in a prototype.
let package = Package(
    name: "PogoReader",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PogoReader", targets: ["PogoReader"]),
        // The screenshot queue (staging, manifests, duplicate ledger). The share extension links this and nothing larger.
        .library(name: "PogoImport", targets: ["PogoImport"]),
        .executable(name: "pogo-read", targets: ["pogo-read"]),
        .executable(name: "pogo-drop", targets: ["pogo-drop"]),
        // The app core: the project's JavaScript grouping/solver in JavaScriptCore, the saved box, the CSV.
        // The app links this; the broadcast extension must NOT (iOS kills it at about 50 MB).
        .library(name: "PogoBox", targets: ["PogoBox"]),
        .executable(name: "pogo-rows", targets: ["pogo-rows"]),
        .executable(name: "pogo-voice", targets: ["pogo-voice"]),
    ],
    targets: [
        // Decoding, orienting, stripping and hashing one image: ImageIO and CryptoKit, nothing that touches file dates. The broadcast extension links it through PogoReader.
        .target(name: "PogoImage"),
        .target(name: "PogoImport", dependencies: ["PogoImage"]),
        .testTarget(name: "PogoImportTests", dependencies: ["PogoImport"]),
        .target(name: "PogoReader", dependencies: ["PogoImage"], resources: [.copy("Resources/species.json")]),
        .executableTarget(name: "pogo-read", dependencies: ["PogoReader"]),
        .executableTarget(name: "pogo-drop", dependencies: ["PogoReader"]),
        .testTarget(name: "PogoReaderTests", dependencies: ["PogoReader"]),
        .target(name: "PogoBox", dependencies: ["PogoReader", "PogoImport"], resources: [
            .copy("Resources/pogo-core.js"), .copy("Resources/gamemaster.json"),
            .copy("Resources/tiers.json"), .copy("Resources/pvp-rankings.json"), .copy("Resources/hub.json"),
        ]),
        .executableTarget(name: "pogo-rows", dependencies: ["PogoBox", "PogoReader"]),
        .executableTarget(name: "pogo-voice", dependencies: ["PogoBox"]),
        .testTarget(name: "PogoBoxTests", dependencies: ["PogoBox", "PogoReader", "PogoImport"], resources: [.copy("Fixtures")]),
    ]
)
