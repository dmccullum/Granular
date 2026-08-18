import GranularCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = false

    var body: some View {
        @Bindable var model = model

        Form {
            Section("Output") {
                Picker("Format", selection: $model.outputOptions.format) {
                    ForEach(OutputFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }

                LabeledContent("Quality") {
                    HStack {
                        Slider(value: $model.outputOptions.compressionQuality, in: 0.6 ... 1)
                            .frame(width: 180)
                        Text(model.outputOptions.compressionQuality, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                .disabled(model.outputOptions.format == .png || model.outputOptions.format == .tiff)

                Toggle("Remove GPS location metadata", isOn: $model.outputOptions.stripLocationMetadata)
            }

            Section("Watched Folder") {
                SettingsFolderRow(title: "Incoming", url: model.watchedInputFolder) {
                    model.chooseWatchedInputFolder()
                }
                SettingsFolderRow(title: "Finished", url: model.watchedOutputFolder) {
                    model.chooseWatchedOutputFolder()
                }

                LabeledContent("Automation") {
                    if model.isWatching {
                        Button("Pause Watching", systemImage: "pause.fill") {
                            model.stopWatching()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Start Watching", systemImage: "play.fill") {
                            model.startWatching()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.watchedInputFolder == nil || model.watchedOutputFolder == nil)
                    }
                }

                Text("Files are processed with the currently selected recipe after they finish copying. Granular remains available in the menu bar while watching.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label(
                    model.watchErrorMessage ?? model.watchStatusMessage,
                    systemImage: model.watchErrorMessage == nil
                        ? (model.isWatching ? "checkmark.circle.fill" : "pause.circle")
                        : "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(model.watchErrorMessage == nil ? Color.secondary : Color.orange)
            }

            Section("Application") {
                Toggle("Launch Granular at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        model.setLaunchAtLogin(enabled)
                    }
            }

            Section {
                LabeledContent("Processing") {
                    Text("Apple Core Image · extended-linear color")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 560)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct SettingsFolderRow: View {
    let title: String
    let url: URL?
    let choose: () -> Void

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(url?.path(percentEncoded: false) ?? "Not selected")
                    .foregroundStyle(url == nil ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Choose…", action: choose)
            }
        }
    }
}
