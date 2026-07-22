import CoreGraphics
import CoreImage
import Foundation

public enum FilmRendererError: LocalizedError {
    case kernelCompilationFailed(String)
    case imageLoadFailed(URL)
    case renderFailed

    public var errorDescription: String? {
        switch self {
        case .kernelCompilationFailed(let name):
            "Filmify could not compile its \(name) image kernel."
        case .imageLoadFailed(let url):
            "Filmify could not open \(url.lastPathComponent)."
        case .renderFailed:
            "Filmify could not render the image."
        }
    }
}

public final class FilmRenderer: @unchecked Sendable {
    private let lightShapingKernel: CIColorKernel
    private let diffusionKernel: CIColorKernel
    private let halationKernel: CIColorKernel
    private let grainKernel: CIColorKernel

    public init() throws {
        guard let lightShapingKernel = CIColorKernel(source: Self.lightShapingSource) else {
            throw FilmRendererError.kernelCompilationFailed("light-shaping")
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

        self.lightShapingKernel = lightShapingKernel
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

        if recipe.lightShaping.isEnabled, recipe.lightShaping.amountStops != 0 {
            image = try applyLightShaping(image, settings: recipe.lightShaping, extent: extent)
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
