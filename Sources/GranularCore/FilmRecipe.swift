import Foundation

public enum FilmStockID: String, CaseIterable, Codable, Hashable, Sendable {
    case none
    case portra160
    case portra400
    case gold200
    case ektar100
    case pro400H
    case superiaReala
    case vision250D

    public var name: String {
        switch self {
        case .none: "None"
        case .portra160: "Portra 160 / Endura"
        case .portra400: "Portra 400 / Endura"
        case .gold200: "Gold 200 / Endura"
        case .ektar100: "Ektar 100 / Endura"
        case .pro400H: "Pro 400H / Crystal Archive"
        case .superiaReala: "Superia Reala / Crystal Archive"
        case .vision250D: "Vision3 250D / 2383"
        }
    }

    var resourceName: String? {
        switch self {
        case .none: nil
        case .portra160: "portra_160_endura_premier"
        case .portra400: "portra_400_endura_premier"
        case .gold200: "gold_200_endura_premier"
        case .ektar100: "ektar_100_endura_premier"
        case .pro400H: "fuji_pro_400h_ca_maxima"
        case .superiaReala: "fuji_superia_reala_ca_pro_pdii"
        case .vision250D: "vision3_250d_2383"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let storedValue = try container.decode(String.self)
        switch storedValue {
        case "vision500T":
            self = .vision250D
        case "velvia50":
            self = .none
        default:
            guard let stock = Self(rawValue: storedValue) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown Granular color stock: \(storedValue)"
                )
            }
            self = stock
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct FilmToneSettings: Codable, Hashable, Sendable {
    public static let maximumStockAmount = 2.0

    public var isEnabled: Bool
    public var stock: FilmStockID
    public var stockAmount: Double
    public var exposure: Double
    public var contrast: Double
    public var saturation: Double
    public var vibrance: Double
    public var warmth: Double

    public init(
        isEnabled: Bool = true,
        stock: FilmStockID = .none,
        stockAmount: Double = 1,
        exposure: Double = 0,
        contrast: Double = 0,
        saturation: Double = 0,
        vibrance: Double = 0,
        warmth: Double = 0
    ) {
        self.isEnabled = isEnabled
        self.stock = stock
        self.stockAmount = stockAmount
        self.exposure = exposure
        self.contrast = contrast
        self.saturation = saturation
        self.vibrance = vibrance
        self.warmth = warmth
    }

    public var isNeutral: Bool {
        (stock == .none || stockAmount == 0)
            && !hasToneAdjustments
    }

    public var hasToneAdjustments: Bool {
        exposure != 0
            || contrast != 0
            || saturation != 0
            || vibrance != 0
            || warmth != 0
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case stock
        case stockAmount
        case exposure
        case contrast
        case saturation
        case vibrance
        case warmth
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        stock = try container.decodeIfPresent(FilmStockID.self, forKey: .stock) ?? .none
        stockAmount = try container.decodeIfPresent(Double.self, forKey: .stockAmount) ?? 1
        exposure = try container.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        contrast = try container.decodeIfPresent(Double.self, forKey: .contrast) ?? 0
        saturation = try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 0
        vibrance = try container.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0
        warmth = try container.decodeIfPresent(Double.self, forKey: .warmth) ?? 0
    }
}

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

public struct LensBlurSettings: Codable, Hashable, Sendable {
    public static let maximumAmount = 1.0

    public var isEnabled: Bool
    public var amount: Double
    public var falloff: Double
    public var colorFringing: Double
    public var focusX: Double
    public var focusY: Double

    public init(
        isEnabled: Bool = false,
        amount: Double = 0.25,
        falloff: Double = 0.55,
        colorFringing: Double = 0.075,
        focusX: Double = 0.5,
        focusY: Double = 0.5
    ) {
        self.isEnabled = isEnabled
        self.amount = amount
        self.falloff = falloff
        self.colorFringing = colorFringing
        self.focusX = focusX
        self.focusY = focusY
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case amount
        case falloff
        case colorFringing
        case focusX
        case focusY
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        amount = try container.decodeIfPresent(Double.self, forKey: .amount) ?? 0.25
        falloff = try container.decodeIfPresent(Double.self, forKey: .falloff) ?? 0.55
        colorFringing = try container.decodeIfPresent(Double.self, forKey: .colorFringing) ?? 0.075
        focusX = try container.decodeIfPresent(Double.self, forKey: .focusX) ?? 0.5
        focusY = try container.decodeIfPresent(Double.self, forKey: .focusY) ?? 0.5
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
    public var tone: FilmToneSettings
    public var lightShaping: LightShapingSettings
    public var lensBlur: LensBlurSettings
    public var diffusion: DiffusionSettings
    public var halation: HalationSettings
    public var grain: GrainSettings

    public init(
        id: String,
        name: String,
        strength: Double = 1,
        tone: FilmToneSettings = .init(),
        lightShaping: LightShapingSettings,
        lensBlur: LensBlurSettings = .init(),
        diffusion: DiffusionSettings,
        halation: HalationSettings,
        grain: GrainSettings
    ) {
        self.id = id
        self.name = name
        self.strength = strength
        self.tone = tone
        self.lightShaping = lightShaping
        self.lensBlur = lensBlur
        self.diffusion = diffusion
        self.halation = halation
        self.grain = grain
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case strength
        case tone
        case lightShaping
        case lensBlur
        case diffusion
        case halation
        case grain
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        strength = try container.decodeIfPresent(Double.self, forKey: .strength) ?? 1
        tone = try container.decodeIfPresent(FilmToneSettings.self, forKey: .tone) ?? .init()
        lightShaping = try container.decode(LightShapingSettings.self, forKey: .lightShaping)
        lensBlur = try container.decodeIfPresent(LensBlurSettings.self, forKey: .lensBlur) ?? .init()
        diffusion = try container.decode(DiffusionSettings.self, forKey: .diffusion)
        halation = try container.decode(HalationSettings.self, forKey: .halation)
        grain = try container.decode(GrainSettings.self, forKey: .grain)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(strength, forKey: .strength)
        try container.encode(tone, forKey: .tone)
        try container.encode(lightShaping, forKey: .lightShaping)
        try container.encode(lensBlur, forKey: .lensBlur)
        try container.encode(diffusion, forKey: .diffusion)
        try container.encode(halation, forKey: .halation)
        try container.encode(grain, forKey: .grain)
    }
}

public extension FilmRecipe {
    static let builtIns: [FilmRecipe] = [
        FilmRecipe(
            id: "clean-120",
            name: "Clean 120",
            tone: .init(isEnabled: false),
            lightShaping: .init(amountStops: 0.10, focus: 0.68),
            diffusion: .init(amount: 0.10, bloom: 0.2, veil: 0.03),
            halation: .init(amount: 0.10, spillRadius: 0.20, tail: 0.2),
            grain: .init(amount: 0.20, particleSizeMicrons: 6, chroma: 0.05, virtualGateWidthMillimeters: 56)
        ),
        FilmRecipe(
            id: "classic-35",
            name: "Classic 35",
            tone: .init(isEnabled: false),
            lightShaping: .init(amountStops: 0.25, focus: 0.56),
            diffusion: .init(amount: 0.06, bloom: 0.35, veil: 0.10),
            halation: .init(amount: 0.15, spillRadius: 0.35, tail: 0.35),
            grain: .init(amount: 0.17, particleSizeMicrons: 10, chroma: 0.12)
        ),
        FilmRecipe(
            id: "extra-35",
            name: "Extra 35",
            tone: .init(isEnabled: false),
            lightShaping: .init(amountStops: 0.25, focus: 0.56),
            diffusion: .init(amount: 0.10, bloom: 0.35, veil: 0.10),
            halation: .init(amount: 0.25, spillRadius: 0.35, tail: 0.35),
            grain: .init(amount: 0.25, particleSizeMicrons: 10, chroma: 0.12)
        ),
        FilmRecipe(
            id: "soft-16",
            name: "Soft 16",
            tone: .init(isEnabled: false),
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
        result.tone.stockAmount *= effectiveStrength
        result.tone.exposure *= effectiveStrength
        result.tone.contrast *= effectiveStrength
        result.tone.saturation *= effectiveStrength
        result.tone.vibrance *= effectiveStrength
        result.tone.warmth *= effectiveStrength
        result.lightShaping.amountStops *= effectiveStrength
        result.lensBlur.amount *= effectiveStrength
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

    func normalizedFromAmountScaleVersion3() -> FilmRecipe {
        var result = self
        result.lensBlur.colorFringing /= 2
        return result
    }
}
