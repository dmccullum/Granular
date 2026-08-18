import Foundation

public enum OutputFormat: String, CaseIterable, Codable, Sendable {
    case sameAsSource
    case jpeg
    case heic
    case png
    case tiff

    public var displayName: String {
        switch self {
        case .sameAsSource: "Same as Source"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .png: "PNG"
        case .tiff: "TIFF"
        }
    }
}

public struct OutputOptions: Codable, Hashable, Sendable {
    public var format: OutputFormat
    public var compressionQuality: Double
    public var stripLocationMetadata: Bool

    public init(
        format: OutputFormat = .sameAsSource,
        compressionQuality: Double = 0.94,
        stripLocationMetadata: Bool = true
    ) {
        self.format = format
        self.compressionQuality = compressionQuality
        self.stripLocationMetadata = stripLocationMetadata
    }
}
