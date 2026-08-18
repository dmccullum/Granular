import SwiftUI

struct DropModeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 15) {
                Image(systemName: model.isDropTargeted ? "arrow.down.circle.fill" : "photo.on.rectangle.angled")
                    .font(.system(size: 48, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .contentTransition(.symbolEffect(.replace))

                VStack(spacing: 4) {
                    Text("Drop images to Granular")
                        .font(.title2.weight(.semibold))
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("They’ll be processed immediately with")
                            .foregroundStyle(.secondary)
                        RecipeMenu(showsRecipeName: true)
                    }
                }

                Button("Choose Images…") {
                    model.chooseImagesForDroplet()
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
            .contentShape(Rectangle())
            .overlay {
                if model.isDropTargeted {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.tint, style: StrokeStyle(lineWidth: 3, dash: [9, 6]))
                        .padding(14)
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                Task { await model.processInstantly(urls) }
                return !urls.isEmpty
            } isTargeted: { targeted in
                withAnimation(.easeOut(duration: 0.16)) {
                    model.isDropTargeted = targeted
                }
            }

            DropletStatusBar()
        }
        .background(.background)
    }
}

private struct DropletStatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(model.dropOutputFolder?.lastPathComponent ?? "Choose output folder")
                    .lineLimit(1)
                Button("Change…") {
                    model.chooseDropOutputFolder()
                }
                .buttonStyle(.link)
            }

            Spacer(minLength: 20)

            if let last = model.jobs.first {
                CompactJobStatus(job: last)
            } else {
                Text(model.statusMessage)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

struct CompactJobStatus: View {
    @Environment(AppModel.self) private var model
    let job: ProcessingJob

    var body: some View {
        HStack(spacing: 6) {
            switch job.state {
            case .queued:
                Image(systemName: "clock")
            case .processing:
                ProgressView().controlSize(.small)
            case .finished:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            Text(job.sourceURL.lastPathComponent)
                .lineLimit(1)
            switch job.state {
            case .finished(let outputURL):
                Button {
                    model.reveal(outputURL)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("Show in Finder")
                .help("Show in Finder")
            default:
                Text(job.state.label)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
