import AppKit
import GranularCore
import Foundation
import UniformTypeIdentifiers

nonisolated enum InstantOutputKey {
    static let asksEachTime = "settings.instantAsksEachTime"
}

/// Where Ask Each Time develops frames until they’re saved. Each drop gets its
/// own folder, so the files keep their real names. Whatever is left is cleared
/// at the next drop after launch, and at quit.
nonisolated enum UnsavedOutputs {
    private static var root: URL {
        FileManager.default.temporaryDirectory.appending(path: "Granular Unsaved", directoryHint: .isDirectory)
    }

    /// Clears what an earlier launch left behind, once, before this launch
    /// puts anything here.
    private static let clearsEarlierLaunches: Void = {
        removeAll()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { _ in removeAll() }
    }()

    static func makeFolder() throws -> URL {
        _ = clearsEarlierLaunches
        let folder = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Removes a frame’s file, and the folder it was developed into once that’s empty.
    static func remove(_ file: URL) {
        let folder = file.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: file)
        guard folder.deletingLastPathComponent().lastPathComponent == root.lastPathComponent,
              (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}

// Instant mode, Ask Each Time: frames are exposed as usual, into a temporary
// folder; once the film has wound on, one Save panel asks where they go.
extension AppModel {
    func askWhereToSaveEachTime() {
        asksWhereToSaveInstantly = true
    }

    /// The folder’s name in the footer and Settings, or the Ask Each Time label.
    var dropOutputTitle: String {
        if asksWhereToSaveInstantly { return "Ask Each Time" }
        return dropOutputFolder?.lastPathComponent ?? "Choose Output Folder"
    }

    // MARK: When to ask

    /// Called once a drop’s last image is done. The panel waits for the film
    /// to wind on, or for a few seconds if nothing is there to say so.
    func armSavePrompt() {
        guard !jobsAwaitingSavePrompt.isEmpty else { return }
        isSavePromptArmed = true
        savePromptTask?.cancel()
        savePromptTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.4))
            guard !Task.isCancelled else { return }
            self?.promptToSaveUnsaved()
        }
    }

    /// The camera back calls this as its last frame comes to rest.
    func filmDidSettle() {
        promptToSaveUnsaved()
    }

    /// Asks about every frame developed since the last time, if a drop has
    /// finished and Granular is in front to ask.
    func promptToSaveUnsaved() {
        guard isSavePromptArmed, instantBatch == nil, !isPresentingSavePanel, NSApp.isActive else { return }
        isSavePromptArmed = false
        savePromptTask?.cancel()
        let ids = jobsAwaitingSavePrompt.filter { unsavedJobIDs.contains($0) }
        jobsAwaitingSavePrompt = []
        guard !ids.isEmpty else { return }
        Task { await askWhereToSave(ids) }
    }

    /// Every unsaved frame, oldest first, for the footer button and the File menu.
    func saveAllUnsaved() {
        let ids = jobs.reversed().map(\.id).filter { unsavedJobIDs.contains($0) }
        guard !ids.isEmpty, !isPresentingSavePanel else { return }
        Task { await askWhereToSave(ids) }
    }

    /// Saves every unsaved frame for Quit, returning whether all of them were.
    func saveAllUnsavedBeforeQuitting() async -> Bool {
        let ids = jobs.reversed().map(\.id).filter { unsavedJobIDs.contains($0) }
        guard !isPresentingSavePanel else { return false }
        await askWhereToSave(ids)
        return unsavedJobIDs.isEmpty
    }

    func saveUnsaved(_ id: UUID) {
        guard unsavedJobIDs.contains(id), !isPresentingSavePanel else { return }
        Task { await askWhereToSave([id]) }
    }

    // MARK: Asking

    private func askWhereToSave(_ ids: [UUID]) async {
        let frames = ids.compactMap { id -> (id: UUID, file: URL)? in
            guard case .finished(let file) = job(id)?.state, unsavedJobIDs.contains(id) else { return nil }
            return (id, file)
        }
        guard let first = frames.first, !isPresentingSavePanel else { return }
        isPresentingSavePanel = true
        defer {
            isPresentingSavePanel = false
            // A drop that finished meanwhile is asked about next.
            promptToSaveUnsaved()
        }

        if frames.count == 1 {
            let panel = NSSavePanel()
            panel.title = "Save Processed Image"
            panel.message = "Choose where to save “\(first.file.lastPathComponent)”."
            panel.prompt = "Save"
            panel.nameFieldStringValue = first.file.lastPathComponent
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.allowsOtherFileTypes = false
            if let type = UTType(filenameExtension: first.file.pathExtension) {
                panel.allowedContentTypes = [type]
            }
            if let folder = dropOutputFolder, Self.isExistingDirectory(folder) {
                panel.directoryURL = folder
            }
            guard await present(panel) == .OK, let destination = panel.url else {
                noteUnsaved(count: 1)
                return
            }
            do {
                try move(first.file, to: destination, replacing: true)
                markSaved(first.id, at: destination)
            } catch {
                editorAlert = EditorAlert(
                    title: "“\(destination.lastPathComponent)” couldn’t be saved.",
                    message: "\(error.localizedDescription)\n\nThe image is still on the film strip, unsaved."
                )
            }
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Save Processed Images"
        panel.message = "Choose a folder for the \(frames.count) processed images."
        panel.prompt = "Save"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let folder = dropOutputFolder, Self.isExistingDirectory(folder) {
            panel.directoryURL = folder
        }
        guard await present(panel) == .OK, let folder = panel.url else {
            noteUnsaved(count: frames.count)
            return
        }
        var saved = 0
        var lastError: Error?
        for frame in frames {
            let destination = SaveDestination.availableURL(for: frame.file.lastPathComponent, in: folder)
            do {
                try move(frame.file, to: destination, replacing: false)
                markSaved(frame.id, at: destination)
                saved += 1
            } catch {
                lastError = error
            }
        }
        if let lastError {
            let failed = frames.count - saved
            editorAlert = EditorAlert(
                title: "\(failed) of \(frames.count) images couldn’t be saved to “\(folder.lastPathComponent)”.",
                message: "\(lastError.localizedDescription)\n\n\(failed == 1 ? "It’s" : "They’re") still on the film strip, unsaved."
            )
        }
    }

    /// Leaves the frames on the strip, marked, for the person to save later.
    private func noteUnsaved(count: Int) {
        showEditorNotice(count == 1
            ? "Not saved yet. Right-click the frame to save it."
            : "\(count) images not saved yet. Use Save… to choose a folder.")
    }

    /// A sheet on the main window when there is one, so the panel belongs to
    /// what was just developed.
    private func present(_ panel: NSSavePanel) async -> NSApplication.ModalResponse {
        guard let window = observedWindow ?? NSApp.mainWindow, window.isVisible, !window.isMiniaturized else {
            return panel.runModal()
        }
        return await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
    }

    private func move(_ file: URL, to destination: URL, replacing: Bool) throws {
        let manager = FileManager.default
        if replacing, manager.fileExists(atPath: destination.path) {
            // The Save panel has already confirmed the replacement.
            _ = try manager.replaceItemAt(destination, withItemAt: file)
        } else {
            try manager.moveItem(at: file, to: destination)
        }
        UnsavedOutputs.remove(file)
    }

    private func markSaved(_ id: UUID, at destination: URL) {
        unsavedJobIDs.remove(id)
        updateJob(id, state: .finished(destination))
    }
}
