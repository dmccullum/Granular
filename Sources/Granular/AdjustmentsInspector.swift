import AppKit
import DMKit
import GranularCore
import SwiftUI

/// The adjustments beside the canvas: one DMKit inspector card per effect,
/// in the order the renderer applies them.
struct AdjustmentsInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        // What each card's Reset puts back, and each slider's double-click.
        let defaults = model.currentRecipe

        ScrollView {
            VStack(alignment: .leading, spacing: DMLayout.inspectorSpacing) {
                HStack(spacing: 8) {
                    // The title keeps its line; a long recipe name gives way instead.
                    Text("Adjustments")
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 0)
                    RecipeMenu()
                }

                FilmToneCard(settings: $model.recipe.tone, defaults: defaults.tone, reset: model.resetTone)
                LightShapingCard(
                    settings: $model.recipe.lightShaping,
                    defaults: defaults.lightShaping,
                    reset: model.resetLightShaping
                )
                LensBlurCard(settings: $model.recipe.lensBlur, defaults: defaults.lensBlur, reset: model.resetLensBlur)
                DiffusionCard(settings: $model.recipe.diffusion, defaults: defaults.diffusion, reset: model.resetDiffusion)
                HalationCard(settings: $model.recipe.halation, defaults: defaults.halation, reset: model.resetHalation)
                LandscapeGlowCard(
                    settings: $model.recipe.landscapeGlow,
                    defaults: defaults.landscapeGlow,
                    reset: model.resetLandscapeGlow
                )
                GrainCard(
                    settings: $model.recipe.grain,
                    defaults: defaults.grain,
                    reset: model.resetGrain,
                    randomize: model.randomizeGrain
                )
            }
            .padding(DMLayout.inspectorPadding)
        }
        .onChange(of: model.recipe) { _, _ in
            model.recipeDidChange()
        }
    }
}

private struct FilmToneCard: View {
    @Environment(AppModel.self) private var model
    @Binding var settings: FilmToneSettings
    let defaults: FilmToneSettings
    let reset: () -> Void

    var body: some View {
        EffectCard(
            title: "Film Tone",
            enabled: $settings.isEnabled,
            reset: reset,
            showsAdvanced: false
        ) {
            StackedControl("Film Stock") {
                FilmStockPickerButton(stock: Binding {
                    settings.stock
                } set: { stock in
                    model.changeAdjustments("Film Stock") {
                        settings.stock = stock
                        // Choosing a stock is a request to see it.
                        if stock != .none {
                            settings.isEnabled = true
                        }
                    }
                })
            }
            ParameterSlider(
                "Stock Amount",
                value: $settings.stockAmount,
                default: defaults.stockAmount,
                range: 0 ... FilmToneSettings.maximumStockAmount,
                display: .strength
            )
                .disabled(settings.stock == .none)
                .opacity(settings.stock == .none ? 0.48 : 1)
            ParameterSlider(
                "Exposure",
                value: $settings.exposure,
                default: defaults.exposure,
                range: -2 ... 2,
                display: .exposure
            )
            ParameterSlider("Contrast", value: $settings.contrast, default: defaults.contrast, range: -1 ... 1)
            ParameterSlider("Saturation", value: $settings.saturation, default: defaults.saturation, range: -1 ... 1)
            ParameterSlider("Vibrance", value: $settings.vibrance, default: defaults.vibrance, range: -1 ... 1)
            ParameterSlider("Warmth", value: $settings.warmth, default: defaults.warmth, range: -1 ... 1)
        } advanced: {}
    }
}

private struct LightShapingCard: View {
    @Binding var settings: LightShapingSettings
    let defaults: LightShapingSettings
    let reset: () -> Void

    var body: some View {
        EffectCard(
            title: "Vignette",
            enabled: $settings.isEnabled,
            reset: reset
        ) {
            ParameterSlider(
                "Amount",
                value: $settings.amountStops,
                default: defaults.amountStops,
                range: 0 ... LightShapingSettings.maximumAmount,
                undoName: "Vignette Amount"
            )
            ParameterSlider(
                "Focus",
                value: $settings.focus,
                default: defaults.focus,
                range: 0 ... 1,
                undoName: "Vignette Focus"
            )
        } advanced: {
            ParameterSlider("Pop", value: $settings.pop, default: defaults.pop, range: 0 ... 1)
            ParameterSlider("Bias", value: $settings.bias, default: defaults.bias, range: 0 ... 1)
            ParameterSlider("Roundness", value: $settings.roundness, default: defaults.roundness, range: 0 ... 1)
            CenterControlRow(
                title: "Center",
                target: .vignette,
                x: $settings.centerX,
                y: $settings.centerY
            )
        }
    }
}

