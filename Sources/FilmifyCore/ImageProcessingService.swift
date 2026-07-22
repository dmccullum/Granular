import CoreGraphics
import Foundation

public actor ImageProcessingService {
    private let renderer: FilmRenderer
    private let exporter: ImageExporter

    public init() throws {
        renderer = try FilmRenderer()
        exporter = ImageExporter()
    }

    public func renderPreview(
        sourceURL: URL,
        recipe: FilmRecipe,
        maximumDimension: CGFloat = 1_600
    ) throws -> Data {
        let source = try renderer.loadImage(at: sourceURL)
        let rendered = try renderer.render(source, recipe: recipe)
        return try exporter.previewData(for: rendered, maximumDimension: maximumDimension)
    }

    public func process(
        sourceURL: URL,
        destinationFolder: URL,
        recipe: FilmRecipe,
        options: OutputOptions
    ) throws -> URL {
        let source = try renderer.loadImage(at: sourceURL)
        let rendered = try renderer.render(source, recipe: recipe)
        return try exporter.export(
            image: rendered,
            sourceURL: sourceURL,
            destinationFolder: destinationFolder,
            options: options
        )
    }

    public func process(
        sourceURL: URL,
        destinationURL: URL,
        recipe: FilmRecipe,
        options: OutputOptions
    ) throws -> URL {
        let source = try renderer.loadImage(at: sourceURL)
        let rendered = try renderer.render(source, recipe: recipe)
        return try exporter.export(
            image: rendered,
            sourceURL: sourceURL,
            destinationFolder: destinationURL.deletingLastPathComponent(),
            destinationURL: destinationURL,
            options: options
        )
    }
}
