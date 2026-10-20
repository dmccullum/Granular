import CoreImage
import Foundation
import Testing
@testable import GranularCore

// Renders a fixed synthetic photo through every built-in recipe and through
// recipes that turn on each stage and kernel, then compares the result with
// float RGBA references in RenderReferences/. Set GRANULAR_RECORD_REFERENCES=1
// to rewrite the references from the current renderer.

private let referenceSpace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
private let referenceContext = CIContext(options: [
    .workingColorSpace: referenceSpace,
    .workingFormat: CIFormat.RGBAh,
    .cacheIntermediates: false
])
private let referenceWidth = 64
private let referenceHeight = 48

/// Gradients, saturated patches, a few HDR highlights above 1 and a
/// half-transparent strip, premultiplied, in extended linear Rec. 2020.
private func referencePhoto(hdr: Bool) -> CIImage {
    var pixels = [Float]()
    pixels.reserveCapacity(referenceWidth * referenceHeight * 4)
    for y in 0 ..< referenceHeight {
        for x in 0 ..< referenceWidth {
            let u = Float(x) / Float(referenceWidth - 1)
            let v = Float(y) / Float(referenceHeight - 1)
            var rgb: [Float] = [u * u, v, (1 - u) * (0.2 + 0.6 * v)]
            if (24 ..< 34).contains(x), (16 ..< 26).contains(y) { rgb = [0.85, 0.25, 0.05] }
            if (40 ..< 50).contains(x), (8 ..< 18).contains(y) { rgb = [0.05, 0.35, 0.80] }
            if (8 ..< 14).contains(x), (30 ..< 36).contains(y) { rgb = [0.02, 0.02, 0.02] }
            if (50 ..< 56).contains(x), (32 ..< 38).contains(y) {
                rgb = hdr ? [3.6, 3.1, 2.2] : [1, 0.86, 0.61]
            }
            let alpha: Float = y < 4 ? 0.5 : 1
            pixels += rgb.map { $0 * alpha } + [alpha]
        }
    }
    return pixels.withUnsafeBytes {
        CIImage(bitmapData: Data($0), bytesPerRow: referenceWidth * 16,
                size: CGSize(width: referenceWidth, height: referenceHeight),
                format: .RGBAf, colorSpace: referenceSpace)
    }
}

private struct ReferenceCase: Sendable, CustomStringConvertible {
    var name: String
    var recipe: FilmRecipe
    var hdr = false
    var previewMaximumDimension: CGFloat?
    var grainDimension: CGFloat?
    var fullSize: CGSize?

    var description: String { name }
}

private func recipe(
    _ id: String,
    tone: FilmToneSettings = .init(isEnabled: false),
    lightShaping: LightShapingSettings = .init(isEnabled: false),
    lensBlur: LensBlurSettings = .init(isEnabled: false),
    diffusion: DiffusionSettings = .init(isEnabled: false),
    halation: HalationSettings = .init(isEnabled: false),
    landscapeGlow: LandscapeGlowSettings = .init(isEnabled: false),
    grain: GrainSettings = .init(isEnabled: false)
) -> FilmRecipe {
    FilmRecipe(id: id, name: id, tone: tone, lightShaping: lightShaping, lensBlur: lensBlur,
               diffusion: diffusion, halation: halation, landscapeGlow: landscapeGlow, grain: grain)
}

private let toneAdjustments = FilmToneSettings(
    exposure: 0.6, contrast: 0.4, saturation: 0.3, vibrance: 0.5, warmth: 0.4
)

