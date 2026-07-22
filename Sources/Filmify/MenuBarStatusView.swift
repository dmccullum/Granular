import SwiftUI

struct MenuBarStatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: model.isWatching ? "drop.fill" : "drop")
                    .font(.title2)
                    .foregroundStyle(model.isWatching ? Color.green : Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.isWatching ? "Filmify is watching" : "Filmify is paused")
                        .font(.headline)
                    Text(model.watchErrorMessage ?? model.watchStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let incoming = model.watchedInputFolder {
                Label(incoming.path(percentEncoded: false), systemImage: "folder")
                    .font(.caption)
                    .lineLimit(1)
            }

            HStack {
                Button(model.isWatching ? "Pause" : "Resume") {
                    model.toggleWatching()
                }
                .disabled(model.watchedInputFolder == nil || model.watchedOutputFolder == nil)

                Button("Reveal Last") {
                    model.revealLastOutput()
                }
                .disabled(model.completedJobCount == 0)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
