import CoreGraphics
import CoreImage
import Foundation

public enum FilmRendererError: LocalizedError {
    case kernelCompilationFailed(String)
    case filmStockUnavailable(String)
    case filmStockMalformed(String)
    case imageLoadFailed(URL)
    case renderFailed

    public var errorDescription: String? {
        switch self {
        case .kernelCompilationFailed(let name):
            "Granular could not compile its \(name) image kernel."
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
    private let lightShapingKernel: CIColorKernel
    private let lensRadialBlurKernel: CIKernel
    private let lensChromaticKernel: CIKernel
    private let diffusionKernel: CIColorKernel
    private let halationKernel: CIColorKernel
    private let grainKernel: CIColorKernel
    private let stockCubeLock = NSLock()
    private var stockCubes: [FilmStockID: FilmStockCube] = [:]

    public init() throws {
        guard let toneKernel = CIColorKernel(source: Self.toneSource) else {
            throw FilmRendererError.kernelCompilationFailed("film-tone")
        }
        guard let stockInputKernel = CIColorKernel(source: Self.stockInputSource) else {
            throw FilmRendererError.kernelCompilationFailed("color-stock input")
        }
        guard let stockOutputKernel = CIColorKernel(source: Self.stockOutputSource) else {
            throw FilmRendererError.kernelCompilationFailed("color-stock output")
        }
        guard let lightShapingKernel = CIColorKernel(source: Self.lightShapingSource) else {
            throw FilmRendererError.kernelCompilationFailed("light-shaping")
        }
        guard let lensRadialBlurKernel = CIKernel(source: Self.lensRadialBlurSource) else {
            throw FilmRendererError.kernelCompilationFailed("lens-blur")
        }
        guard let lensChromaticKernel = CIKernel(source: Self.lensChromaticSource) else {
            throw FilmRendererError.kernelCompilationFailed("chromatic-aberration")
        }
        guard let diffusionKernel = CIColorKernel(source: Self.diffusionSource) else {
            throw FilmRendererError.kernelCompilationFailed("diffusion")
        }
        guard let halationKernel = CIColorKernel(source: Self.halationSource) else {
            throw FilmRendererError.kernelCompilationFailed("halation")
        }
        guard let grainKernel = CIColorKernel(source: Self.grainSource) else {
            throw FilmRendererError.kernelCompilationFailed("grain")
        }

        self.toneKernel = toneKernel
        self.stockInputKernel = stockInputKernel
        self.stockOutputKernel = stockOutputKernel
        self.lightShapingKernel = lightShapingKernel
        self.lensRadialBlurKernel = lensRadialBlurKernel
        self.lensChromaticKernel = lensChromaticKernel
        self.diffusionKernel = diffusionKernel
        self.halationKernel = halationKernel
        self.grainKernel = grainKernel
    }

    public func loadImage(at url: URL) throws -> CIImage {
        let options: [CIImageOption: Any] = [
            .applyOrientationProperty: true
        ]
        guard let image = CIImage(contentsOf: url, options: options) else {
            throw FilmRendererError.imageLoadFailed(url)
        }
        return image
    }

    public func render(_ source: CIImage, recipe: FilmRecipe) throws -> CIImage {
        let recipe = recipe.effective
        let extent = source.extent.integral
        guard !extent.isEmpty else { throw FilmRendererError.renderFailed }

        var image = source

        if recipe.tone.isEnabled, recipe.tone.hasToneAdjustments {
            image = try applyTone(image, settings: recipe.tone, extent: extent)
        }
        if recipe.tone.isEnabled,
           recipe.tone.stock != .none,
           recipe.tone.stockAmount > 0 {
            image = try applyFilmStock(image, settings: recipe.tone, extent: extent)
        }
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
        if recipe.grain.isEnabled, recipe.grain.amount != 0 {
            image = try applyGrain(image, settings: recipe.grain, extent: extent)
        }

        return image.cropped(to: extent)
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
        let cube = try stockCube(for: settings.stock)
        guard let input = stockInputKernel.apply(extent: extent, arguments: [image]) else {
            throw FilmRendererError.renderFailed
        }

        guard let filter = CIFilter(name: "CIColorCube") else {
            throw FilmRendererError.renderFailed
        }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(cube.dimension, forKey: "inputCubeDimension")
        filter.setValue(cube.data, forKey: "inputCubeData")
        guard let graded = filter.outputImage?.cropped(to: extent) else {
            throw FilmRendererError.renderFailed
        }

        let amount = Float(max(0, min(FilmToneSettings.maximumStockAmount, settings.stockAmount)))
        guard let output = stockOutputKernel.apply(
            extent: extent,
            arguments: [image, graded, amount]
        ) else {
            throw FilmRendererError.renderFailed
        }
        return output
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
        let baseRadius = max(0.75, shortEdge * (0.00045 + 0.0022 * settings.spillRadius))
        let middleRadius = baseRadius * (2.0 + settings.tail)
        let farRadius = baseRadius * (4.0 + settings.tail * 5.0)

        let near = gaussianBlur(image, radius: baseRadius, extent: extent)
        let middle = gaussianBlur(image, radius: middleRadius, extent: extent)
        let far = gaussianBlur(image, radius: farRadius, extent: extent)

        let arguments: [Any] = [
            image,
            near,
            middle,
            far,
            Float(amount),
            Float(settings.tail),
            Float(settings.colorShift),
            Float(settings.saturation),
            Float(settings.greenLeakage)
        ]
        guard let output = halationKernel.apply(extent: extent, arguments: arguments) else {
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
        let particlePixels = max(
            0.65,
            min(10, extent.width * settings.particleSizeMicrons / (settings.virtualGateWidthMillimeters * 1_000))
        )

        let arguments: [Any] = [
            image,
            CIVector(cgRect: extent),
            Float(Self.mappedGrainAmount(settings.amount)),
            Float(particlePixels),
            Float(settings.acutance),
            Float(settings.sizeVariation),
            Float(settings.chroma),
            Float(settings.shadowResponse),
            Float(settings.highlightResponse),
            Float(settings.seed)
        ]
        guard let output = grainKernel.apply(extent: extent, arguments: arguments) else {
            throw FilmRendererError.renderFailed
        }
        return output
    }

    static func mappedGrainAmount(_ amount: Double) -> Double {
        min(1, max(0, amount)) * 6
    }

    private func gaussianBlur(_ image: CIImage, radius: CGFloat, extent: CGRect) -> CIImage {
        image
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: extent)
    }

}

private extension FilmRenderer {
    static let stockInputSource = #"""
    float srgbEncode(float value) {
        float linear = max(value, 0.0);
        return linear <= 0.0031308
            ? linear * 12.92
            : 1.055 * pow(linear, 1.0 / 2.4) - 0.055;
    }

    kernel vec4 prepareFilmStock(__sample pixel) {
        vec3 rec2020 = max(pixel.rgb, vec3(0.0));
        vec3 rgb = vec3(
            1.6604910 * rec2020.r - 0.5876411 * rec2020.g - 0.0728499 * rec2020.b,
            -0.1245505 * rec2020.r + 1.1328999 * rec2020.g - 0.0083494 * rec2020.b,
            -0.0181508 * rec2020.r - 0.1005789 * rec2020.g + 1.1187297 * rec2020.b
        );

        // The spectral cubes describe display-referred sRGB. Compress wide-gamut
        // excursions toward neutral before lookup instead of clipping individual
        // channels, which would create hard, synthetic hue changes.
        float y = max(dot(rgb, vec3(0.2126, 0.7152, 0.0722)), 0.0);
        if (y > 0.82) {
            float rolledY = 0.82 + 0.18 * (1.0 - exp(-(y - 0.82) / 0.18));
            rgb *= rolledY / max(y, 0.000001);
            y = rolledY;
        }
        float minimum = min(rgb.r, min(rgb.g, rgb.b));
        float maximum = max(rgb.r, max(rgb.g, rgb.b));
        float lowScale = minimum < 0.0 ? y / max(y - minimum, 0.000001) : 1.0;
        float highScale = maximum > 1.0
            ? (1.0 - y) / max(maximum - y, 0.000001)
            : 1.0;
        rgb = mix(vec3(y), rgb, clamp(min(lowScale, highScale), 0.0, 1.0));

        return vec4(
            srgbEncode(rgb.r),
            srgbEncode(rgb.g),
            srgbEncode(rgb.b),
            pixel.a
        );
    }
    """#

    static let stockOutputSource = #"""
    float srgbDecode(float value) {
        float encoded = max(value, 0.0);
        return encoded <= 0.04045
            ? encoded / 12.92
            : pow((encoded + 0.055) / 1.055, 2.4);
    }

    kernel vec4 finishFilmStock(__sample source, __sample graded, float amount) {
        vec3 srgb = vec3(
            srgbDecode(graded.r),
            srgbDecode(graded.g),
            srgbDecode(graded.b)
        );
        vec3 rec2020 = vec3(
            0.6274039 * srgb.r + 0.3292830 * srgb.g + 0.0433131 * srgb.b,
            0.0690973 * srgb.r + 0.9195404 * srgb.g + 0.0113623 * srgb.b,
            0.0163914 * srgb.r + 0.0880133 * srgb.g + 0.8955953 * srgb.b
        );
        const vec3 luma = vec3(0.2627002, 0.6779981, 0.0593017);
        vec3 positiveGrade = max(rec2020, vec3(0.0));
        float sourceY = max(dot(source.rgb, luma), 0.0);
        float gradedY = max(dot(positiveGrade, luma), 0.000001);

        // These spectral cubes include a complete negative-to-print density
        // response, but Color Stock is intended to supply color character rather
        // than replace Granular's tone controls. Keep only a restrained fraction
        // of the cube's luminance move while preserving its chromatic signature.
        float restrainedY = mix(sourceY, gradedY, 0.20);
        vec3 colorGrade = positiveGrade * (restrainedY / gradedY);
        vec3 rgb = mix(
            source.rgb,
            colorGrade,
            clamp(amount, 0.0, 2.0)
        );
        return vec4(rgb, source.a);
    }
    """#

    static let toneSource = #"""
    float filmShoulder(float value) {
        float a = 0.15;
        float b = 0.50;
        float c = 0.10;
        float d = 0.20;
        float e = 0.02;
        float f = 0.30;
        return ((value * (a * value + c * b) + d * e)
            / (value * (a * value + b) + d * f)) - e / f;
    }

    float outputShoulder(float value, float knee) {
        float width = max(1.0 - knee, 0.0001);
        float over = max(value - knee, 0.0);
        float rolled = knee + width * (1.0 - exp(-over / width));
        return value > knee ? rolled : value;
    }

    vec3 rec2020ToOklab(vec3 rgb) {
        float x = 0.6369580 * rgb.r + 0.1446169 * rgb.g + 0.1688809 * rgb.b;
        float y = 0.2627002 * rgb.r + 0.6779981 * rgb.g + 0.0593017 * rgb.b;
        float z =                         0.0280727 * rgb.g + 1.0609851 * rgb.b;

        float l = 0.8190224 * x + 0.3619063 * y - 0.1288738 * z;
        float m = 0.0329837 * x + 0.9292868 * y + 0.0361447 * z;
        float s = 0.0481772 * x + 0.2642395 * y + 0.6335478 * z;
        float lRoot = pow(max(l, 0.0), 0.3333333);
        float mRoot = pow(max(m, 0.0), 0.3333333);
        float sRoot = pow(max(s, 0.0), 0.3333333);

        return vec3(
            0.2104543 * lRoot + 0.7936178 * mRoot - 0.0040720 * sRoot,
            1.9780000 * lRoot - 2.4285922 * mRoot + 0.4505937 * sRoot,
            0.0259040 * lRoot + 0.7827718 * mRoot - 0.8086758 * sRoot
        );
    }

    vec3 oklabToRec2020(vec3 lab) {
        float lRoot = lab.x + 0.3963378 * lab.y + 0.2158038 * lab.z;
        float mRoot = lab.x - 0.1055613 * lab.y - 0.0638542 * lab.z;
        float sRoot = lab.x - 0.0894842 * lab.y - 1.2914855 * lab.z;
        float l = lRoot * lRoot * lRoot;
        float m = mRoot * mRoot * mRoot;
        float s = sRoot * sRoot * sRoot;

        float x = 1.2268799 * l - 0.5578150 * m + 0.2813911 * s;
        float y = -0.0405757 * l + 1.1122868 * m - 0.0717111 * s;
        float z = -0.0763729 * l - 0.4214933 * m + 1.5869240 * s;

        return vec3(
            1.7166512 * x - 0.3556708 * y - 0.2533663 * z,
            -0.6666844 * x + 1.6164812 * y + 0.0157685 * z,
            0.0176399 * x - 0.0427706 * y + 0.9421031 * z
        );
    }

    kernel vec4 filmTone(__sample pixel, float exposure, float contrast, float saturation, float vibrance, float warmth) {
        const vec3 luma = vec3(0.2627002, 0.6779981, 0.0593017);
        vec3 source = max(pixel.rgb, vec3(0.0));
        float sourceY = max(dot(source, luma), 0.000001);

        // Exposure uses a bounded photographic density curve. The family composes
        // cleanly around fixed black and white points: +1 EV gives deep tones about
        // three times their input density, then progressively reduces that gain
        // through the mids and highlights. This matches the response of modern raw
        // editors much more closely than multiplying RGB and applying a late knee.
        float densityGain = pow(3.05, exposure);
        float exposedY = sourceY * densityGain
            / max(1.0 + (densityGain - 1.0) * sourceY, 0.000001);
        float adjustedStops = log2(max(exposedY, 0.000001) / 0.18);

        // Contrast is an S-curve around 18% gray. A bounded soft-sign curve limits
        // toward both endpoints instead of driving highlights and shadows into clips.
        float contrastPosition = adjustedStops * 0.62;
        float contrastCurve = contrastPosition / (1.0 + abs(contrastPosition));
        adjustedStops += contrast * 1.15 * contrastCurve;
        float adjustedY = 0.18 * exp2(adjustedStops);

        // Contrast adds a normalized film response without making exposure itself
        // collide with a second shoulder.
        float filmY = filmShoulder(adjustedY)
            * (0.18 / max(filmShoulder(0.18), 0.000001));
        float rolloff = clamp(abs(contrast) * 0.23, 0.0, 0.36);
        adjustedY = mix(adjustedY, filmY, rolloff);

        // Retain a hair of printable separation below display white at positive
        // exposure instead of letting the last highlight values quantize together.
        adjustedY -= 0.0035
            * clamp(max(exposure, 0.0), 0.0, 1.0)
            * smoothstep(0.85, 1.0, adjustedY);

        // SDR source values remain below white by construction. Compress only
        // genuinely extended input rather than flattening ordinary upper mids.
        adjustedY = adjustedY > 1.0
            ? 0.995
            : adjustedY;
        vec3 rgb = source * (adjustedY / sourceY);

        // Saturation and Vibrance live in OKLab so equal slider moves feel much more
        // even across hues. Vibrance favors restrained colors, protects skin-like
        // orange hues, and eases off in the brightest part of the image.
        vec3 lab = rec2020ToOklab(max(rgb, vec3(0.0)));
        float chroma = length(lab.yz);

        // Raising exposure on photographic material does not preserve electronic
        // RGB saturation all the way to white. Compress dye separation gradually
        // through the raised mids, then more firmly in the shoulder. At +1 EV this
        // is calibrated against a Lightroom reference; the user's Saturation and
        // Vibrance controls remain available afterward for intentional color moves.
        float exposureColorWeight = clamp(max(exposure, 0.0), 0.0, 1.0);
        float raisedMidCompression = smoothstep(0.10, 0.75, adjustedY);
        float shoulderCompression = smoothstep(0.75, 0.98, adjustedY);
        float exposureChromaScale = 1.0 - exposureColorWeight
            * (0.45 * raisedMidCompression + 0.18 * shoulderCompression);
        lab.yz *= max(0.30, exposureChromaScale);

        float saturationScale = saturation >= 0.0
            ? 1.0 + saturation * 1.35
            : 1.0 + saturation;
        lab.yz *= saturationScale;

        float directionLength = max(length(lab.yz), 0.000001);
        vec2 hueDirection = lab.yz / directionLength;
        float skinDirection = clamp(dot(hueDirection, normalize(vec2(0.78, 0.62))), 0.0, 1.0);
        float skinProtection = smoothstep(0.70, 0.94, skinDirection)
            * smoothstep(0.008, 0.055, chroma)
            * (1.0 - smoothstep(0.25, 0.38, chroma));
        float chromaProtection = smoothstep(0.035, 0.28, chroma);
        float highlightProtection = 1.0 - 0.35 * smoothstep(0.72, 1.08, lab.x);
        float vibranceScale = vibrance >= 0.0
            ? 1.0 + vibrance * 1.25 * (1.0 - chromaProtection)
                * (1.0 - 0.92 * skinProtection) * highlightProtection
            : exp2(vibrance * 1.05);
        lab.yz *= max(0.0, vibranceScale);

        // Warmth leans toward a Kodak Gold-like palette: yellow-gold density through
        // the mids and highlights, with cleaner, less-red shadow color separation.
        float highlightTone = smoothstep(0.42, 0.96, lab.x);
        float shadowTone = 1.0 - smoothstep(0.08, 0.46, lab.x);
        float midtoneTone = smoothstep(0.16, 0.52, lab.x)
            * (1.0 - smoothstep(0.68, 1.02, lab.x));
        lab.y += warmth * (0.007 + 0.006 * midtoneTone
            + 0.004 * highlightTone - 0.006 * shadowTone);
        lab.z += warmth * (0.027 + 0.021 * midtoneTone
            + 0.022 * highlightTone - 0.014 * shadowTone);

        // A small density response keeps newly saturated colors rich rather than
        // electronic, then pulls out-of-gamut negative channels toward neutral.
        float colorIncrease = max(0.0, saturationScale * vibranceScale - 1.0);
        lab.x -= min(0.012, colorIncrease * min(chroma, 0.25) * 0.05);
        rgb = oklabToRec2020(lab);
        float y = max(dot(rgb, luma), 0.000001);
        float minimum = min(rgb.r, min(rgb.g, rgb.b));
        float gamutScale = minimum < 0.0 ? y / max(y - minimum, 0.000001) : 1.0;
        rgb = max(vec3(0.0), mix(vec3(y), rgb, clamp(gamutScale, 0.0, 1.0)));

        // As luminance enters the shoulder, compress only the chroma that no longer
        // fits below display white. This gives film-like highlight desaturation and
        // prevents one channel from clipping early and producing a colored edge.
        float maximum = max(rgb.r, max(rgb.g, rgb.b));
        float colorExcursion = max(maximum - y, 0.0);
        float availableExcursion = max(1.0 - y, 0.0);
        float highlightGamutScale = colorExcursion > availableExcursion
            ? availableExcursion / max(colorExcursion, 0.000001)
            : 1.0;
        rgb = mix(vec3(y), rgb, clamp(highlightGamutScale, 0.0, 1.0));
        if (sourceY > 1.0) {
            rgb = min(rgb, vec3(0.99));
        }

        return vec4(rgb, pixel.a);
    }
    """#

    static let lightShapingSource = #"""
    kernel vec4 lightShape(__sample pixel, vec4 extent, float amount, float focus, float pop, float bias, float roundness, vec2 center) {
        vec2 uv = (destCoord() - extent.xy) / extent.zw;
        vec2 delta = uv - center;
        float aspect = extent.z / max(extent.w, 1.0);
        delta.x *= mix(1.0, aspect, clamp(roundness, 0.0, 1.0));
        float corner = length(vec2(0.5 * mix(1.0, aspect, clamp(roundness, 0.0, 1.0)), 0.5));
        float distanceFromCenter = length(delta) / max(corner, 0.001);
        float inner = mix(0.08, 0.82, clamp(focus, 0.0, 1.0));
        float falloff = smoothstep(inner, 1.0, distanceFromCenter);
        float centerLift = (bias - 0.5) * amount * 0.35 * (1.0 - falloff);
        float edgeLoss = amount * falloff * mix(1.15, 0.8, bias);
        float gain = exp2(centerLift - edgeLoss);
        vec3 rgb = pixel.rgb * gain;
        float contrast = 1.0 + (pop - 0.5) * amount * 0.16;
        rgb = max(vec3(0.0), (rgb - vec3(0.18)) * contrast + vec3(0.18));
        return vec4(rgb, pixel.a);
    }
    """#

    static let lensRadialBlurSource = #"""
    kernel vec4 lensRadialBlur(
        sampler source,
        vec4 extent,
        float maximumOffset,
        float falloff,
        vec2 center
    ) {
        vec2 coordinate = destCoord();
        vec2 uv = (coordinate - extent.xy) / extent.zw;
        vec2 delta = uv - center;
        float aspect = extent.z / max(extent.w, 1.0);
        vec2 opticalDelta = vec2(delta.x, delta.y / max(aspect, 0.0001));
        float cornerRadius = length(vec2(0.5, 0.5 / max(aspect, 0.0001)));
        float radius = length(opticalDelta) / max(cornerRadius, 0.0001);
        float inner = mix(0.08, 0.70, clamp(falloff, 0.0, 1.0));
        float outer = mix(0.80, 1.02, clamp(falloff, 0.0, 1.0));
        float edge = smoothstep(inner, outer, radius);

        vec2 pixelCenter = extent.xy + center * extent.zw;
        vec2 pixelDelta = coordinate - pixelCenter;
        float pixelRadius = length(pixelDelta);
        vec2 radial = pixelRadius > 0.0001
            ? pixelDelta / pixelRadius
            : vec2(0.0);

        // This is Kromo's polar-space Gaussian expressed directly in Cartesian
        // coordinates: convolution follows the radial axis, and its radius grows
        // continuously as the image leaves the focus area. Forty-nine bilinear
        // samples eliminate the discrete echoes visible in the former 7-tap pass.
        float span = maximumOffset * edge;
        vec4 accumulated = vec4(0.0);
        float weightSum = 0.0;
        for (int index = -24; index <= 24; index++) {
            float position = float(index) / 24.0;
            float gaussianPosition = position * 2.75;
            float weight = exp(-0.5 * gaussianPosition * gaussianPosition);
            vec2 sampleCoordinate = coordinate + radial * position * span;
            accumulated += sample(
                source,
                samplerTransform(source, sampleCoordinate)
            ) * weight;
            weightSum += weight;
        }
        return accumulated / max(weightSum, 0.000001);
    }
    """#

    static let lensChromaticSource = #"""
    kernel vec4 lensChromatic(
        sampler blurredSource,
        vec4 extent,
        float falloff,
        float colorFringing,
        vec2 center
    ) {
        vec2 coordinate = destCoord();
        vec2 uv = (coordinate - extent.xy) / extent.zw;
        vec2 delta = uv - center;
        float aspect = extent.z / max(extent.w, 1.0);
        vec2 opticalDelta = vec2(delta.x, delta.y / max(aspect, 0.0001));
        float cornerRadius = length(vec2(0.5, 0.5 / max(aspect, 0.0001)));
        float radius = length(opticalDelta) / max(cornerRadius, 0.0001);
        float inner = mix(0.08, 0.70, clamp(falloff, 0.0, 1.0));
        float outer = mix(0.80, 1.02, clamp(falloff, 0.0, 1.0));
        float edge = smoothstep(inner, outer, radius);

        vec2 pixelCenter = extent.xy + center * extent.zw;
        vec2 pixelDelta = coordinate - pixelCenter;

        // Match Kromo's continuous channel enlargement: red remains anchored,
        // green expands slightly, and blue expands farther. Because this samples
        // the already-continuous radial convolution, no colored tap bands appear.
        float separation = clamp(colorFringing, 0.0, 2.0) * edge;
        float greenScale = 0.018 * separation;
        float blueScale = 0.044 * separation;
        vec2 greenCoordinate = coordinate - pixelDelta * (greenScale / (1.0 + greenScale));
        vec2 blueCoordinate = coordinate - pixelDelta * (blueScale / (1.0 + blueScale));

        vec4 anchored = sample(
            blurredSource,
            samplerTransform(blurredSource, coordinate)
        );
        float green = sample(
            blurredSource,
            samplerTransform(blurredSource, greenCoordinate)
        ).g;
        float blue = sample(
            blurredSource,
            samplerTransform(blurredSource, blueCoordinate)
        ).b;
        return vec4(max(vec3(anchored.r, green, blue), vec3(0.0)), anchored.a);
    }
    """#

    static let diffusionSource = #"""
    kernel vec4 diffuse(__sample source, __sample detail, __sample bloom, __sample wide, float amount, float bloomCharacter, float veil, float sourceBias, float warmth) {
        float sourceY = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
        float haloY = dot(bloom.rgb, vec3(0.2126, 0.7152, 0.0722));
        float strength = 1.0 - exp(-3.5 * clamp(amount, 0.0, 1.0));

        float kneeStart = mix(0.02, 0.35, clamp(sourceBias, 0.0, 1.0));
        float kneeEnd = min(1.5, kneeStart + 0.65);
        float flareGate = mix(0.30, 1.0, smoothstep(kneeStart, kneeEnd, haloY));

        // Black diffusion particles retain substantially more shadow density while
        // still allowing nearby practicals to spill into dark surroundings.
        float blackRetention = mix(0.62, 1.0, smoothstep(0.025, 0.25, sourceY));
        float nearWeight = strength * mix(0.18, 0.30, clamp(bloomCharacter, 0.0, 1.0));
        float bloomWeight = strength * mix(0.18, 0.46, clamp(bloomCharacter, 0.0, 1.0)) * flareGate * blackRetention;
        float wideWeight = strength * mix(0.08, 0.30, clamp(bloomCharacter, 0.0, 1.0)) * flareGate * blackRetention;
        float veilWeight = strength * clamp(veil, 0.0, 0.5) * 0.35 * blackRetention;

        float rawScatterWeight = nearWeight + bloomWeight + wideWeight + veilWeight;
        float scatterScale = min(1.0, 0.82 / max(rawScatterWeight, 0.0001));
        float scatteredWeight = rawScatterWeight * scatterScale;
        float sourceWeightFinal = 1.0 - scatteredWeight;
        vec3 warmthScale = vec3(1.0 + warmth * 0.08, 1.0, 1.0 - warmth * 0.04);
        vec3 scattered = (detail.rgb * nearWeight
            + bloom.rgb * warmthScale * bloomWeight
            + wide.rgb * warmthScale * (wideWeight + veilWeight)) * scatterScale;
        vec3 rgb = max(vec3(0.0), source.rgb * sourceWeightFinal + scattered);
        return vec4(rgb, source.a);
    }
    """#

    static let halationSource = #"""
    kernel vec4 halate(__sample source, __sample nearBlur, __sample middleBlur, __sample farBlur, float amount, float tail, float colorShift, float saturation, float greenLeakage) {
        float farWeight = mix(0.08, 0.26, clamp(tail, 0.0, 1.0));
        float middleWeight = 0.32;
        float nearWeight = 1.0 - middleWeight - farWeight;
        vec3 scattered = nearBlur.rgb * nearWeight + middleBlur.rgb * middleWeight + farBlur.rgb * farWeight;
        float redScatter = clamp(amount * mix(0.55, 0.92, saturation), 0.0, 0.85);
        float greenScatter = clamp(amount * greenLeakage * mix(0.8, 0.35, saturation) * mix(1.2, 0.75, colorShift), 0.0, 0.35);
        vec3 rgb;
        rgb.r = mix(source.r, scattered.r, redScatter);
        rgb.g = mix(source.g, scattered.g, greenScatter);
        rgb.b = source.b;
        return vec4(rgb, source.a);
    }
    """#

    static let grainSource = #"""
    float filmHash(vec2 p, float seed) {
        return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 0.0137) * 43758.5453123);
    }