private struct LensBlurCard: View {
    @Binding var settings: LensBlurSettings
    let defaults: LensBlurSettings
    let reset: () -> Void

    var body: some View {
        EffectCard(
            title: "Lens Blur",
            enabled: $settings.isEnabled,
            reset: reset
        ) {
            ParameterSlider(
                "Amount",
                value: $settings.amount,
                default: defaults.amount,
                range: 0 ... LensBlurSettings.maximumAmount,
                undoName: "Lens Blur Amount"
            )
            ParameterSlider("Falloff", value: $settings.falloff, default: defaults.falloff, range: 0 ... 1)
        } advanced: {
            ParameterSlider(
                "Chromatic Aberration",
                value: $settings.colorFringing,
                default: defaults.colorFringing,
                range: 0 ... 1
            )
            CenterControlRow(
                title: "Focus",
                target: .lensBlur,
                x: $settings.focusX,
                y: $settings.focusY
            )
        }
    }
}

private struct DiffusionCard: View {
    @Binding var settings: DiffusionSettings
    let defaults: DiffusionSettings
    let reset: () -> Void

    var body: some View {
        EffectCard(
            title: "Diffusion",
            enabled: $settings.isEnabled,
            reset: reset
        ) {
            ParameterSlider(
                "Amount",
                value: $settings.amount,
                default: defaults.amount,
                range: 0 ... DiffusionSettings.maximumAmount,
                undoName: "Diffusion Amount"
            )
            ParameterSlider("Bloom", value: $settings.bloom, default: defaults.bloom, range: 0 ... 1)
        } advanced: {
            ParameterSlider("Veil", value: $settings.veil, default: defaults.veil, range: 0 ... 0.5)
            ParameterSlider("Source Bias", value: $settings.sourceBias, default: defaults.sourceBias, range: 0 ... 1)
            ParameterSlider(
                "Warmth",
                value: $settings.warmth,
                default: defaults.warmth,
                range: -1 ... 1,
                undoName: "Diffusion Warmth"
            )
        }
    }
}

private struct HalationCard: View {
    @Binding var settings: HalationSettings
    let defaults: HalationSettings
    let reset: () -> Void

    var body: some View {
        EffectCard(
            title: "Halation",
            enabled: $settings.isEnabled,
            reset: reset
        ) {
            ParameterSlider(
                "Amount",
                value: $settings.amount,
                default: defaults.amount,
                range: 0 ... HalationSettings.maximumAmount,
                undoName: "Halation Amount"
            )
            ParameterSlider(
                "Spill Radius",
                value: $settings.spillRadius,
                default: defaults.spillRadius,
                range: 0 ... 1
            )
        } advanced: {
            ParameterSlider("Tail", value: $settings.tail, default: defaults.tail, range: 0 ... 1)
            ParameterSlider("Color Shift", value: $settings.colorShift, default: defaults.colorShift, range: 0 ... 1)
            ParameterSlider(
                "Saturation",
                value: $settings.saturation,
                default: defaults.saturation,
                range: 0 ... 1,
                undoName: "Halation Saturation"
            )
            ParameterSlider(
                "Green Leakage",
                value: $settings.greenLeakage,
                default: defaults.greenLeakage,
                range: 0 ... 0.5
            )
        }
    }
}

private struct LandscapeGlowCard: View {
    @Binding var settings: LandscapeGlowSettings
    let defaults: LandscapeGlowSettings
    let reset: () -> Void

    var body: some View {
        EffectCard(
            title: "Landscape Glow",
            enabled: $settings.isEnabled,
            reset: reset
        ) {
            ParameterSlider(
                "Amount",
                value: $settings.amount,
                default: defaults.amount,
                range: 0 ... LandscapeGlowSettings.maximumAmount,
                undoName: "Glow Amount"
            )
            ParameterSlider("Glow Size", value: $settings.glowSize, default: defaults.glowSize, range: 0 ... 1)
        } advanced: {
            ParameterSlider(
                "Shadow Protection",
                value: $settings.shadowProtection,
                default: defaults.shadowProtection,
                range: 0 ... 1
            )
            ParameterSlider("Detail", value: $settings.detail, default: defaults.detail, range: 0 ... 1)
        }
    }
}

private struct GrainCard: View {
    @Binding var settings: GrainSettings
    let defaults: GrainSettings
    let reset: () -> Void
    let randomize: () -> Void

