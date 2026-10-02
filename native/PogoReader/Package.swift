// swift-tools-version: 5.9
import PackageDescription

// Swift 5 language mode on purpose: the Vision and vImage callbacks are not worth fighting strict
// concurrency over in a prototype.
let package = Package(
    name: "PogoReader",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PogoReader", targets: ["PogoReader"]),
        .executable(name: "pogo-read", targets: ["pogo-read"]),
        .executable(name: "pogo-drop", targets: ["pogo-drop"]),
        // The app core: the project's JavaScript grouping/solver in JavaScriptCore, the saved box, the CSV.
        // The app links this; the broadcast extension must NOT (iOS kills it at about 50 MB).
        .library(name: "PogoBox", targets: ["PogoBox"]),
        .executable(name: "pogo-rows", targets: ["pogo-rows"]),
    ],
    targets: [
        .target(name: "PogoReader", resources: [.copy("Resources/species.json")]),
        .executableTarget(name: "pogo-read", dependencies: ["PogoReader"]),
        .executableTarget(name: "pogo-drop", dependencies: ["PogoReader"]),
        .testTarget(name: "PogoReaderTests", dependencies: ["PogoReader"]),
        .target(name: "PogoBox", dependencies: ["PogoReader"], resources: [
            .copy("Resources/pogo-core.js"), .copy("Resources/gamemaster.json"),
            .copy("Resources/tiers.json"), .copy("Resources/pvp-rankings.json"),
        ]),
        .executableTarget(name: "pogo-rows", dependencies: ["PogoBox", "PogoReader"]),
        .testTarget(name: "PogoBoxTests", dependencies: ["PogoBox", "PogoReader"], resources: [.copy("Fixtures")]),
    ]
)
