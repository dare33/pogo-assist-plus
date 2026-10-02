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
    ],
    targets: [
        .target(name: "PogoReader", resources: [.copy("Resources/species.json")]),
        .executableTarget(name: "pogo-read", dependencies: ["PogoReader"]),
        .executableTarget(name: "pogo-drop", dependencies: ["PogoReader"]),
        .testTarget(name: "PogoReaderTests", dependencies: ["PogoReader"]),
    ]
)
