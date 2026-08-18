import CoreImage
import Foundation
import Testing
@testable import GranularCore

@Test func builtInRecipesHaveStableIdentifiersAndRanges() {
    #expect(FilmRecipe.builtIns.map(\.name) == ["Clean 120", "Classic 35", "Extra 35", "Soft 16"])
    #expect(Set(FilmRecipe.builtIns.map(\.id)).count == FilmRecipe.builtIns.count)

    for recipe in FilmRecipe.builtIns {
        #expect((0 ... 1).contains(recipe.strength))
        #expect(recipe.tone == FilmToneSettings(isEnabled: false))
        #expect((0 ... 1).contains(recipe.lightShaping.amountStops))
        #expect(recipe.lensBlur.isEnabled == false)
        #expect((0 ... 1).contains(recipe.lensBlur.amount))
        #expect((0 ... 1).contains(recipe.diffusion.amount))
        #expect((0 ... 1).contains(recipe.halation.amount))
        #expect((0 ... 1).contains(recipe.grain.amount))
        #expect(recipe.grain.particleSizeMicrons > 0)
        #expect(recipe.grain.virtualGateWidthMillimeters > 0)
    }
}

@Test func classic35UsesTheCIHBalance() {
    let recipe = FilmRecipe.classic35

    #expect(recipe.tone == FilmToneSettings(isEnabled: false))
    #expect(recipe.lightShaping.amountStops == 0.25)
    #expect(recipe.diffusion.amount == 0.06)
    #expect(recipe.halation.amount == 0.15)
    #expect(recipe.grain.amount == 0.17)
}

@Test func filmToneScalesWithRecipeStrength() {
    var recipe = FilmRecipe.classic35
    recipe.strength = 0.5
    recipe.tone = .init(
        stock: .portra400,
        stockAmount: 0.8,
        exposure: 1,
        contrast: 0.6,
        saturation: -0.4,
        vibrance: 0.8,
        warmth: 0.2
    )
    let effective = recipe.effective

    #expect(effective.tone.exposure == 0.5)
    #expect(effective.tone.stock == .portra400)
    #expect(effective.tone.stockAmount == 0.4)
    #expect(effective.tone.contrast == 0.3)
    #expect(effective.tone.saturation == -0.2)
    #expect(effective.tone.vibrance == 0.4)
    #expect(effective.tone.warmth == 0.1)
}

@Test func recipesSavedBeforeColorStocksDecodeWithNeutralStockDefaults() throws {
    let encoded = try JSONEncoder().encode(FilmRecipe.classic35)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var tone = try #require(object["tone"] as? [String: Any])
    tone.removeValue(forKey: "stock")
    tone.removeValue(forKey: "stockAmount")
    object["tone"] = tone
    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(FilmRecipe.self, from: legacyData)

    #expect(decoded.tone.stock == .none)
    #expect(decoded.tone.stockAmount == 1)
}

@Test func allNamedColorStocksLoadAsCoreImageCubes() throws {
    for stock in FilmStockID.allCases where stock != .none {
        let cube = try FilmStockLUTLoader.load(stock)
        #expect(cube.dimension == 33)
        #expect(cube.data.count == 33 * 33 * 33 * 4 * MemoryLayout<Float>.size)
    }
}

@Test func colorStockAmountIsNeutralAtZeroAndDistinctAtFullStrength() throws {
    let renderer = try FilmRenderer()
    let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
    let source = CIImage(color: .init(red: 0.42, green: 0.24, blue: 0.10, alpha: 1))
        .cropped(to: extent)
    var recipe = FilmRecipe(
        id: "stock-test",
        name: "Stock Test",
        tone: .init(stock: .portra400, stockAmount: 0),
        lightShaping: .init(isEnabled: false),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        grain: .init(isEnabled: false)
    )

    let sourcePixels = renderFloatPixels(source, extent: extent)
    let neutralPixels = renderFloatPixels(try renderer.render(source, recipe: recipe), extent: extent)
    #expect(abs(sourcePixels[0] - neutralPixels[0]) < 0.000_001)
    #expect(abs(sourcePixels[1] - neutralPixels[1]) < 0.000_001)
    #expect(abs(sourcePixels[2] - neutralPixels[2]) < 0.000_001)

    recipe.tone.stockAmount = 1
    let portraPixels = renderFloatPixels(try renderer.render(source, recipe: recipe), extent: extent)
    recipe.tone.stockAmount = 2
    let overcookedPortraPixels = renderFloatPixels(
        try renderer.render(source, recipe: recipe),
        extent: extent
    )
    recipe.tone.stock = .ektar100
    recipe.tone.stockAmount = 1
    let ektarPixels = renderFloatPixels(try renderer.render(source, recipe: recipe), extent: extent)

    #expect(colorDistance(sourcePixels, portraPixels) > 0.01)
    #expect(
        colorDistance(sourcePixels, overcookedPortraPixels)
            > colorDistance(sourcePixels, portraPixels) * 1.5
    )
    #expect(colorDistance(portraPixels, ektarPixels) > 0.0075)
}

