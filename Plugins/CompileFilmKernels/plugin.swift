import Foundation
import PackagePlugin

/// Compiles GranularCore's FilmKernels.metal into a Core Image Metal library
/// for each platform GranularCore builds for. SwiftPM's own Metal step can't
/// link against Core Image's kernel library, which sampler kernels need.
/// The plugin isn't told which platform is being built, so it makes all three
/// and FilmRenderer loads the one for the platform it runs on.
@main
struct CompileFilmKernels: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        let source = target.directoryURL.appending(path: "FilmKernels.metal")
        let platforms = [
            ("macosx", "air64-apple-macos26.0"),
            ("iphoneos", "air64-apple-ios26.0"),
            ("iphonesimulator", "air64-apple-ios26.0-simulator")
        ]
        return platforms.map { sdk, triple in
            let library = context.pluginWorkDirectoryURL
                .appending(path: "FilmKernels-\(sdk).metallib")
            return .buildCommand(
                displayName: "Compiling Core Image kernels for \(sdk)",
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: [
                    "-sdk", sdk, "metal",
                    "-target", triple,
                    "-framework", "CoreImage",
                    "-o", library.path,
                    source.path
                ],
                inputFiles: [source],
                outputFiles: [library]
            )
        }
    }
}