    var body: some View {
        EffectCard(
            title: "Film Grain",
            enabled: $settings.isEnabled,
            reset: reset
        ) {
            ParameterSlider(
                "Amount",
                value: $settings.amount,
                default: defaults.amount,
                range: 0 ... GrainSettings.maximumAmount,
                undoName: "Grain Amount"
            )
            ParameterSlider(
                "Grain Size",
                value: $settings.grainSize,
                default: defaults.grainSize,
                range: 2 ... GrainSettings.maximumGrainSize,
                display: .grainSize
            )
        } advanced: {
            ParameterSlider("Acutance", value: $settings.acutance, default: defaults.acutance, range: 0 ... 1)
            ParameterSlider(
                "Size Variation",
                value: $settings.sizeVariation,
                default: defaults.sizeVariation,
                range: 0 ... 1
            )
            ParameterSlider("Chroma", value: $settings.chroma, default: defaults.chroma, range: 0 ... 1)
            ParameterSlider(
                "Shadow Response",
                value: $settings.shadowResponse,
                default: defaults.shadowResponse,
                range: 0 ... 1
            )
            ParameterSlider(
                "Highlight Response",
                value: $settings.highlightResponse,
                default: defaults.highlightResponse,
                range: 0 ... 1
            )
            Button("New Grain Pattern", systemImage: "dice", action: randomize)
                .buttonStyle(.borderless)
        }
    }
}

/// One effect: its name, Reset and on/off switch in the header, its main
/// sliders, and the rest under More. Switched off, it folds to its header.
private struct EffectCard<Primary: View, Advanced: View>: View {
    @Environment(AppModel.self) private var model

    let title: String
    @Binding var enabled: Bool
    let reset: () -> Void
    var showsAdvanced = true
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let advanced: () -> Advanced

    @State private var isExpanded = false

    var body: some View {
        InspectorCard(title) {
            CardResetButton("Reset \(title)") {
                model.changeAdjustments("Reset \(title)", reset)
            }
            Toggle("Enable \(title)", isOn: animatedEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        } content: {
            if enabled {
                VStack(alignment: .leading, spacing: DMLayout.cardSpacing) {
                    primary()

                    if showsAdvanced {
                        MoreButton(isExpanded: $isExpanded)
                        if isExpanded {
                            advanced()
                        }
                    }
                }
            }
        }
        // Content folding in or out stays inside the card while it resizes.
        .clipShape(RoundedRectangle(cornerRadius: DMRadius.medium, style: .continuous))
    }

    private var animatedEnabled: Binding<Bool> {
        Binding {
            enabled
        } set: { newValue in
            withDMAnimation(.smooth) {
                model.changeAdjustments(newValue ? "Enable \(title)" : "Disable \(title)") {
                    enabled = newValue
                }
            }
        }
    }
}

/// Shows or hides an effect's less-used sliders.
private struct MoreButton: View {
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withDMAnimation(.smooth) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .fontWeight(.semibold)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
                Text("More")
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

/// One adjustment on DMKit's `InspectorSlider`: double-click it or its name to
/// put back the recipe's own value, which a tick marks under the track; click
/// the value to type an exact one. A drag, a run of arrow-key nudges, a typed
/// value or a reset is one step on Edit ▸ Undo.
private struct ParameterSlider: View {
    @Environment(AppModel.self) private var model

    let title: String
    @Binding var value: Double
    let defaultValue: Double
    let range: ClosedRange<Double>
    let format: SliderValueFormat
    /// What Edit ▸ Undo calls a change, where the title alone is ambiguous.
    let undoName: String

    init(
        _ title: String,
        value: Binding<Double>,
        default defaultValue: Double,
        range: ClosedRange<Double>,
        display: ParameterDisplay? = nil,
        undoName: String? = nil
    ) {
        self.title = title
        _value = value
        self.defaultValue = defaultValue
        self.range = range
        self.format = SliderValueFormat(display ?? .proportion(in: range))
        self.undoName = undoName ?? title
    }

    var body: some View {
        InspectorSlider(
            title,
            value: value,
            in: range,
            default: defaultValue,
            format: format,
            preview: { newValue in
                // Every change joins the step open for this slider; `commit`
                // closes it when the drag, nudges or typing end.
                model.changeAdjustments(actionName(for: newValue), coalescingKey: undoKey) {
                    value = newValue
                }
            },
            commit: {
                model.endCoalescedChanges(undoKey)
            }
        )
    }

