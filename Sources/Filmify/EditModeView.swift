import AppKit
import FilmifyCore
import Observation
import SwiftUI

@MainActor
@Observable
final class ViewerZoomController {
    private(set) var scale = 1.0
    private(set) var fitScale = 1.0
    private(set) var isFitted = true

    func updateFitScale(_ scale: Double) {
        fitScale = ViewerZoomMath.clampedScale(scale)
        if isFitted {
            self.scale = fitScale
        }
    }

    func zoomIn() {
        setManualScale(ViewerZoomMath.zoomedIn(from: scale))
    }

    func zoomOut() {
        setManualScale(ViewerZoomMath.zoomedOut(from: scale))
    }

    func setManualScale(_ scale: Double) {
        isFitted = false
        self.scale = ViewerZoomMath.clampedScale(scale)
    }

    func fit() {
        isFitted = true
        scale = fitScale
    }

    func resetForNewImage() {
        fit()
    }
}

private struct FilmifyViewerZoomControllerKey: FocusedValueKey {
    typealias Value = ViewerZoomController
}

extension FocusedValues {
    var filmifyViewerZoomController: ViewerZoomController? {
        get { self[FilmifyViewerZoomControllerKey.self] }
        set { self[FilmifyViewerZoomControllerKey.self] = newValue }
    }
}

struct EditModeView: View {
    @Environment(AppModel.self) private var model
    @State private var zoomController = ViewerZoomController()

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ZStack {
                    if let image = model.previewImage {
                        ZoomableImageCanvas(
                            image: image,
                            imagePixelSize: model.sourcePreview?.pixelDimensions ?? image.pixelDimensions,
                            zoomController: zoomController
                        )
                        .id(model.selectedSourceURL)

                        VStack {
                            HStack {
                                Spacer()
                                if model.sourcePreview != nil, model.processedPreview != nil {
                                    Button {
                                        model.showOriginal.toggle()
                                    } label: {
                                        Label(
                                            model.showOriginal ? "Original" : "Filmify",
                                            systemImage: model.showOriginal ? "eye.slash" : "eye"
                                        )
                                    }
                                    .buttonStyle(.glass)
                                }
                            }
                            Spacer()
                            ZoomControls(zoomController: zoomController)
                        }
                        .padding(16)
                    } else {
                        EditorEmptyState()
                    }

                    if model.isRenderingPreview {
                        ProgressView()
                            .controlSize(.small)
                            .padding(9)
                            .background(.regularMaterial, in: Circle())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .dropDestination(for: URL.self) { urls, _ in
                    model.openForEditing(urls)
                    return !urls.isEmpty
                } isTargeted: { targeted in
                    model.isDropTargeted = targeted
                }

                EditorStatusBar()
            }

            AdjustmentsInspector()
                .environment(model)
                .frame(width: 310)
                .background(.bar)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .focusedSceneValue(\.filmifyViewerZoomController, zoomController)
        .onChange(of: model.selectedSourceURL) { _, _ in
            zoomController.resetForNewImage()
        }
    }
}

private struct ZoomableImageCanvas: View {
    let image: NSImage
    let imagePixelSize: CGSize
    let zoomController: ViewerZoomController
    @State private var gestureStartZoom = 1.0
    @State private var isMagnifying = false
    @State private var panOffset = CGSize.zero
    @State private var dragStartOffset: CGSize?

