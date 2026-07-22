import Foundation

public struct LightShapingSettings: Codable, Hashable, Sendable {
    public static let maximumAmount = 1.0

    public var isEnabled: Bool
    public var amountStops: Double
    public var focus: Double
    public var pop: Double
    public var bias: Double
    public var roundness: Double
    public var centerX: Double
    public var centerY: Double

    public init(
        isEnabled: Bool = true,
        amountStops: Double = 0.25,
        focus: Double = 0.55,
        pop: Double = 0.5,
        bias: Double = 0.5,
        roundness: Double = 0.5,
        centerX: Double = 0.5,
        centerY: Double = 0.5
    ) {
        self.isEnabled = isEnabled
        self.amountStops = amountStops
        self.focus = focus
        self.pop = pop
        self.bias = bias
        self.roundness = roundness
        self.centerX = centerX
        self.centerY = centerY
    }
}

public struct DiffusionSettings: Codable, Hashable, Sendable {
    public static let maximumAmount = 1.0

    public var isEnabled: Bool
    public var amount: Double
    public var bloom: Double
    public var veil: Double
    public var sourceBias: Double
    public var warmth: Double
    public var focusX: Double
    public var focusY: Double

    public init(
        isEnabled: Bool = true,
        amount: Double = 0.25,
        bloom: Double = 0.35,
        veil: Double = 0.1,
        sourceBias: Double = 0.25,
        warmth: Double = 0,
        focusX: Double = 0.5,
        focusY: Double = 0.5
    ) {
        self.isEnabled = isEnabled
        self.amount = amount
        self.bloom = bloom
        self.veil = veil
        self.sourceBias = sourceBias
        self.warmth = warmth
        self.focusX = focusX
        self.focusY = focusY
    }
}

public struct HalationSettings: Codable, Hashable, Sendable {
    public static let maximumAmount = 1.0

    public var isEnabled: Bool
    public var amount: Double
    public var spillRadius: Double
    public var tail: Double
    public var colorShift: Double
    public var saturation: Double
    public var greenLeakage: Double

    public init(
        isEnabled: Bool = true,
        amount: Double = 0.25,
        spillRadius: Double = 0.35,
        tail: Double = 0.35,
        colorShift: Double = 0.5,
        saturation: Double = 0.65,
        greenLeakage: Double = 0.12
    ) {
        self.isEnabled = isEnabled
        self.amount = amount
        self.spillRadius = spillRadius
        self.tail = tail
        self.colorShift = colorShift
        self.saturation = saturation
        self.greenLeakage = greenLeakage
    }
}

public struct GrainSettings: Codable, Hashable, Sendable {
    public static let maximumAmount = 1.0

    public var isEnabled: Bool
    public var amount: Double
    public var particleSizeMicrons: Double
    public var acutance: Double
    public var sizeVariation: Double
    public var chroma: Double
    public var shadowResponse: Double
    public var highlightResponse: Double
    public var virtualGateWidthMillimeters: Double
    public var seed: UInt32

    public init(
        isEnabled: Bool = true,
        amount: Double = 0.25,
        particleSizeMicrons: Double = 9,
        acutance: Double = 0.55,
        sizeVariation: Double = 0.25,
        chroma: Double = 0.12,
        shadowResponse: Double = 0.72,
        highlightResponse: Double = 0.28,
        virtualGateWidthMillimeters: Double = 36,
        seed: UInt32 = 2_016
    ) {
        self.isEnabled = isEnabled
        self.amount = amount
        self.particleSizeMicrons = particleSizeMicrons
        self.acutance = acutance
        self.sizeVariation = sizeVariation
        self.chroma = chroma
        self.shadowResponse = shadowResponse
        self.highlightResponse = highlightResponse
        self.virtualGateWidthMillimeters = virtualGateWidthMillimeters
        self.seed = seed
    }
}

public struct FilmRecipe: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var strength: Double
    public var lightShaping: LightShapingSettings
    public var diffusion: DiffusionSettings
    public var halation: HalationSettings
    public var grain: GrainSettings

    public init(
        id: String,
        name: String,
        strength: Double = 1,
        lightShaping: LightShapingSettings,
        diffusion: DiffusionSettings,
        halation: HalationSettings,
        grain: GrainSettings
    ) {
        self.id = id
        self.name = name
        self.strength = strength
        self.lightShaping = lightShaping
        self.diffusion = diffusion
        self.halation = halation
        self.grain = grain
    }
}

public extension FilmRecipe {
    static let builtIns: [FilmRecipe] = [
        FilmRecipe(
            id: "clean-120",
            name: "Clean 120",
            lightShaping: .init(amountStops: 0.10, focus: 0.68),
            diffusion: .init(amount: 0.10, bloom: 0.2, veil: 0.03),
            halation: .init(amount: 0.10, spillRadius: 0.20, tail: 0.2),
            grain: .init(amount: 0.20, particleSizeMicrons: 6, chroma: 0.05, virtualGateWidthMillimeters: 56)
        ),
        FilmRecipe(
            id: "classic-35",
            name: "Classic 35",
            lightShaping: .init(amountStops: 0.25, focus: 0.56),
            diffusion: .init(amount: 0.10, bloom: 0.35, veil: 0.10),
            halation: .init(amount: 0.25, spillRadius: 0.35, tail: 0.35),
            grain: .init(amount: 0.30, particleSizeMicrons: 10, chroma: 0.12)
        ),
        FilmRecipe(
            id: "soft-16",
            name: "Soft 16",
            lightShaping: .init(amountStops: 0.50, focus: 0.48),
            diffusion: .init(amount: 0.40, bloom: 0.50, veil: 0.16),
            halation: .init(amount: 0.40, spillRadius: 0.5, tail: 0.52),
            grain: .init(
                amount: 0.35,
                particleSizeMicrons: 14.1,
                acutance: 0.42,
                sizeVariation: 0.50,
                chroma: 0.98,
                shadowResponse: 0.72,
                highlightResponse: 0.28,
                virtualGateWidthMillimeters: 21.1
            )
        )
    ]

    static var classic35: FilmRecipe {
        builtIns.first { $0.id == "classic-35" }!
    }

    var effective: FilmRecipe {
        var result = self
        let effectiveStrength = max(0, min(1, self.strength))
        result.lightShaping.amountStops *= effectiveStrength
        result.diffusion.amount *= effectiveStrength
        result.diffusion.veil *= effectiveStrength
        result.halation.amount *= effectiveStrength
        result.grain.amount *= effectiveStrength
        return result
    }

    func normalizedFromLegacyAmountScale() -> FilmRecipe {
        var result = self
        result.lightShaping.amountStops /= 2
        result.diffusion.amount /= 2
        result.halation.amount /= 2
        result.grain.amount /= 2
        return result
    }

    func normalizedFromAmountScaleVersion1() -> FilmRecipe {
        var result = self
        result.lightShaping.amountStops /= 2
        result.grain.amount *= 0.75
        return result
    }

    func normalizedFromAmountScaleVersion2() -> FilmRecipe {
        var result = self
        result.grain.amount *= 2 / 3
        return result
    }
}
