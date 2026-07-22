// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Filmify",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "FilmifyCore", targets: ["FilmifyCore"]),
        .executable(name: "Filmify", targets: ["Filmify"])
    ],
    targets: [
        .target(
            name: "FilmifyCore",
            path: "Sources/FilmifyCore"
        ),
        .executableTarget(
            name: "Filmify",
            dependencies: ["FilmifyCore"],
            path: "Sources/Filmify"
        ),
        .testTarget(
            name: "FilmifyCoreTests",
            dependencies: ["FilmifyCore"],
            path: "Tests/FilmifyCoreTests"
        )
    ]
)