    var body: some View {
        GeometryReader { proxy in
            let fitScale = min(
                ViewerZoomMath.fitScale(
                    imageWidth: Double(imagePixelSize.width),
                    imageHeight: Double(imagePixelSize.height),
                    viewportWidth: Double(proxy.size.width),
                    viewportHeight: Double(proxy.size.height)
                ),
                ViewerZoomMath.maximumScale
            )
            let displaySize = CGSize(
                width: imagePixelSize.width * CGFloat(zoomController.scale),
                height: imagePixelSize.height * CGFloat(zoomController.scale)
            )
            let canPan = displaySize.width > proxy.size.width || displaySize.height > proxy.size.height

            ZStack {
                Color.clear
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: displaySize.width, height: displaySize.height)
                    .shadow(color: .black.opacity(0.28), radius: 14, y: 5)
                    .offset(panOffset)
                    .contentShape(Rectangle())
                    .gesture(panGesture(displaySize: displaySize, viewportSize: proxy.size, canPan: canPan))
                    .onContinuousHover { phase in
                        switch phase {
                        case .active:
                            (canPan ? NSCursor.openHand : NSCursor.arrow).set()
                        case .ended:
                            NSCursor.arrow.set()
                        }
                    }
            }
            .clipped()
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        if !isMagnifying {
                            gestureStartZoom = zoomController.scale
                            isMagnifying = true
                        }
                        zoomController.setManualScale(gestureStartZoom * value.magnification)
                    }
                    .onEnded { _ in
                        isMagnifying = false
                    }
            )
            .onChange(of: fitScale, initial: true) { _, newFitScale in
                zoomController.updateFitScale(newFitScale)
                if zoomController.isFitted {
                    panOffset = .zero
                }
            }
            .onChange(of: zoomController.scale) { _, _ in
                if zoomController.isFitted {
                    panOffset = .zero
                } else {
                    panOffset = clampedOffset(
                        panOffset,
                        displaySize: displaySize,
                        viewportSize: proxy.size
                    )
                }
            }
            .onDisappear {
                NSCursor.arrow.set()
            }
        }
    }

    private func panGesture(displaySize: CGSize, viewportSize: CGSize, canPan: Bool) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard canPan else { return }
                if dragStartOffset == nil {
                    dragStartOffset = panOffset
                }
                let start = dragStartOffset ?? .zero
                panOffset = clampedOffset(
                    CGSize(
                        width: start.width + value.translation.width,
                        height: start.height + value.translation.height
                    ),
                    displaySize: displaySize,
                    viewportSize: viewportSize
                )
                NSCursor.closedHand.set()
            }
            .onEnded { _ in
                dragStartOffset = nil
                (canPan ? NSCursor.openHand : NSCursor.arrow).set()
            }
    }

    private func clampedOffset(
        _ proposed: CGSize,
        displaySize: CGSize,
        viewportSize: CGSize
    ) -> CGSize {
        CGSize(
            width: CGFloat(ViewerZoomMath.clampedPanOffset(
                Double(proposed.width),
                displayLength: Double(displaySize.width),
                viewportLength: Double(viewportSize.width)
            )),
            height: CGFloat(ViewerZoomMath.clampedPanOffset(
                Double(proposed.height),
                displayLength: Double(displaySize.height),
                viewportLength: Double(viewportSize.height)
            ))
        )
    }
}

private struct ZoomControls: View {
    let zoomController: ViewerZoomController

    var body: some View {
        HStack(spacing: 8) {
            Button {
                zoomController.zoomOut()
            } label: {
                ZoomButtonLabel(systemImage: "minus", width: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zoom Out")

            Slider(
                value: Binding(
                    get: { ViewerZoomMath.sliderPosition(forScale: zoomController.scale) },
                    set: { zoomController.setManualScale(ViewerZoomMath.scale(forSliderPosition: $0)) }
                ),
                in: 0 ... 1
            )
                .accessibilityLabel("Zoom")
                .accessibilityValue(Text(zoomController.scale, format: .percent.precision(.fractionLength(0))))
                .frame(width: 110)

            Button {
                zoomController.zoomIn()
            } label: {
                ZoomButtonLabel(systemImage: "plus", width: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zoom In")

            Divider().frame(height: 14)

            HStack(spacing: 7) {
                Button {
                    zoomController.fit()
                } label: {
                    ZoomButtonLabel("Fit", width: 38)
                }
                .buttonStyle(.plain)

                Text(zoomController.scale, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        }
    }
}

private struct ZoomButtonLabel: View {
    private let title: String?
    private let systemImage: String?
    private let width: CGFloat

    init(_ title: String, width: CGFloat) {
        self.title = title
        self.systemImage = nil
        self.width = width
    }

    init(systemImage: String, width: CGFloat) {
        self.title = nil
        self.systemImage = systemImage
        self.width = width
    }

    var body: some View {
        Group {
            if let systemImage {
                Image(systemName: systemImage)
            } else if let title {
                Text(title)
            }
        }
        .frame(width: width, height: 22)
        .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
    }
}

private extension NSImage {
    var pixelDimensions: CGSize {
        guard let representation = representations.max(by: {
            ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh)
        }), representation.pixelsWide > 0, representation.pixelsHigh > 0 else {
            return size
        }
        return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
    }
}

private struct EditorEmptyState: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 50, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            Text("Open an image to begin")
                .font(.title2.weight(.semibold))
            Text("Adjust the recipe with a live preview, then export when it feels right.")
                .foregroundStyle(.secondary)
            Button("Open Image…") {
                model.chooseImageForEditing()
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(40)
    }
}

private struct EditorStatusBar: View {
    @Environment(AppModel.self) private var model
    @State private var isHoveringSource = false

    var body: some View {
        HStack(spacing: 12) {
            if let source = model.selectedSourceURL {
                HStack(spacing: 5) {
                    Button {
                        model.closeEditorImage()
                    } label: {
                        ZStack {
                            Image(systemName: "photo")
                                .font(.system(size: 12))
                                .opacity(isHoveringSource ? 0 : 1)

                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .opacity(isHoveringSource ? 1 : 0)
                        }
                        .frame(width: 17, height: 17)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Close Image")
                    .help("Close image")

                    Text(source.lastPathComponent)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onHover { isHovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isHoveringSource = isHovering
                    }
                }
            } else {
                Text("No image open")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 20)

            Button("Export…") {
                model.exportEditedImage()
            }
            .buttonStyle(.glassProminent)
            .disabled(model.selectedSourceURL == nil || model.isExporting)
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