    /// One slider's drags and nudges each make a single undo step.
    private var undoKey: String {
        "slider \(undoName)"
    }

    /// “Reset Exposure” for a change straight to the recipe's value, otherwise “Exposure”.
    private func actionName(for newValue: Double) -> String {
        // TODO(DMKit): InspectorSlider doesn't say whether a change is a reset, a drag,
        // a nudge or a typed value. A first change that lands exactly on the default,
        // with no drag or nudge under way, is taken to be a reset.
        let isContinuingStep = model.openUndoStep?.key == AnyHashable(undoKey)
        return newValue == defaultValue && !isContinuingStep ? "Reset \(undoName)" : undoName
    }
}

extension SliderValueFormat {
    /// How GranularCore's display for an adjustment reads in DMKit's slider:
    /// the same scale, sign, decimals, unit and arrow-key step.
    init(_ display: ParameterDisplay) {
        self.init(
            scale: display.scale,
            fractionDigits: display.fractionDigits,
            isSigned: display.isSigned,
            unit: Unit(display.unit),
            step: display.step
        )
    }
}

extension SliderValueFormat.Unit {
    init(_ unit: ParameterDisplay.Unit) {
        switch unit {
        case .none: self = SliderValueFormat.Unit.none
        case .percent: self = .percent
        case .stops: self = .stops
        case .micrometers: self = .micrometers
        }
    }

    /// Grain size, in microns on a 35mm frame.
    static let micrometers = SliderValueFormat.Unit(
        symbol: "µm",
        spokenName: "micrometers",
        spellings: ["µm", "μm", "um", "microns", "micron"]
    )
}

/// The point an effect centers on, set by clicking the image.
private struct CenterControlRow: View {
    @Environment(AppModel.self) private var model

    let title: String
    let target: EffectCenterTarget
    @Binding var x: Double
    @Binding var y: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer()

            HStack(spacing: 7) {
                Text("X \(percentage(x))")
                Text("Y \(percentage(y))")
            }
            .monospacedDigit()
            .foregroundStyle(.secondary)

            Button {
                withDMAnimation(.snappy) {
                    model.showOriginal = false
                    model.activeCenterTarget = isActive ? nil : target
                }
            } label: {
                Image(systemName: isActive ? "scope" : "viewfinder")
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(isActive ? .accentColor : nil)
            .disabled(model.selectedSourceURL == nil)
            .help(isActive ? "Finish adjusting \(title.lowercased())" : "Adjust \(title.lowercased()) on image")
            .accessibilityLabel(isActive ? "Finish \(target.title) center adjustment" : "Adjust \(target.title) center on image")
        }
    }

    private var isActive: Bool {
        model.activeCenterTarget == target
    }

    private func percentage(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}

// MARK: - Shared with other panels

/// Ends typing in a field when the next click lands anywhere else, which
/// AppKit doesn't do by itself for clicks on non-focusable content.
struct EndEditingOnOutsideClick: NSViewRepresentable {
    func makeNSView(context: Context) -> WatchingView { WatchingView() }
    func updateNSView(_ view: WatchingView, context: Context) {}

    final class WatchingView: NSView {
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                if !self.bounds.contains(point) {
                    // Giving up first responder commits the field.
                    window.makeFirstResponder(nil)
                }
                return event
            }
        }
    }
}

/// The faint fill behind inspector cards and fields. Increase Contrast makes
/// it firmer and gives it an edge.
private struct CardBackground<S: InsettableShape>: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    let shape: S
    let opacity: Double
    let isEdged: Bool

    func body(content: Content) -> some View {
        let isIncreased = contrast == .increased
        content
            .background(.quaternary.opacity(isIncreased ? min(1, opacity * 2.5) : opacity), in: shape)
            .overlay {
                if isIncreased, isEdged {
                    shape.strokeBorder(Color.primary.opacity(0.45), lineWidth: 1)
                }
            }
    }
}

extension View {
    /// `isEdged` false leaves the edge to a tile that draws its own.
    func cardBackground(in shape: some InsettableShape, opacity: Double = 0.34, isEdged: Bool = true) -> some View {
        modifier(CardBackground(shape: shape, opacity: opacity, isEdged: isEdged))
    }
}

/// The edge of a tile in a picker grid, firmer with Increase Contrast.
func tileEdgeColor(isSelected: Bool, contrast: ColorSchemeContrast) -> Color {
    if isSelected { return .accentColor }
    return Color.primary.opacity(contrast == .increased ? 0.45 : 0.1)
}
