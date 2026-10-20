import CoreGraphics
import CoreImage
import Foundation
import ImageIO

public enum FilmRendererError: LocalizedError {
    case kernelLoadFailed(String)
    case filmStockUnavailable(String)
    case filmStockMalformed(String)
    case imageLoadFailed(URL)
    case renderFailed

    public var errorDescription: String? {
        switch self {
        case .kernelLoadFailed(let name):
            "Granular could not load its \(name) image kernel."
        case .filmStockUnavailable(let name):
            "Granular could not load the \(name) color stock."
        case .filmStockMalformed(let name):
            "The bundled \(name) color stock is not a valid 3D LUT."
        case .imageLoadFailed(let url):
            "Granular could not open \(url.lastPathComponent)."
        case .renderFailed:
            "Granular could not render the image."
        }
    }
}

public final class FilmRenderer: @unchecked Sendable {
    private let toneKernel: CIColorKernel
    private let stockInputKernel: CIColorKernel
    private let stockOutputKernel: CIColorKernel
    private let characterKernel: CIColorKernel
    private let lightShapingKernel: CIColorKernel
    private let lensRadialBlurKernel: CIKernel
    private let lensChromaticKernel: CIKernel
    private let diffusionKernel: CIColorKernel
    private let halationKernel: CIColorKernel
    private let landscapeGlowExtractionKernel: CIColorKernel
    private let landscapeGlowKernel: CIColorKernel
    private let grainKernel: CIColorKernel
    private let hdrToneKernel: CIColorKernel
    private let stockCubeLock = NSLock()
    private var stockCubes: [FilmStockID: FilmStockCube] = [:]

    public init() throws {
        let library = try Self.kernelLibrary()
        func colorKernel(_ name: String) throws -> CIColorKernel {
            do {
                return try CIColorKernel(functionName: name, fromMetalLibraryData: library)
            } catch {
                throw FilmRendererError.kernelLoadFailed(name)
            }
        }
        func kernel(_ name: String) throws -> CIKernel {
            do {
                return try CIKernel(functionName: name, fromMetalLibraryData: library)
            } catch {
                throw FilmRendererError.kernelLoadFailed(name)
            }
        }

        hdrToneKernel = try colorKernel("hdrTone")
        toneKernel = try colorKernel("filmTone")
        stockInputKernel = try colorKernel("prepareFilmStock")
        stockOutputKernel = try colorKernel("finishFilmStock")
        characterKernel = try colorKernel("filmCharacter")
        lightShapingKernel = try colorKernel("lightShape")
        lensRadialBlurKernel = try kernel("lensRadialBlur")
        lensChromaticKernel = try kernel("lensChromatic")
        diffusionKernel = try colorKernel("diffuse")
        halationKernel = try colorKernel("halate")
        landscapeGlowExtractionKernel = try colorKernel("landscapeGlowSource")
        landscapeGlowKernel = try colorKernel("landscapeGlow")
        grainKernel = try colorKernel("grain")
    }

    /// The kernels in FilmKernels.metal, which the CompileFilmKernels package
    /// plugin compiles into the bundle for each platform. The Mac app built by
    /// Scripts/build-app.sh carries a copy in its own resources.
    static func kernelLibrary() throws -> Data {
        #if os(macOS)
        let name = "FilmKernels-macosx"
        #elseif targetEnvironment(simulator)
        let name = "FilmKernels-iphonesimulator"
        #else
        let name = "FilmKernels-iphoneos"
        #endif
        guard let url = Bundle.main.url(forResource: name, withExtension: "metallib")
                ?? Bundle.module.url(forResource: name, withExtension: "metallib"),
              let data = try? Data(contentsOf: url) else {
            throw FilmRendererError.kernelLoadFailed("Metal library")
        }
        return data
    }

    /// Loads the photo's SDR rendition, or with `expandToHDR` its HDR one.
    public func loadImage(at url: URL, expandToHDR: Bool = false) throws -> CIImage {
        if expandToHDR { return try loadHDRImage(at: url) }
        let options: [CIImageOption: Any] = [
            .applyOrientationProperty: true,
            .toneMapHDRtoSDR: true
        ]
        guard let image = CIImage(contentsOf: url, options: options) else {
            throw FilmRendererError.imageLoadFailed(url)
        }
        return image
    }