@Test func colorStockAmountDefaultsToOneWithAnOvercookMaximumOfTwo() {
    #expect(FilmToneSettings().stockAmount == 1)
    #expect(FilmToneSettings.maximumStockAmount == 2)
}

@Test func removedColorStocksMigrateWithoutBreakingSavedRecipes() throws {
    let decoder = JSONDecoder()
    let removedVelvia = try decoder.decode(FilmStockID.self, from: Data(#""velvia50""#.utf8))
    let duplicateVision = try decoder.decode(FilmStockID.self, from: Data(#""vision500T""#.utf8))

    #expect(removedVelvia == .none)
    #expect(duplicateVision == .vision250D)
}

@Test func colorStocksRetainColorWithoutImposingASecondStrongContrastCurve() throws {
    let renderer = try FilmRenderer()
    let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
    let lowSource = CIImage(color: .init(red: 0.12, green: 0.12, blue: 0.12, alpha: 1))
        .cropped(to: extent)
    let highSource = CIImage(color: .init(red: 0.68, green: 0.68, blue: 0.68, alpha: 1))
        .cropped(to: extent)
    let sourceContrast = Float(0.68 - 0.12)

    for stock in FilmStockID.allCases where stock != .none {
        let recipe = FilmRecipe(
            id: "stock-contrast-\(stock.rawValue)",
            name: "Stock Contrast",
            tone: .init(stock: stock),
            lightShaping: .init(isEnabled: false),
            diffusion: .init(isEnabled: false),
            halation: .init(isEnabled: false),
            grain: .init(isEnabled: false)
        )
        let low = renderFloatPixels(
            try renderer.render(lowSource, recipe: recipe),
            extent: extent
        )
        let high = renderFloatPixels(
            try renderer.render(highSource, recipe: recipe),
            extent: extent
        )
        let outputContrast = pixelLuminance(high) - pixelLuminance(low)

        #expect(outputContrast > sourceContrast * 0.70)
        #expect(outputContrast < sourceContrast * 1.20)
    }
}

@Test func recipesSavedBeforeFilmToneDecodeWithNeutralDefaults() throws {
    let encoded = try JSONEncoder().encode(FilmRecipe.classic35)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "tone")
    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(FilmRecipe.self, from: legacyData)

    #expect(decoded.tone == FilmToneSettings())
    #expect(decoded.lightShaping == FilmRecipe.classic35.lightShaping)
}

@Test func recipesSavedBeforeLensBlurDecodeWithTheEffectDisabled() throws {
    let encoded = try JSONEncoder().encode(FilmRecipe.classic35)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "lensBlur")
    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(FilmRecipe.self, from: legacyData)

    #expect(decoded.lensBlur == LensBlurSettings())
    #expect(decoded.lensBlur.isEnabled == false)
}

@Test func strengthScalesEffectAmountsWithoutChangingCharacterControls() {
    var recipe = FilmRecipe.classic35
    recipe.strength = 0.5
    let effective = recipe.effective

    #expect(effective.lightShaping.amountStops == recipe.lightShaping.amountStops * 0.5)
    #expect(effective.lensBlur.amount == recipe.lensBlur.amount * 0.5)
    #expect(effective.diffusion.amount == recipe.diffusion.amount * 0.5)
    #expect(effective.halation.amount == recipe.halation.amount * 0.5)
    #expect(effective.grain.amount == recipe.grain.amount * 0.5)
    #expect(effective.grain.particleSizeMicrons == recipe.grain.particleSizeMicrons)
}

@Test func classic35DefaultsMatchCalibratedRecipe() {
    let recipe = FilmRecipe.classic35

    #expect(recipe.lightShaping.amountStops == 0.25)
    #expect(recipe.diffusion.amount == 0.06)
    #expect(recipe.halation.amount == 0.15)
    #expect(recipe.grain.amount == 0.17)
    #expect(recipe.grain.particleSizeMicrons == 10)
}

@Test func clean120DefaultsMatchReferenceSettings() throws {
    let recipe = try #require(FilmRecipe.builtIns.first { $0.id == "clean-120" })

    #expect(recipe.lightShaping.amountStops == 0.10)
    #expect(recipe.lightShaping.focus == 0.68)
    #expect(recipe.diffusion.amount == 0.10)
    #expect(recipe.diffusion.bloom == 0.20)
    #expect(recipe.halation.amount == 0.10)
    #expect(recipe.halation.spillRadius == 0.20)
    #expect(recipe.grain.amount == 0.20)
    #expect(recipe.grain.particleSizeMicrons == 6)
}

@Test func extra35PreservesThePriorClassic35RendererStrengths() throws {
    let recipe = try #require(FilmRecipe.builtIns.first { $0.id == "extra-35" })

    #expect(FilmRenderer.mappedSpotlightAmount(recipe.lightShaping.amountStops) == 1.0)
    #expect(FilmRenderer.mappedOpticalAmount(recipe.diffusion.amount) == 0.20)
    #expect(FilmRenderer.mappedOpticalAmount(recipe.halation.amount) == 0.50)
    #expect(FilmRenderer.mappedGrainAmount(recipe.grain.amount) == 1.50)
}

@Test func halationUsesNormalizedAmountsWithoutChangingRecipeStrengths() throws {
    #expect(HalationSettings.maximumAmount == 1)
    #expect(try #require(FilmRecipe.builtIns.first { $0.id == "clean-120" }).halation.amount == 0.10)
    #expect(try #require(FilmRecipe.builtIns.first { $0.id == "extra-35" }).halation.amount == 0.25)
    #expect(try #require(FilmRecipe.builtIns.first { $0.id == "soft-16" }).halation.amount == 0.40)
}

@Test func diffusionUsesNormalizedAmountsWithoutChangingRecipeStrengths() throws {
    #expect(DiffusionSettings.maximumAmount == 1)
    #expect(try #require(FilmRecipe.builtIns.first { $0.id == "clean-120" }).diffusion.amount == 0.10)
    #expect(try #require(FilmRecipe.builtIns.first { $0.id == "extra-35" }).diffusion.amount == 0.10)
    #expect(try #require(FilmRecipe.builtIns.first { $0.id == "soft-16" }).diffusion.amount == 0.40)
}

@Test func expandedOpticalAmountsUseAProgressiveSecondPass() {
    #expect(FilmRenderer.opticalPassAmounts(for: FilmRenderer.mappedOpticalAmount(0.25)) == [0.5])
    #expect(FilmRenderer.opticalPassAmounts(for: FilmRenderer.mappedOpticalAmount(0.50)) == [1.0])
    #expect(FilmRenderer.opticalPassAmounts(for: FilmRenderer.mappedOpticalAmount(0.75)) == [1.0, 0.5])
    #expect(FilmRenderer.opticalPassAmounts(for: FilmRenderer.mappedOpticalAmount(1.00)) == [1.0, 1.0])
}

@Test func newOpticalMaximumsAreVisiblyStrongerThanTheFormerMaximums() throws {
    let extent = CGRect(x: 0, y: 0, width: 256, height: 256)
    let black = CIImage(color: .init(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
    let practical = CIImage(color: .init(red: 1, green: 1, blue: 1, alpha: 1))
        .cropped(to: CGRect(x: 120, y: 120, width: 16, height: 16))
    let source = practical.composited(over: black)
    let renderer = try FilmRenderer()

    let diffusionAtOne = renderFloatPixels(
        try renderer.render(source, recipe: opticalStrengthRecipe(diffusionAmount: 0.5)),
        extent: extent
    )
    let diffusionAtTwo = renderFloatPixels(
        try renderer.render(source, recipe: opticalStrengthRecipe(diffusionAmount: 1)),
        extent: extent
    )
    let halationAtOne = renderFloatPixels(
        try renderer.render(source, recipe: opticalStrengthRecipe(halationAmount: 0.5)),
        extent: extent
    )
    let halationAtTwo = renderFloatPixels(
        try renderer.render(source, recipe: opticalStrengthRecipe(halationAmount: 1)),
        extent: extent
    )
    let haloPixel = (128 * 256 + 112) * 4

    #expect(diffusionAtTwo[haloPixel] > diffusionAtOne[haloPixel] * 1.05)
    #expect(halationAtTwo[haloPixel] > halationAtOne[haloPixel] * 1.05)
}

@Test func soft16GrainDefaultsMatchReferenceSettings() throws {
    let recipe = try #require(FilmRecipe.builtIns.first { $0.id == "soft-16" })

    #expect(recipe.lightShaping.amountStops == 0.50)
    #expect(recipe.lightShaping.focus == 0.48)
    #expect(recipe.diffusion.amount == 0.40)
    #expect(recipe.diffusion.bloom == 0.50)
    #expect(recipe.halation.amount == 0.40)
    #expect(recipe.halation.spillRadius == 0.50)
    #expect(recipe.grain.amount == 0.35)
    #expect(recipe.grain.particleSizeMicrons == 14.1)
    #expect(recipe.grain.acutance == 0.42)
    #expect(recipe.grain.sizeVariation == 0.50)
    #expect(recipe.grain.chroma == 0.98)
    #expect(recipe.grain.shadowResponse == 0.72)
    #expect(recipe.grain.highlightResponse == 0.28)
    #expect(recipe.grain.virtualGateWidthMillimeters == 21.1)
}

@Test func grainAmountUsesTheStrongerIntensityScale() {
    #expect(FilmRenderer.mappedGrainAmount(0) == 0)
    #expect(FilmRenderer.mappedGrainAmount(0.25) == 1.5)
    #expect(FilmRenderer.mappedGrainAmount(1) == 6)
}

@Test func spotlightAmountUsesTheExpandedIntensityScale() {
    #expect(FilmRenderer.mappedSpotlightAmount(0) == 0)
    #expect(FilmRenderer.mappedSpotlightAmount(0.5) == 2)
    #expect(FilmRenderer.mappedSpotlightAmount(1) == 4)
}

@Test func lensBlurStartsAtTheFormerMaximumAndAllowsOvercooking() {
    #expect(FilmRenderer.mappedLensBlurAmount(0) == 0)
    #expect(FilmRenderer.mappedLensBlurAmount(0.25) == 1)
    #expect(FilmRenderer.mappedLensBlurAmount(1) == 4)
}

@Test func lensBlurRGBSeparationDoublesItsPreviousRange() {
    #expect(FilmRenderer.mappedLensBlurRGBSeparation(0) == 0)
    #expect(FilmRenderer.mappedLensBlurRGBSeparation(0.5) == 1)
    #expect(FilmRenderer.mappedLensBlurRGBSeparation(1) == 2)
}

@Test func legacyCustomRecipeAmountsMigrateWithoutChangingRenderedStrength() {
    let legacy = FilmRecipe(
        id: "custom-legacy",
        name: "Legacy",
        lightShaping: .init(amountStops: 1.2),
        diffusion: .init(amount: 0.6),
        halation: .init(amount: 1.4),
        grain: .init(amount: 1.8)
    )
    let migrated = legacy.normalizedFromLegacyAmountScale()

    #expect(migrated.lightShaping.amountStops == 0.6)
    #expect(migrated.diffusion.amount == 0.3)
    #expect(migrated.halation.amount == 0.7)
    #expect(migrated.grain.amount == 0.9)
}

@Test func versionOneCustomRecipeAmountsMigrateWithoutChangingRenderedStrength() {
    let prior = FilmRecipe(
        id: "custom-version-one",
        name: "Version One",
        lightShaping: .init(amountStops: 0.5),
        diffusion: .init(amount: 0.25),
        halation: .init(amount: 0.25),
        grain: .init(amount: 0.5)
    )
    let migrated = prior.normalizedFromAmountScaleVersion1()

    #expect(migrated.lightShaping.amountStops == 0.25)
    #expect(migrated.diffusion.amount == 0.25)
    #expect(migrated.halation.amount == 0.25)
    #expect(migrated.grain.amount == 0.375)
}

@Test func versionTwoCustomRecipeAmountsMigrateWithoutChangingRenderedStrength() {
    let prior = FilmRecipe(
        id: "custom-version-two",
        name: "Version Two",
        lightShaping: .init(amountStops: 0.25),
        diffusion: .init(amount: 0.25),
        halation: .init(amount: 0.25),
        grain: .init(amount: 0.375)
    )
    let migrated = prior.normalizedFromAmountScaleVersion2()

    #expect(migrated.lightShaping.amountStops == 0.25)
    #expect(migrated.diffusion.amount == 0.25)
    #expect(migrated.halation.amount == 0.25)
    #expect(migrated.grain.amount == 0.25)
}

@Test func versionThreeLensBlurRecipesMigrateWithoutChangingRGBSeparation() {
    let prior = FilmRecipe(
        id: "custom-version-three",
        name: "Version Three",
        lightShaping: .init(),
        lensBlur: .init(isEnabled: true, colorFringing: 1),
        diffusion: .init(),
        halation: .init(),
        grain: .init()
    )
    let migrated = prior.normalizedFromAmountScaleVersion3()

    #expect(migrated.lensBlur.colorFringing == 0.5)
    #expect(
        FilmRenderer.mappedLensBlurRGBSeparation(migrated.lensBlur.colorFringing)
            == prior.lensBlur.colorFringing
    )
}

@Test func viewerZoomUsesActualImageScaleAndFitGeometry() {
    let fit = ViewerZoomMath.fitScale(
        imageWidth: 4_000,
        imageHeight: 3_000,
        viewportWidth: 1_000,
        viewportHeight: 800
    )

    #expect(abs(fit - 0.238) < 0.000_001)
    #expect(ViewerZoomMath.zoomedIn(from: fit) == 0.25)
    #expect(ViewerZoomMath.zoomedOut(from: fit) == 0.125)
    #expect(ViewerZoomMath.zoomedIn(from: 1) == 2)
    #expect(ViewerZoomMath.zoomedOut(from: 1) == 0.5)
    #expect(ViewerZoomMath.zoomedOut(from: 1.25) == 1)
}

@Test func viewerZoomSliderAndPanClampingAreStable() {
    let scale = 0.237
    let position = ViewerZoomMath.sliderPosition(forScale: scale)

    #expect(abs(ViewerZoomMath.scale(forSliderPosition: position) - scale) < 0.000_001)
    #expect(ViewerZoomMath.clampedPanOffset(900, displayLength: 1_600, viewportLength: 1_000) == 300)
    #expect(ViewerZoomMath.clampedPanOffset(-900, displayLength: 1_600, viewportLength: 1_000) == -300)
    #expect(ViewerZoomMath.clampedPanOffset(50, displayLength: 800, viewportLength: 1_000) == 0)
}

@Test func grainChromaProducesVisibleLuminanceNeutralColorVariation() throws {
    let extent = CGRect(x: 0, y: 0, width: 192, height: 192)
    let source = CIImage(color: .init(red: 0.42, green: 0.42, blue: 0.42, alpha: 1))
        .cropped(to: extent)
    let monochromeRecipe = grainTestRecipe(chroma: 0)
    let chromaticRecipe = grainTestRecipe(chroma: 1)
    let renderer = try FilmRenderer()

    let monochromePixels = renderFloatPixels(try renderer.render(source, recipe: monochromeRecipe), extent: extent)
    let chromaticPixels = renderFloatPixels(try renderer.render(source, recipe: chromaticRecipe), extent: extent)
    let monochromeEnergy = meanChromaEnergy(monochromePixels)
    let chromaticEnergy = meanChromaEnergy(chromaticPixels)

    #expect(monochromeEnergy < 0.000_001)
    #expect(chromaticEnergy > 0.000_2)
}

@Test func rendererPreservesSourceExtent() throws {
    let renderer = try FilmRenderer()
    let source = CIImage(color: .init(red: 0.4, green: 0.25, blue: 0.15, alpha: 1))
        .cropped(to: CGRect(x: 0, y: 0, width: 96, height: 64))
    let output = try renderer.render(source, recipe: .classic35)

    #expect(output.extent == source.extent)
}

@Test func filmToneExposureProtectsTheHighlightShoulder() throws {
    let renderer = try FilmRenderer()
    let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
    let recipe = FilmRecipe(
        id: "tone-test",
        name: "Tone Test",
        tone: .init(exposure: 1),
        lightShaping: .init(isEnabled: false),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        grain: .init(isEnabled: false)
    )
    let middleSource = CIImage(color: .init(red: 0.18, green: 0.18, blue: 0.18, alpha: 1))
        .cropped(to: extent)
    let highlightSource = CIImage(color: .init(red: 0.9, green: 0.9, blue: 0.9, alpha: 1))
        .cropped(to: extent)
    let extendedHighlightSource = CIImage(color: .init(red: 2, green: 2, blue: 2, alpha: 1))
        .cropped(to: extent)

    let middle = Double(renderFloatPixels(try renderer.render(middleSource, recipe: recipe), extent: extent)[0])
    let highlight = Double(renderFloatPixels(try renderer.render(highlightSource, recipe: recipe), extent: extent)[0])
    let extendedHighlight = Double(
        renderFloatPixels(try renderer.render(extendedHighlightSource, recipe: recipe), extent: extent)[0]
    )

    #expect(middle > 0.18)
    #expect(middle > 0.38)
    #expect(middle < 0.43)
    #expect(highlight > 0.9)
    #expect(highlight > 0.95)
    #expect(highlight < 1)
    #expect(extendedHighlight > highlight)
    #expect(extendedHighlight < 1)
    #expect(middle / 0.18 > highlight / 0.9)
}

@Test func positiveExposureCompressesColorAsItApproachesTheShoulder() throws {
    let renderer = try FilmRenderer()
    let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
    let recipe = FilmRecipe(
        id: "exposure-color-test",
        name: "Exposure Color Test",
        tone: .init(exposure: 1),
        lightShaping: .init(isEnabled: false),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        grain: .init(isEnabled: false)
    )
    let middleSource = CIImage(color: .init(red: 0.30, green: 0.16, blue: 0.08, alpha: 1))
        .cropped(to: extent)
    let highlightSource = CIImage(color: .init(red: 0.92, green: 0.58, blue: 0.32, alpha: 1))
        .cropped(to: extent)

    let middleInput = renderFloatPixels(middleSource, extent: extent)
    let highlightInput = renderFloatPixels(highlightSource, extent: extent)
    let middleOutput = renderFloatPixels(
        try renderer.render(middleSource, recipe: recipe),
        extent: extent
    )
    let highlightOutput = renderFloatPixels(
        try renderer.render(highlightSource, recipe: recipe),
        extent: extent
    )

    let middleRetention = normalizedChroma(middleOutput) / normalizedChroma(middleInput)
    let highlightRetention = normalizedChroma(highlightOutput) / normalizedChroma(highlightInput)
    #expect(middleRetention < 1)
    #expect(highlightRetention < middleRetention)
}

@Test func filmToneSaturationAndWarmthRemainPhotographic() throws {
    let renderer = try FilmRenderer()
    let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
    let source = CIImage(color: .init(red: 0.52, green: 0.28, blue: 0.12, alpha: 1))
        .cropped(to: extent)
    var recipe = FilmRecipe(
        id: "color-tone-test",
        name: "Color Tone Test",
        tone: .init(saturation: -1),
        lightShaping: .init(isEnabled: false),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        grain: .init(isEnabled: false)
    )

    let monochrome = renderFloatPixels(try renderer.render(source, recipe: recipe), extent: extent)
    #expect(abs(monochrome[0] - monochrome[1]) < 0.001)
    #expect(abs(monochrome[1] - monochrome[2]) < 0.001)

    recipe.tone = .init(warmth: 1)
    let neutralSource = CIImage(color: .init(red: 0.35, green: 0.35, blue: 0.35, alpha: 1))
        .cropped(to: extent)
    let warmed = renderFloatPixels(try renderer.render(neutralSource, recipe: recipe), extent: extent)
    #expect(warmed[0] > warmed[2])
    #expect(warmed[1] > warmed[2])
    let warmedLuminance = 0.2627002 * warmed[0] + 0.6779981 * warmed[1] + 0.0593017 * warmed[2]
    #expect(abs(warmedLuminance - 0.35) < 0.04)
}

@Test func filmToneVibranceProtectsSkinLikeHues() throws {
    let renderer = try FilmRenderer()
    let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
    let recipe = FilmRecipe(
        id: "vibrance-test",
        name: "Vibrance Test",
        tone: .init(vibrance: 1),
        lightShaping: .init(isEnabled: false),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        grain: .init(isEnabled: false)
    )
    let skinColor = [Float(0.38), 0.28, 0.23]
    let foliageColor = [Float(0.25), 0.34, 0.22]
    let skinSource = CIImage(color: .init(
        red: CGFloat(skinColor[0]),
        green: CGFloat(skinColor[1]),
        blue: CGFloat(skinColor[2]),
        alpha: 1
    )).cropped(to: extent)
    let foliageSource = CIImage(color: .init(
        red: CGFloat(foliageColor[0]),
        green: CGFloat(foliageColor[1]),
        blue: CGFloat(foliageColor[2]),
        alpha: 1
    )).cropped(to: extent)

    let skin = renderFloatPixels(try renderer.render(skinSource, recipe: recipe), extent: extent)
    let foliage = renderFloatPixels(try renderer.render(foliageSource, recipe: recipe), extent: extent)
    let skinBoost = channelSpread(skin) / channelSpread(skinColor)
    let foliageBoost = channelSpread(foliage) / channelSpread(foliageColor)

    #expect(skinBoost < foliageBoost)
}

@Test func diffusionCreatesStrongControlledHighlightSpill() throws {
    let extent = CGRect(x: 0, y: 0, width: 256, height: 256)
    let black = CIImage(color: .init(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
    let practical = CIImage(color: .init(red: 1, green: 1, blue: 1, alpha: 1))
        .cropped(to: CGRect(x: 120, y: 120, width: 16, height: 16))
    let source = practical.composited(over: black)
    let recipe = FilmRecipe(
        id: "diffusion-test",
        name: "Diffusion Test",
        lightShaping: .init(isEnabled: false),
        diffusion: .init(amount: 0.25, bloom: 0.65, veil: 0.1, sourceBias: 0.2),
        halation: .init(isEnabled: false),
        grain: .init(isEnabled: false)
    )

    let output = try FilmRenderer().render(source, recipe: recipe)
    let pixels = renderFloatPixels(output, extent: extent)
    let center = pixels[((128 * 256 + 128) * 4)]
    let nearHalo = pixels[((128 * 256 + 116) * 4)]
    let distantShadow = pixels[((32 * 256 + 32) * 4)]

    #expect(center < 0.85)
    #expect(nearHalo > 0.01)
    #expect(distantShadow < 0.005)
}

@Test func lensBlurSoftensTheFieldEdgesWhileKeepingTheOpticalCenterSharp() throws {
    let extent = CGRect(x: 0, y: 0, width: 256, height: 256)
    let black = CIImage(color: .init(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
    let whiteHalf = CIImage(color: .init(red: 1, green: 1, blue: 1, alpha: 1))
        .cropped(to: CGRect(x: 128, y: 0, width: 128, height: 256))
    let source = whiteHalf.composited(over: black)
    let recipe = FilmRecipe(
        id: "lens-blur-test",
        name: "Lens Blur Test",
        lightShaping: .init(isEnabled: false),
        lensBlur: .init(
            isEnabled: true,
            amount: 1,
            falloff: 0.35,
            character: 0.7,
            colorFringing: 0,
            asymmetry: 0
        ),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        grain: .init(isEnabled: false)
    )

    let pixels = renderFloatPixels(try FilmRenderer().render(source, recipe: recipe), extent: extent)
    let centerDarkSide = pixels[((128 * 256 + 123) * 4)]
    let edgeDarkSide = pixels[((8 * 256 + 123) * 4)]

    #expect(centerDarkSide < 0.02)
    #expect(edgeDarkSide > centerDarkSide + 0.02)
}

@Test func lensBlurRGBSeparationCreatesSoftPrismaticGhostsNearTheEdge() throws {
    let extent = CGRect(x: 0, y: 0, width: 256, height: 256)
    let black = CIImage(color: .init(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
    let whiteHalf = CIImage(color: .init(red: 1, green: 1, blue: 1, alpha: 1))
        .cropped(to: CGRect(x: 128, y: 0, width: 128, height: 256))
    let source = whiteHalf.composited(over: black)
    let recipe = FilmRecipe(
        id: "lens-fringe-test",
        name: "Lens Fringe Test",
        lightShaping: .init(isEnabled: false),
        lensBlur: .init(
            isEnabled: true,
            amount: 0.25,
            falloff: 0.2,
            character: 0.2,
            colorFringing: 1,
            asymmetry: 0
        ),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        grain: .init(isEnabled: false)
    )

    let pixels = renderFloatPixels(try FilmRenderer().render(source, recipe: recipe), extent: extent)
    let edgeIndex = (8 * 256 + 126) * 4
    let channelSeparation = max(
        abs(pixels[edgeIndex] - pixels[edgeIndex + 1]),
        abs(pixels[edgeIndex + 2] - pixels[edgeIndex + 1])
    )

    #expect(channelSeparation > 0.02)
}

@Test func processingServiceWritesAReadableCollisionSafeOutput() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("GranularTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let sourceURL = directory.appendingPathComponent("frame.png")
    let sourceImage = CIImage(color: .init(red: 0.62, green: 0.28, blue: 0.12, alpha: 1))
        .cropped(to: CGRect(x: 0, y: 0, width: 80, height: 60))
    let context = CIContext()
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let sourceData = try #require(
        context.pngRepresentation(of: sourceImage, format: .RGBA8, colorSpace: colorSpace)
    )
    try sourceData.write(to: sourceURL)

    let service = try ImageProcessingService()
    let outputURL = try await service.process(
        sourceURL: sourceURL,
        destinationFolder: directory,
        recipe: .classic35,
        options: .init(format: .png)
    )

    #expect(outputURL.lastPathComponent == "frame — Granular.png")
    #expect(FileManager.default.fileExists(atPath: outputURL.path))
    #expect(CIImage(contentsOf: outputURL)?.extent == sourceImage.extent)
}

@Test func watchedFolderRetriesFilesUntilProcessingSucceeds() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("GranularWatchTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let sourceURL = directory.appendingPathComponent("incoming.png")
    try Data([0x46, 0x49, 0x4C, 0x4D]).write(to: sourceURL)

    let recorder = WatchMonitorRecorder(succeedAfterAttempt: 2)
    let monitor = WatchedFolderMonitor(
        scanInterval: .milliseconds(15),
        retryDelay: .milliseconds(25)
    )
    await monitor.start(folder: directory) { urls in
        await recorder.handle(urls)
    } errorHandler: { message in
        await recorder.record(error: message)
    }

    let didRetry = await eventually {
        await recorder.attemptCount >= 2
    }
    await monitor.stop()

    #expect(didRetry)
    #expect(await recorder.attemptCount == 2)
    #expect(await recorder.errors.isEmpty)
}

@Test func watchedFolderReportsAnUnavailableIncomingFolder() async {
    let missingFolder = FileManager.default.temporaryDirectory
        .appendingPathComponent("MissingGranularWatchFolder-\(UUID().uuidString)", isDirectory: true)
    let recorder = WatchMonitorRecorder(succeedAfterAttempt: 1)
    let monitor = WatchedFolderMonitor(
        scanInterval: .milliseconds(15),
        retryDelay: .milliseconds(25)
    )
    await monitor.start(folder: missingFolder) { urls in
        await recorder.handle(urls)
    } errorHandler: { message in
        await recorder.record(error: message)
    }

    let reportedError = await eventually {
        await !recorder.errors.isEmpty
    }
    await monitor.stop()

    #expect(reportedError)
    #expect(await recorder.errors.first?.contains("no longer available") == true)
}

private actor WatchMonitorRecorder {
    private(set) var attemptCount = 0
    private(set) var errors: [String] = []
    private let succeedAfterAttempt: Int

    init(succeedAfterAttempt: Int) {
        self.succeedAfterAttempt = succeedAfterAttempt
    }

    func handle(_ urls: [URL]) -> Set<URL> {
        attemptCount += 1
        return attemptCount >= succeedAfterAttempt ? Set(urls) : []
    }

    func record(error: String) {
        errors.append(error)
    }
}

private func eventually(
    timeout: Duration = .seconds(1),
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}

private func renderFloatPixels(_ image: CIImage, extent: CGRect) -> [Float] {
    let width = Int(extent.width)
    let height = Int(extent.height)
    var pixels = [Float](repeating: 0, count: width * height * 4)
    let context = CIContext(options: [.workingColorSpace: NSNull()])
    context.render(
        image,
        toBitmap: &pixels,
        rowBytes: width * 4 * MemoryLayout<Float>.size,
        bounds: extent,
        format: .RGBAf,
        colorSpace: nil
    )
    return pixels
}

private func opticalStrengthRecipe(
    diffusionAmount: Double = 0,
    halationAmount: Double = 0
) -> FilmRecipe {
    FilmRecipe(
        id: "optical-strength-test",
        name: "Optical Strength Test",
        lightShaping: .init(isEnabled: false),
        diffusion: .init(isEnabled: diffusionAmount > 0, amount: diffusionAmount, bloom: 0.65),
        halation: .init(isEnabled: halationAmount > 0, amount: halationAmount, spillRadius: 0.5),
        grain: .init(isEnabled: false)
    )
}

private func grainTestRecipe(chroma: Double) -> FilmRecipe {
    FilmRecipe(
        id: "grain-test-\(chroma)",
        name: "Grain Test",
        lightShaping: .init(isEnabled: false),
        diffusion: .init(isEnabled: false),
        halation: .init(isEnabled: false),
        grain: .init(
            amount: 0.5,
            particleSizeMicrons: 10,
            chroma: chroma,
            shadowResponse: 0.72,
            highlightResponse: 0.28,
            seed: 1234
        )
    )
}

private func channelSpread(_ pixels: [Float]) -> Float {
    guard pixels.count >= 3 else { return 0 }
    return max(pixels[0], max(pixels[1], pixels[2]))
        - min(pixels[0], min(pixels[1], pixels[2]))
}

private func colorDistance(_ lhs: [Float], _ rhs: [Float]) -> Float {
    guard lhs.count >= 3, rhs.count >= 3 else { return 0 }
    let red = lhs[0] - rhs[0]
    let green = lhs[1] - rhs[1]
    let blue = lhs[2] - rhs[2]
    return sqrt(red * red + green * green + blue * blue)
}

private func normalizedChroma(_ pixels: [Float]) -> Float {
    guard pixels.count >= 3 else { return 0 }
    let luminance = max(
        0.000_001,
        0.2126 * pixels[0] + 0.7152 * pixels[1] + 0.0722 * pixels[2]
    )
    return channelSpread(pixels) / luminance
}

private func pixelLuminance(_ pixels: [Float]) -> Float {
    guard pixels.count >= 3 else { return 0 }
    return 0.2627002 * pixels[0] + 0.6779981 * pixels[1] + 0.0593017 * pixels[2]
}

private func meanChromaEnergy(_ pixels: [Float]) -> Double {
    var total = 0.0
    var count = 0
    for index in stride(from: 0, to: pixels.count, by: 4) {
        let red = Double(pixels[index])
        let green = Double(pixels[index + 1])
        let blue = Double(pixels[index + 2])
        let redGreen = red - green
        let blueGreen = blue - green
        total += redGreen * redGreen + blueGreen * blueGreen
        count += 1
    }
    return total / Double(max(1, count))
}
