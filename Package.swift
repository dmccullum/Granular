// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Granular",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(name: "GranularCore", targets: ["GranularCore"]),
        .executable(name: "Granular", targets: ["Granular"])
    ],
    targets: [
        .target(
            name: "GranularCore",
            path: "Sources/GranularCore",
            // CompileFilmKernels builds this into the bundle's metallibs.
            exclude: ["FilmKernels.metal"],
            resources: [
                .copy("FilmStocks")
            ],
            plugins: ["CompileFilmKernels"]
        ),
        .plugin(
            name: "CompileFilmKernels",
            capability: .buildTool(),
            path: "Plugins/CompileFilmKernels"
        ),
        .executableTarget(
            name: "Granular",
            dependencies: ["GranularCore"],
            path: "Sources/Granular",
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        ),
        .testTarget(
            name: "GranularCoreTests",
            dependencies: ["GranularCore"],
            path: "Tests/GranularCoreTests",
            exclude: ["RenderReferences"]
        )
    ]
)