    /// Core Image's own decoding sometimes hands back the tone-mapped SDR
    /// rendition of a PQ or HLG photo when asked for HDR, depending on what
    /// decoded the file before. ImageIO's explicit decode request doesn't.
    private func loadHDRImage(at url: URL) throws -> CIImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceDecodeRequest: kCGImageSourceDecodeToHDR,
                  kCGImageSourceShouldAllowFloat: true,
                  kCGImageSourceShouldCache: false
              ] as CFDictionary) else {
            throw FilmRendererError.imageLoadFailed(url)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = properties?[kCGImagePropertyOrientation] as? Int32 ?? 1
        // The image carries the headroom ImageIO decoded it with.
        return CIImage(cgImage: image).oriented(forExifOrientation: orientation)
    }

    /// Renders `source`, the photo's SDR rendition. Given `hdr`, the same photo's
    /// HDR rendition, it renders the HDR rendition of the edit instead.
    public func render(
        _ source: CIImage,
        hdr: CIImage? = nil,
        recipe: FilmRecipe,
        previewMaximumDimension: CGFloat? = nil,
        grainDimension: CGFloat? = nil,
        fullSize: CGSize? = nil
    ) throws -> CIImage {
        var extent = source.extent.integral
        guard !extent.isEmpty else { throw FilmRendererError.renderFailed }

        var image = try renderFilmTone(source, tone: recipe.tone, hdr: hdr)

        if recipe.lightShaping.isEnabled, recipe.lightShaping.amountStops != 0 {
            image = try applyLightShaping(image, settings: recipe.lightShaping, extent: extent)
        }
        if recipe.lensBlur.isEnabled, recipe.lensBlur.amount != 0 {
            image = try applyLensBlur(image, settings: recipe.lensBlur, extent: extent)
        }
        if recipe.diffusion.isEnabled, recipe.diffusion.amount != 0 {
            image = try applyDiffusion(image, settings: recipe.diffusion, extent: extent)
        }
        if recipe.halation.isEnabled, recipe.halation.amount != 0 {
            image = try applyHalation(image, settings: recipe.halation, extent: extent)
        }
        if recipe.landscapeGlow.isEnabled, recipe.landscapeGlow.amount != 0 {
            image = try applyLandscapeGlow(image, settings: recipe.landscapeGlow, extent: extent,
                                           preserveHDR: hdr != nil)
        }
        // Resolve optical effects at source resolution, then generate grain on
        // the final preview grid so downsampling does not dilute its contrast.
        if let maximumDimension = previewMaximumDimension, maximumDimension > 0 {
            let scale = min(1, maximumDimension / max(extent.width, extent.height))
            if scale < 1 {
                image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                extent = image.extent.integral
            }
        }
        if recipe.grain.isEnabled, recipe.grain.amount != 0 {
            if let fullSize, fullSize.width > 0, fullSize.height > 0,
               fullSize.width > extent.width || fullSize.height > extent.height {
                // What you see is what you get: grain is made on the photo's
                // own pixels, exactly as in the developed file, then shrunk
                // to the preview the way any viewer shrinks the file.
                let target = grainDimension ?? max(extent.width, extent.height)
                return try applyGrainOnFullGrid(
                    image,
                    settings: recipe.grain,
                    extent: extent,
                    fullSize: fullSize,
                    outputLongEdge: min(target, max(fullSize.width, fullSize.height))
                )
            }
            // A quick preview resolves everything else small, but grain is
            // generated on the grid it will be shown at; stretching it up from
            // the small grid would make it blocky.
            if let grainDimension, grainDimension > 0 {
                let scale = grainDimension / max(extent.width, extent.height)
                if scale > 1 {
                    image = image.samplingLinear()
                        .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    extent = image.extent.integral
                }
            }
            image = try applyGrain(image, settings: recipe.grain, extent: extent)
        }

        return image.cropped(to: extent)
    }

    /// Applies only the Film Tone stage: tone adjustments, then the color stock.
    /// Given `hdr`, the HDR rendition of `source`, it returns the stage's HDR rendition.
    public func renderFilmTone(
        _ source: CIImage, tone: FilmToneSettings, hdr: CIImage? = nil
    ) throws -> CIImage {
        let extent = source.extent.integral
        let appliesStock = tone.stock != .none && tone.stockAmount > 0
        guard tone.isEnabled, !extent.isEmpty, tone.hasToneAdjustments || appliesStock else {
            return hdr ?? source
        }

        var image = source
        if tone.hasToneAdjustments {
            image = try applyTone(image, settings: tone, extent: extent)
        }
        if appliesStock {
            image = try applyFilmStock(image, settings: tone, extent: extent)
        }
        guard let hdr else { return image }
        // The graded SDR image, brightened as much as the photo's HDR rendition is
        // brighter than its SDR one. Exposure acts on that extra light; stock
        // strength gently rolls it off.
        let stockAmount = appliesStock ? max(0, min(2, tone.stockAmount)) : 0
        guard let output = hdrToneKernel.apply(extent: extent, arguments: [
            source, hdr, image, Float(max(-2, min(2, tone.exposure))),
            Float(1 / (1 + 0.15 * stockAmount))
        ]) else { throw FilmRendererError.renderFailed }
        return output
    }

    private func applyTone(
        _ image: CIImage,
        settings: FilmToneSettings,
        extent: CGRect
    ) throws -> CIImage {
        let arguments: [Any] = [
            image,
            Float(max(-2, min(2, settings.exposure))),
            Float(max(-1, min(1, settings.contrast))),
            Float(max(-1, min(1, settings.saturation))),
            Float(max(-1, min(1, settings.vibrance))),
            Float(max(-1, min(1, settings.warmth)))
        ]
        guard let output = toneKernel.apply(extent: extent, arguments: arguments) else {
            throw FilmRendererError.renderFailed
        }
        return output
    }

    private func applyFilmStock(
        _ image: CIImage,
        settings: FilmToneSettings,
        extent: CGRect
    ) throws -> CIImage {
        let character = settings.stock.character
        // Cubes carry their own shoulder, so ease highlights in before the
        // lookup. A fitted character already describes its roll-off.
        let knee: Float = character == nil ? 0.82 : 1
        guard let input = stockInputKernel.apply(extent: extent, arguments: [image, knee]) else {
            throw FilmRendererError.renderFailed
        }

        let graded: CIImage
        if let character {
            guard let output = characterKernel.apply(
                extent: extent,
                arguments: [input] + Self.characterArguments(character)
            ) else {
                throw FilmRendererError.renderFailed
            }
            graded = output
        } else {
            let cube = try stockCube(for: settings.stock)
            guard let filter = CIFilter(name: "CIColorCube") else {
                throw FilmRendererError.renderFailed
            }
            filter.setValue(input, forKey: kCIInputImageKey)
            filter.setValue(cube.dimension, forKey: "inputCubeDimension")
            filter.setValue(cube.data, forKey: "inputCubeData")
            guard let output = filter.outputImage?.cropped(to: extent) else {
                throw FilmRendererError.renderFailed
            }
            graded = output
        }

        let amount = Float(max(0, min(FilmToneSettings.maximumStockAmount, settings.stockAmount)))
        let colorAmount = settings.stock.isMonochrome ? min(amount, 1) : amount
        guard let output = stockOutputKernel.apply(
            extent: extent,
            arguments: [
                image,
                graded,
                Float(character == nil ? settings.stock.toneRetention : 1),
                colorAmount,
                amount
            ]
        ) else {
            throw FilmRendererError.renderFailed
        }
        return output
    }

    static func characterArguments(_ character: FilmCharacter) -> [Any] {
        let curves = (0 ..< FilmCharacter.curveKnots.count).map { index in
            CIVector(
                x: FilmCharacter.curveKnots[index] + character.red[index],
                y: FilmCharacter.curveKnots[index] + character.green[index],
                z: FilmCharacter.curveKnots[index] + character.blue[index]
            )
        }
        let sectors = (0 ..< FilmCharacter.hueCenters.count).map { index in
            CIVector(
                x: character.lightness[index],
                y: character.chroma[index],
                z: character.hue[index]
            )
        }
        let saturation = CIVector(
            x: character.highlightDesaturation,
            y: character.shadowSaturation
        )
        return curves + sectors + [saturation]
    }

    private func stockCube(for stock: FilmStockID) throws -> FilmStockCube {
        stockCubeLock.lock()
        if let cached = stockCubes[stock] {
            stockCubeLock.unlock()
            return cached
        }
        stockCubeLock.unlock()

        let loaded = try FilmStockLUTLoader.load(stock)
        stockCubeLock.lock()
        stockCubes[stock] = loaded
        stockCubeLock.unlock()
        return loaded
    }

    private func applyLightShaping(
        _ image: CIImage,
        settings: LightShapingSettings,
        extent: CGRect
    ) throws -> CIImage {
        let arguments: [Any] = [
            image,
            CIVector(cgRect: extent),
            Float(Self.mappedSpotlightAmount(settings.amountStops)),
            Float(settings.focus),
            Float(settings.pop),
            Float(settings.bias),
            Float(settings.roundness),
            CIVector(x: settings.centerX, y: settings.centerY)
        ]
        guard let output = lightShapingKernel.apply(extent: extent, arguments: arguments) else {
            throw FilmRendererError.renderFailed
        }
        return output
    }

    private func applyLensBlur(
        _ image: CIImage,
        settings: LensBlurSettings,
        extent: CGRect
    ) throws -> CIImage {
        let amount = Self.mappedLensBlurAmount(settings.amount)
        let rgbSeparation = Self.mappedLensBlurRGBSeparation(settings.colorFringing)
        let shortEdge = min(extent.width, extent.height)
        // Kromo's polar-space Gaussian reaches roughly one percent of image width
        // plus height at strength 1. Granular keeps that calibration, but performs
        // the convolution directly on the GPU around the user-selected center.
        let maximumBlurOffset = (extent.width + extent.height) * 0.01 * amount
        let maximumChromaticOffset = shortEdge * 0.044 * rgbSeparation
        let roiExpansion = ceil(maximumBlurOffset + maximumChromaticOffset + 3)
        let clamped = image.clampedToExtent()
        let center = CIVector(x: settings.focusX, y: settings.focusY)
        let blurArguments: [Any] = [
            clamped,
            CIVector(cgRect: extent),
            Float(maximumBlurOffset),
            Float(settings.falloff),
            center
        ]
        guard let radialBlur = lensRadialBlurKernel.apply(
            extent: extent,
            roiCallback: { _, rect in rect.insetBy(dx: -roiExpansion, dy: -roiExpansion) },
            arguments: blurArguments
        ) else {
            throw FilmRendererError.renderFailed
        }

        let chromaticArguments: [Any] = [
            radialBlur,
            CIVector(cgRect: extent),
            Float(settings.falloff),
            Float(rgbSeparation),
            center
        ]
        guard let output = lensChromaticKernel.apply(
            extent: extent,
            roiCallback: { _, rect in rect.insetBy(dx: -maximumChromaticOffset - 2, dy: -maximumChromaticOffset - 2) },
            arguments: chromaticArguments
        ) else {
            throw FilmRendererError.renderFailed
        }
        return output.cropped(to: extent)
    }

    private func applyDiffusion(
        _ image: CIImage,
        settings: DiffusionSettings,
        extent: CGRect
    ) throws -> CIImage {
        var output = image
        for passAmount in Self.opticalPassAmounts(for: Self.mappedOpticalAmount(settings.amount)) {
            output = try applyDiffusionPass(
                output,
                settings: settings,
                amount: passAmount,
                extent: extent
            )
        }
        return output
    }

    private func applyDiffusionPass(
        _ image: CIImage,
        settings: DiffusionSettings,
        amount: Double,
        extent: CGRect
    ) throws -> CIImage {
        let shortEdge = min(extent.width, extent.height)
        let detailRadius = max(0.8, shortEdge * (0.00045 + 0.0018 * settings.bloom))
        let bloomRadius = max(3.0, shortEdge * (0.0030 + 0.0120 * settings.bloom))
        let wideRadius = bloomRadius * (2.5 + 1.5 * settings.bloom)
        let detail = gaussianBlur(image, radius: detailRadius, extent: extent)
        let bloom = gaussianBlur(image, radius: bloomRadius, extent: extent)
        let wide = gaussianBlur(image, radius: wideRadius, extent: extent)

        let arguments: [Any] = [
            image,
            detail,
            bloom,
            wide,
            Float(amount),
            Float(settings.bloom),
            Float(settings.veil),
            Float(settings.sourceBias),
            Float(settings.warmth)
        ]
        guard let output = diffusionKernel.apply(extent: extent, arguments: arguments) else {
            throw FilmRendererError.renderFailed
        }
        return output
    }

    private func applyHalation(
        _ image: CIImage,
        settings: HalationSettings,
        extent: CGRect
    ) throws -> CIImage {
        var output = image
        for passAmount in Self.opticalPassAmounts(for: Self.mappedOpticalAmount(settings.amount)) {
            output = try applyHalationPass(
                output,
                settings: settings,
                amount: passAmount,
                extent: extent
            )
        }
        return output
    }

    private func applyHalationPass(
        _ image: CIImage,
        settings: HalationSettings,
        amount: Double,
        extent: CGRect
    ) throws -> CIImage {
        let shortEdge = min(extent.width, extent.height)
        let spillRadius = max(0, min(1, settings.spillRadius))
        let tail = max(0, min(1, settings.tail))
        // Keep every scale relative to the image, including subpixel radii.
        // A pixel-sized floor makes quick previews halate more than exports.
        let baseRadius = shortEdge * (0.00045 + 0.0022 * spillRadius)
        let middleRadius = baseRadius * (2.0 + tail)
        let farRadius = baseRadius * (4.0 + tail * 5.0)

        let near = gaussianBlur(image, radius: baseRadius, extent: extent)
        let middle = gaussianBlur(image, radius: middleRadius, extent: extent)
        let far = gaussianBlur(image, radius: farRadius, extent: extent)
        // A compact green record gives an amber inner halo and a red outer
        // tail. These are RGB approximations, not measured emulsion spectra.
        let greenNear = gaussianBlur(image, radius: baseRadius * 0.55, extent: extent)

        let arguments: [Any] = [
            image,
            near,
            middle,
            far,
            greenNear,
            Float(amount),
            Float(tail),
            Float(max(0, min(1, settings.colorShift))),
            Float(max(0, min(1, settings.saturation))),
            Float(max(0, min(0.5, settings.greenLeakage)))
        ]
        guard let output = halationKernel.apply(extent: extent, arguments: arguments) else {
            throw FilmRendererError.renderFailed
        }
        return output
    }

    private func applyLandscapeGlow(
        _ image: CIImage,
        settings: LandscapeGlowSettings,
        extent: CGRect,
        preserveHDR: Bool
    ) throws -> CIImage {
        let shortEdge = min(extent.width, extent.height)
        let size = max(0, min(1, settings.glowSize))

        // All scales follow the image dimensions so the frequency separation and
        // highlight tail remain consistent across preview and export sizes.
        let middleRadius = max(4, shortEdge * (0.0045 + 0.0135 * size))
        let wideRadius = middleRadius * (2.25 + 1.75 * size)
        let overall = gaussianBlur(image, radius: middleRadius * 0.72, extent: extent)
        guard let highlightSource = landscapeGlowExtractionKernel.apply(
            extent: extent,
            arguments: [image]
        ) else {
            throw FilmRendererError.renderFailed
        }
        let middle = gaussianBlur(highlightSource, radius: middleRadius, extent: extent)
        let wide = gaussianBlur(highlightSource, radius: wideRadius, extent: extent)

        let arguments: [Any] = [
            image,
            overall,
            middle,
            wide,
            Float(max(0, min(LandscapeGlowSettings.maximumAmount, settings.amount))),
            Float(max(0, min(1, settings.shadowProtection))),
            Float(max(0, min(1, settings.detail))),
            Float(preserveHDR ? 1 : 0)
        ]
        guard let output = landscapeGlowKernel.apply(extent: extent, arguments: arguments) else {
            throw FilmRendererError.renderFailed
        }
        return output
    }

    static func opticalPassAmounts(for amount: Double) -> [Double] {
        let clampedAmount = max(0, min(2, amount))
        guard clampedAmount > 0 else { return [] }
        if clampedAmount <= 1 {
            return [clampedAmount]
        }
        return [1, clampedAmount - 1]
    }

    static func mappedOpticalAmount(_ amount: Double) -> Double {
        min(1, max(0, amount)) * 2
    }

    static func mappedSpotlightAmount(_ amount: Double) -> Double {
        min(1, max(0, amount)) * 4
    }

    static func mappedLensBlurAmount(_ amount: Double) -> Double {
        min(1, max(0, amount)) * 4
    }

    static func mappedLensBlurRGBSeparation(_ amount: Double) -> Double {
        min(1, max(0, amount)) * 2
    }

    private func applyGrain(
        _ image: CIImage,
        settings: GrainSettings,
        extent: CGRect
    ) throws -> CIImage {
        // Treat the long edge as the 36 mm film dimension in either orientation.
        let particlePixels = max(
            0.20,
            min(10, max(extent.width, extent.height) * settings.grainSize / 36_000)
        )
        // Film granularity follows the density of a small surrounding area, not the
        // brightness of each finished pixel in isolation. A softly resolved guide
        // keeps fine edges and specular detail from visibly switching grain regimes.
        let shortEdge = min(extent.width, extent.height)
        let densityGuideRadius = max(2, min(16, max(particlePixels * 2.25, shortEdge * 0.0015)))
        let densityGuide = gaussianBlur(image, radius: densityGuideRadius, extent: extent)

        let arguments: [Any] = [
            image,
            densityGuide,
            CIVector(cgRect: extent),
            Float(Self.mappedGrainAmount(settings.amount)),
            Float(particlePixels),
            Float(settings.acutance),
            Float(settings.sizeVariation),
            Float(settings.chroma),
            Float(settings.shadowResponse),
            Float(settings.highlightResponse),
            Self.mappedGrainSeed(settings.seed)
        ]
        guard let output = grainKernel.apply(extent: extent, arguments: arguments) else {
            throw FilmRendererError.renderFailed
        }
        return output
    }

    /// Grain for a preview that matches the developed file at any size: the
    /// small picture is stretched onto the photo's full grid, grained there
    /// with the same pixels and settings as an export, then averaged back down.
    private func applyGrainOnFullGrid(
        _ image: CIImage,
        settings: GrainSettings,
        extent: CGRect,
        fullSize: CGSize,
        outputLongEdge: CGFloat
    ) throws -> CIImage {
        let fullExtent = CGRect(origin: .zero, size: CGSize(
            width: fullSize.width.rounded(), height: fullSize.height.rounded()
        ))
        let scaleX = fullExtent.width / extent.width
        let scaleY = fullExtent.height / extent.height
        let upscale = CGAffineTransform(scaleX: scaleX, y: scaleY)

        let particlePixels = max(
            0.20,
            min(10, max(fullExtent.width, fullExtent.height) * settings.grainSize / 36_000)
        )
        let shortEdge = min(fullExtent.width, fullExtent.height)
        let fullRadius = max(2, min(16, max(particlePixels * 2.25, shortEdge * 0.0015)))
        // The density guide is soft, so it's blurred on the small picture.
        let guide = gaussianBlur(image, radius: fullRadius / max(scaleX, scaleY), extent: extent)

        func onFullGrid(_ small: CIImage) -> CIImage {
            small.clampedToExtent().samplingLinear()
                .transformed(by: upscale)
                .cropped(to: fullExtent)
        }

        let arguments: [Any] = [
            onFullGrid(image),
            onFullGrid(guide),
            CIVector(cgRect: fullExtent),
            Float(Self.mappedGrainAmount(settings.amount)),
            Float(particlePixels),
            Float(settings.acutance),
            Float(settings.sizeVariation),
            Float(settings.chroma),
            Float(settings.shadowResponse),
            Float(settings.highlightResponse),
            Self.mappedGrainSeed(settings.seed)
        ]
        guard let grained = grainKernel.apply(extent: fullExtent, arguments: arguments) else {
            throw FilmRendererError.renderFailed
        }
        return Self.areaScaled(
            grained,
            from: fullExtent,
            toLongEdge: outputLongEdge
        )
    }

    /// Shrinks by halving, which averages exactly, then a last partial step.
    /// Dropping straight to a small size would alias fine grain.
    static func areaScaled(_ image: CIImage, from extent: CGRect, toLongEdge longEdge: CGFloat) -> CIImage {
        let factor = longEdge / max(extent.width, extent.height)
        guard factor < 1 else { return image }
        let width = max(1, (extent.width * factor).rounded())
        let height = max(1, (extent.height * factor).rounded())
        var result = image
        var current = extent.size
        while current.width / 2 >= width, current.height / 2 >= height {
            result = result.samplingLinear().transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
            current = CGSize(width: current.width / 2, height: current.height / 2)
        }
        if current.width != width || current.height != height {
            result = result.samplingLinear().transformed(by: CGAffineTransform(
                scaleX: width / current.width, y: height / current.height
            ))
        }
        return result.cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    static func mappedGrainAmount(_ amount: Double) -> Double {
        min(1, max(0, amount)) * 4.224
    }

    static func mappedGrainSeed(_ seed: UInt32) -> Float {
        // Core Image receives scalar kernel arguments as 32-bit floats.
        // Keeping the phase bounded prevents large UInt32 values from collapsing
        // nearby hash inputs into the same representable number on the GPU.
        Float(seed % 1_000_003)
    }

    private func gaussianBlur(_ image: CIImage, radius: CGFloat, extent: CGRect) -> CIImage {
        image
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: extent)
    }

}
