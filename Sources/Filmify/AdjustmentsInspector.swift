import FilmifyCore
import SwiftUI

struct AdjustmentsInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Adjustments")
                    .font(.title2.weight(.semibold))

                LightShapingCard(settings: $model.recipe.lightShaping, reset: model.resetLightShaping)
                DiffusionCard(settings: $model.recipe.diffusion, reset: model.resetDiffusion)
                HalationCard(settings: $model.recipe.halation, reset: model.resetHalation)
                GrainCard(
                    settings: $model.recipe.grain,
                    reset: model.resetGrain,
                    randomize: model.randomizeGrain
                )
            }
            .padding(16)
        }
        .onChange(of: model.recipe) { _, _ in
            model.schedulePreview()
        }
    }
}

private struct LightShapingCard: View {
    @Binding var settings: LightShapingSettings
    let reset: () -> Void

    var body: some View {
        EffectCard(
            title: "Spotlight",
            symbol: "circle.lefthalf.filled",
            tint: .orange,
            enabled: $settings.isEnabled,
            reset: reset
        ) {
            ParameterSlider("Amount", value: $settings.amountStops, range: 0 ... LightShapingSettings.maximumAmount)
            ParameterSlider("Focus", value: $settings.focus, range: 0 ... 1)
        } advanced: {
            ParameterSlider("Pop", value: $settings.pop, range: 0 ... 1)
            ParameterSlider("Bias", value: $settings.bias, range: 0 ... 1)
            ParameterSlider("Roundness", value: $settings.roundness, range: 0 ... 1)
            FocusPad(title: "Center", x: $settings.centerX, y: $settings.centerY)
        }
    }
}

private struct DiffusionCard: View {
    @Binding var settings: DiffusionSettings
    let reset: () -> Void

    var body: some View {
        EffectCard(
            title: "Diffusion",
            symbol: "circle.dotted",
            tint: .indigo,
            enabled: $settings.isEnabled,
            reset: reset
        ) {
            ParameterSlider("Amount", value: $settings.amount, range: 0 ... DiffusionSettings.maximumAmount)
            ParameterSlider("Bloom", value: $settings.bloom, range: 0 ... 1)
        } advanced: {
            ParameterSlider("Veil", value: $settings.veil, range: 0 ... 0.5)
            ParameterSlider("Source Bias", value: $settings.sourceBias, range: 0 ... 1)
            ParameterSlider("Warmth", value: $settings.warmth, range: -1 ... 1)
            FocusPad(title: "Focus", x: $settings.focusX, y: $settings.focusY)
        }
    }
}

private struct HalationCard: View {
    @Binding var settings: HalationSettings
    let reset: () -> Void

    var body: some View {
        EffectCard(
            title: "Halation",
            symbol: "sun.horizon",
            tint: .red,
            enabled: $settings.isEnabled,
            reset: reset
        ) {
            ParameterSlider("Amount", value: $settings.amount, range: 0 ... HalationSettings.maximumAmount)
            ParameterSlider("Spill Radius", value: $settings.spillRadius, range: 0 ... 1)
        } advanced: {
            ParameterSlider("Tail", value: $settings.tail, range: 0 ... 1)
            ParameterSlider("Color Shift", value: $settings.colorShift, range: 0 ... 1)
            ParameterSlider("Saturation", value: $settings.saturation, range: 0 ... 1)
            ParameterSlider("Green Leakage", value: $settings.greenLeakage, range: 0 ... 0.5)
        }
    }
}

private struct GrainCard: View {
    @Binding var settings: GrainSettings
    let reset: () -> Void
    let randomize: () -> Void

    var body: some View {
        EffectCard(
            title: "Film Grain",
            symbol: "aqi.medium",
            tint: .mint,
            enabled: $settings.isEnabled,
            reset: reset
        ) {
            ParameterSlider("Amount", value: $settings.amount, range: 0 ... GrainSettings.maximumAmount)
            ParameterSlider("Particle Size", value: $settings.particleSizeMicrons, range: 3 ... 22, suffix: "µm", decimals: 1)
        } advanced: {
            ParameterSlider("Acutance", value: $settings.acutance, range: 0 ... 1)
            ParameterSlider("Size Variation", value: $settings.sizeVariation, range: 0 ... 1)
            ParameterSlider("Chroma", value: $settings.chroma, range: 0 ... 1)
            ParameterSlider("Shadow Response", value: $settings.shadowResponse, range: 0 ... 1)
            ParameterSlider("Highlight Response", value: $settings.highlightResponse, range: 0 ... 1)
            ParameterSlider("Virtual Gate", value: $settings.virtualGateWidthMillimeters, range: 8 ... 70, suffix: "mm", decimals: 1)

            Button("New Grain Pattern", systemImage: "dice", action: randomize)
                .buttonStyle(.borderless)
        }
    }
}

private struct EffectCard<Primary: View, Advanced: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @Binding var enabled: Bool
    let reset: () -> Void
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let advanced: () -> Advanced

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .frame(width: 20)
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Reset", systemImage: "arrow.counterclockwise", action: reset)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Reset \(title)")
                Toggle("Enable \(title)", isOn: $enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            VStack(spacing: 9) {
                primary()
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.45)

            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text("More")
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.caption)
            .disabled(!enabled)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                VStack(spacing: 9) {
                    advanced()
                }
                .disabled(!enabled)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(13)
        .background(.quaternary.opacity(0.34), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ParameterSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var suffix = ""
    var decimals = 2

    init(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        suffix: String = "",
        decimals: Int = 2
    ) {
        self.title = title
        _value = value
        self.range = range
        self.suffix = suffix
        self.decimals = decimals
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(formattedValue)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            Slider(value: $value, in: range)
                .tint(.accentColor)
        }
    }

    private var formattedValue: String {
        let number = value.formatted(.number.precision(.fractionLength(decimals)))
        return suffix.isEmpty ? number : "\(number) \(suffix)"
    }
}

private struct FocusPad: View {
    let title: String
    @Binding var x: Double
    @Binding var y: Double

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.black.opacity(0.12))
                    Circle()
                        .fill(.white)
                        .shadow(radius: 1)
                        .frame(width: 7, height: 7)
                        .position(x: x * proxy.size.width, y: y * proxy.size.height)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            x = min(1, max(0, value.location.x / proxy.size.width))
                            y = min(1, max(0, value.location.y / proxy.size.height))
                        }
                )
            }
            .frame(width: 44, height: 30)
        }
        .font(.caption)
    }
}