    float filmNoise(vec2 p, float seed) {
        vec2 cell = floor(p);
        vec2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        float a = filmHash(cell, seed);
        float b = filmHash(cell + vec2(1.0, 0.0), seed);
        float c = filmHash(cell + vec2(0.0, 1.0), seed);
        float d = filmHash(cell + vec2(1.0, 1.0), seed);
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }

    kernel vec4 grain(__sample source, vec4 extent, float amount, float particlePixels, float acutance, float variation, float chroma, float shadowResponse, float highlightResponse, float seed) {
        vec2 coordinate = (destCoord() - extent.xy) / max(particlePixels, 0.5);
        float primary = filmNoise(coordinate, seed) - 0.5;
        float clumpScale = mix(0.62, 0.34, clamp(variation, 0.0, 1.0));
        float clump = filmNoise(coordinate * clumpScale + vec2(17.3, 9.1), seed + 41.0) - 0.5;
        float crisp = filmHash(floor(destCoord()), seed + 97.0) - 0.5;
        float densityNoise = primary * 0.72 + clump * (0.18 + variation * 0.22) + crisp * acutance * 0.12;

        float luminance = max(0.00001, dot(source.rgb, vec3(0.2126, 0.7152, 0.0722)));
        float shadowWeight = pow(clamp(1.0 - luminance, 0.0, 1.0), 0.62);
        float tonalResponse = mix(highlightResponse, shadowResponse, shadowWeight);
        float sigma = amount * tonalResponse * 0.34;
        float densityDelta = densityNoise * sigma;
        float densityCompensation = 0.10 * sigma * sigma;
        float luminanceScale = exp2(-(densityDelta + densityCompensation) * 3.321928);

        vec3 chromaNoise = vec3(
            filmNoise(coordinate * 0.91 + vec2(3.1, 7.7), seed + 151.0),
            filmNoise(coordinate * 1.07 + vec2(11.2, 2.4), seed + 263.0),
            filmNoise(coordinate * 0.83 + vec2(5.8, 13.9), seed + 379.0)
        ) - vec3(0.5);
        // Independent dye-layer variation is separated from the shared silver-density
        // component and made luminance-neutral so Chroma changes color texture rather
        // than overall grain contrast.
        chromaNoise -= vec3(dot(chromaNoise, vec3(0.2126, 0.7152, 0.0722)));
        float chromaStrength = amount * clamp(chroma, 0.0, 1.0) * tonalResponse * 0.50;
        vec3 colorScale = max(vec3(0.05), vec3(1.0) + chromaNoise * chromaStrength);
        vec3 rgb = max(vec3(0.0), source.rgb * luminanceScale * colorScale);
        return vec4(rgb, source.a);
    }
    """#
}
