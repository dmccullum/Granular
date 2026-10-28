import AppKit
import DMKit
import SwiftUI

/// File menu: opening, exporting, sharing, saving and revealing images.
///
/// It reads nothing that changes while the recipe is adjusted, so a slider
/// drag doesn’t rebuild the menu bar with every step.
struct FileCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(model.operationMode == .drop ? "Process Images…" : "Open Image…") {
                model.chooseImages()
            }
            .keyboardShortcut("o")

            // Recent images always open in Edit mode, whichever mode is showing.
            OpenRecentMenu(recents: model.recentImages) { url in
                model.openForEditing([url])
            }

            if model.operationMode == .edit, model.selectedSourceURL != nil {
                Button("Close Image") {
                    model.closeEditorImage()
                }
            }

            Divider()

            Button("Choose Instant Output Folder…") {
                Task { await model.chooseDropOutputFolder() }
            }
            if model.operationMode == .edit {
                Button("Export…") {
                    model.exportEditedImage()
                }
                .keyboardShortcut("e")
                .disabled(model.selectedSourceURL == nil || model.isExporting)

                if let source = model.selectedSourceURL {
                    ShareLink(
                        item: model.processedImageItem(for: source),
                        preview: SharePreview(source.deletingPathExtension().lastPathComponent)
                    ) {
                        Text("Share")
                    }
                } else {
                    Menu("Share") {}
                        .disabled(true)
                }
            } else {
                // Frames developed under Ask Each Time that haven’t been saved yet.
                Button("Save Unsaved Images…") {
                    model.saveAllUnsaved()
                }
                .disabled(model.unsavedJobIDs.isEmpty)
            }

            Button("Reveal Last Output") {
                model.revealLastOutput()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model.completedJobCount == 0)
        }
    }
}
