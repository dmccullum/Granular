import CoreImage
import Foundation
import Testing
@testable import FilmifyCore

@Test func builtInRecipesHaveStableIdentifiersAndRanges() {
    #expect(FilmRecipe.builtIns.map(\.name) == ["Clean 120", "Classic 35", "Soft 16"])
    #expect(Set(FilmRecipe.builtIns.map(\.id)).count == FilmRecipe.builtIns.count)

    for recipe in FilmRecipe.builtIns {
        #expect((0 ... 1).contains(recipe.strength))
        #expect((0 ... 1).contains(recipe.lightShaping.amountStops))
        #expect((0 ... 1).contains(recipe.diffusion.amount))
        #expect((0 ... 1).contains(recipe.halation.amount))
        #expect((0 ... 1).contains(recipe.grain.amount))
        #expect(recipe.grain.particleSizeMicrons > 0)
        #expect(recipe.grain.virtualGateWidthMillimeters > 0)
    }
}

@Test func strengthScalesEffectAmountsWithoutChangingCharacterControls() {
    var recipe = FilmRecipe.classic35
    recipe.strength = 0.5
    let effective = recipe.effective

    #expect(effective.lightShaping.amountStops == recipe.lightShaping.amountStops * 0.5)
    #expect(effective.diffusion.amount == recipe.diffusion.amount * 0.5)
    #expect(effective.halation.amount == recipe.halation.amount * 0.5)
    #expect(effective.grain.amount == recipe.grain.amount * 0.5)
    #expect(effective.grain.particleSizeMicrons == recipe.grain.particleSizeMicrons)
}

@Test func classic35DefaultsMatchCalibratedRecipe() {
    let recipe = FilmRecipe.classic35

    #expect(recipe.lightShaping.amountStops == 0.25)
    #expect(recipe.diffusion.amount == 0.10)
    #expect(recipe.halation.amount == 0.25)
    #expect(recipe.grain.amount == 0.30)
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

@Test func normalizedClassic35AmountsMapToThePriorRendererStrengths() {
    let recipe = FilmRecipe.classic35

    #expect(FilmRenderer.mappedSpotlightAmount(recipe.lightShaping.amountStops) == 1.0)
    #expect(FilmRenderer.mappedOpticalAmount(recipe.diffusion.amount) == 0.20)
    #expect(FilmRenderer.mappedOpticalAmount(recipe.halation.amount) == 0.50)
    #expect(abs(FilmRenderer.mappedGrainAmount(recipe.grain.amount) - 1.80) < 0.000_001)
}

@Test func halationUsesNormalizedAmountsWithoutChangingRecipeStrengths() throws {
    #expect(HalationSettings.maximumAmount == 1)
    #expect(try #require(FilmRecipe.builtIns.first { $0.id == "clean-120" }).halation.amount == 0.10)
    #expect(FilmRecipe.classic35.halation.amount == 0.25)
    #expect(try #require(FilmRecipe.builtIns.first { $0.id == "soft-16" }).halation.amount == 0.40)
}

@Test func diffusionUsesNormalizedAmountsWithoutChangingRecipeStrengths() throws {
    #expect(DiffusionSettings.maximumAmount == 1)
    #expect(try #require(FilmRecipe.builtIns.first { $0.id == "clean-120" }).diffusion.amount == 0.10)
    #expect(FilmRecipe.classic35.diffusion.amount == 0.10)
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

@Test func viewerZoomUsesActualImageScaleAndFitGeometry() {
    let fit = ViewerZoomMath.fitScale(
        imageWidth: 4_000,
        imageHeight: 3_000,
        viewportWidth: 1_000,
        viewportHeight: 800
    )

    #expect(abs(fit - 0.238) < 0.000_001)
    #expect(ViewerZoomMath.zoomedIn(from: 1) == 1.25)
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

@Test func processingServiceWritesAReadableCollisionSafeOutput() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("FilmifyTests-\(UUID().uuidString)", isDirectory: true)
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

    #expect(outputURL.lastPathComponent == "frame — Filmify.png")
    #expect(FileManager.default.fileExists(atPath: outputURL.path))
    #expect(CIImage(contentsOf: outputURL)?.extent == sourceImage.extent)
}

@Test func watchedFolderRetriesFilesUntilProcessingSucceeds() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("FilmifyWatchTests-\(UUID().uuidString)", isDirectory: true)
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
        .appendingPathComponent("MissingFilmifyWatchFolder-\(UUID().uuidString)", isDirectory: true)
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