private let referenceCases: [ReferenceCase] = FilmRecipe.builtIns.map {
    ReferenceCase(name: "builtin-\($0.id)", recipe: $0)
} + [
    ReferenceCase(name: "tone", recipe: recipe("tone", tone: toneAdjustments)),
    ReferenceCase(name: "tone-negative", recipe: recipe("tone-negative", tone: .init(
        exposure: -0.8, contrast: -0.5, saturation: -0.4, vibrance: -0.6, warmth: -0.5
    ))),
    ReferenceCase(name: "stock-character", recipe: recipe("stock-character", tone: .init(
        stock: .portra400, stockAmount: 1.4, exposure: 0.2, contrast: 0.1
    ))),
    ReferenceCase(name: "stock-cube", recipe: recipe("stock-cube", tone: .init(stock: .vision250D, stockAmount: 0.8))),
    ReferenceCase(name: "stock-mono", recipe: recipe("stock-mono", tone: .init(stock: .triX400, stockAmount: 1.6))),
    ReferenceCase(name: "light-shaping", recipe: recipe("light-shaping", lightShaping: .init(
        amountStops: 0.8, focus: 0.3, pop: 0.9, bias: 0.8, roundness: 0.2, centerX: 0.4, centerY: 0.6
    ))),
    ReferenceCase(name: "lens-blur", recipe: recipe("lens-blur", lensBlur: .init(
        isEnabled: true, amount: 0.8, falloff: 0.3, colorFringing: 0.9, focusX: 0.45, focusY: 0.55
    ))),
    ReferenceCase(name: "diffusion", recipe: recipe("diffusion", diffusion: .init(
        amount: 0.9, bloom: 0.7, veil: 0.4, sourceBias: 0.6, warmth: 0.5
    ))),
    ReferenceCase(name: "halation", recipe: recipe("halation", halation: .init(
        amount: 0.8, spillRadius: 0.7, tail: 0.6, colorShift: 0.3, saturation: 0.8, greenLeakage: 0.3
    ))),
    ReferenceCase(name: "landscape-glow", recipe: recipe("landscape-glow", landscapeGlow: .init(
        isEnabled: true, amount: 0.9, glowSize: 0.7, shadowProtection: 0.4, detail: 0.3
    ))),
    ReferenceCase(name: "landscape-glow-hdr", recipe: recipe("landscape-glow-hdr", landscapeGlow: .init(
        isEnabled: true, amount: 0.9, glowSize: 0.7, shadowProtection: 0.4, detail: 0.3
    )), hdr: true),
    ReferenceCase(name: "grain", recipe: recipe("grain", grain: .init(
        amount: 0.8, grainSize: 30, acutance: 0.3, sizeVariation: 0.7, chroma: 0.9, seed: 4_242_424_242
    ))),
    ReferenceCase(name: "grain-preview", recipe: recipe("grain-preview", grain: .init(amount: 0.6)),
                  previewMaximumDimension: 32, grainDimension: 64),
    ReferenceCase(name: "grain-full-grid", recipe: recipe("grain-full-grid", grain: .init(amount: 0.6)),
                  previewMaximumDimension: 32, grainDimension: 32,
                  fullSize: CGSize(width: 128, height: 96)),
    ReferenceCase(name: "hdr-tone", recipe: recipe("hdr-tone", tone: .init(
        stock: .ektar100, stockAmount: 1.2, exposure: 0.5, contrast: 0.2
    )), hdr: true),
    ReferenceCase(name: "everything", recipe: recipe(
        "everything",
        tone: .init(stock: .gold200, exposure: 0.3, contrast: 0.2, saturation: 0.1, vibrance: 0.2, warmth: 0.2),
        lightShaping: .init(amountStops: 0.4),
        lensBlur: .init(isEnabled: true, amount: 0.5, colorFringing: 0.5),
        diffusion: .init(amount: 0.4),
        halation: .init(amount: 0.5),
        landscapeGlow: .init(isEnabled: true, amount: 0.5),
        grain: .init(amount: 0.4)
    ), hdr: true)
]

private func referencePixels(_ image: CIImage) -> [Float] {
    let extent = image.extent.integral
    var pixels = [Float](repeating: 0, count: Int(extent.width * extent.height) * 4)
    referenceContext.render(image, toBitmap: &pixels, rowBytes: Int(extent.width) * 16,
                            bounds: extent, format: .RGBAf, colorSpace: referenceSpace)
    return pixels
}

private func referenceURL(_ name: String, filePath: String = #filePath) -> URL {
    URL(fileURLWithPath: filePath).deletingLastPathComponent()
        .appendingPathComponent("RenderReferences/\(name).rgbaf")
}

@Test(arguments: referenceCases)
private func renderMatchesReference(_ testCase: ReferenceCase) throws {
    let renderer = try FilmRenderer()
    let sdr = referencePhoto(hdr: false)
    let output = try renderer.render(
        sdr,
        hdr: testCase.hdr ? referencePhoto(hdr: true) : nil,
        recipe: testCase.recipe,
        previewMaximumDimension: testCase.previewMaximumDimension,
        grainDimension: testCase.grainDimension,
        fullSize: testCase.fullSize
    )
    let pixels = referencePixels(output)
    let url = referenceURL(testCase.name)

    if ProcessInfo.processInfo.environment["GRANULAR_RECORD_REFERENCES"] == "1" {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try pixels.withUnsafeBytes { try Data($0).write(to: url) }
        return
    }

    let data = try Data(contentsOf: url)
    let reference = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    try #require(reference.count == pixels.count, "\(testCase.name): size changed")
    var maximumDifference: Float = 0
    var totalDifference: Float = 0
    for (rendered, expected) in zip(pixels, reference) {
        let difference = abs(rendered - expected)
        maximumDifference = max(maximumDifference, difference)
        totalDifference += difference
    }
    let meanDifference = totalDifference / Float(pixels.count)
    // The working format is half float, which resolves about 1/1024 near 1.
    // The references come from a Mac. The iOS Simulator's renders drift from
    // them by up to about 0.0065 in single pixels, even for the Raw recipe,
    // which runs no kernels, while the mean stays as tight as on the Mac.
    #if targetEnvironment(simulator)
    let maximumTolerance: Float = 0.01
    #else
    let maximumTolerance: Float = 0.004
    #endif
    #expect(maximumDifference <= maximumTolerance, "\(testCase.name): max \(maximumDifference)")
    #expect(meanDifference <= 0.0005, "\(testCase.name): mean \(meanDifference)")
}
