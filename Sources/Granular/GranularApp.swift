import AppKit
import DMKit
import GranularCore
import SwiftUI

extension Notification.Name {
    static let granularOpenURLs = Notification.Name("GranularOpenURLs")
    /// Opens one image in Edit mode, whichever mode is showing.
    static let granularOpenRecentImage = Notification.Name("GranularOpenRecentImage")
}

final class GranularApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        ProcessingNotifier.shared.becomeDelegate()
        NSApp.servicesProvider = ImageServiceProvider.shared
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        TransferFiles.removeAll()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The last adjustment may still be waiting to be saved.
        ImageServiceProvider.shared.model?.persistRecipeSelection()
        TransferFiles.removeAll()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // Recipe files join the Recipe Library; everything else is an image.
        let recipeFiles = urls.filter(RecipeFile.isRecipeFile)
        if !recipeFiles.isEmpty {
            RecipeFileInbox.receive(recipeFiles)
        }
        let images = urls.filter { !RecipeFile.isRecipeFile($0) }
        if !images.isEmpty {
            NotificationCenter.default.post(name: .granularOpenURLs, object: images)
        }
    }

    /// A drop still being processed would stop partway, and frames developed
    /// under Ask Each Time live in a temporary folder until they're saved, so
    /// quitting would quietly lose them.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = ImageServiceProvider.shared.model else { return .terminateNow }
        if let batch = model.instantBatch {
            let remaining = max(1, batch.progress.total - batch.progress.completed)
            let alert = NSAlert()
            alert.messageText = "Stop Processing and Quit?"
            alert.informativeText = remaining == 1
                ? "1 image hasn’t finished processing."
                : "\(remaining) images haven’t finished processing."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Stop and Quit").hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
            model.cancelInstantProcessing()
        }
        guard !model.unsavedJobIDs.isEmpty else { return .terminateNow }

        let count = model.unsavedJobIDs.count
        let alert = NSAlert()
        alert.messageText = count == 1
            ? "Save the unsaved image before quitting?"
            : "Save \(count) unsaved images before quitting?"
        alert.informativeText = "If you don’t save, they’ll be discarded."
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don’t Save").hasDestructiveAction = true
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSApp.activate()
            // Quits once they're saved; cancelling the panel keeps Granular open.
            Task {
                let isSaved = await model.saveAllUnsavedBeforeQuitting()
                NSApp.reply(toApplicationShouldTerminate: isSaved)
            }
            return .terminateLater
        case .alertThirdButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Recent images, for picking up where you left off from the Dock.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        // The list is pruned when Granular becomes active; the Dock can ask
        // while it's in the background, so look for each file here too.
        let urls = (ImageServiceProvider.shared.model?.recentImages.items ?? []).compactMap { item -> URL? in
            let url = item.resolve().url
            return url.withSecurityScope { FileManager.default.fileExists(atPath: url.path) } ? url : nil
        }
        guard !urls.isEmpty else { return nil }

        let menu = NSMenu()
        let shown = Array(urls.prefix(8))
        for (url, title) in zip(shown, RecentItems.menuTitles(for: shown)) {
            let item = NSMenuItem(
                title: title,
                action: #selector(openRecentImage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = url
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        return menu
    }

    @objc private func openRecentImage(_ item: NSMenuItem) {
        guard let url = item.representedObject as? URL else { return }
        NSApp.activate()
        NotificationCenter.default.post(name: .granularOpenRecentImage, object: url)
    }
}

@main
struct GranularDesktopApp: App {
    @NSApplicationDelegateAdaptor(GranularApplicationDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        SystemIntegration.connect(model)
    }

    var body: some Scene {
        @Bindable var model = model

        Window("Granular", id: "main") {
            ContentView()
                .environment(model)
                .recordingAdjustmentUndo(for: model)
        }
        .defaultSize(model.initialWindowSize)
        .restorationBehavior(.disabled)
        .commands {
            // App › About opens the AboutScene below, which doesn't add the item itself.
            AboutCommands()
            MainWindowCommands()
            ViewerCommands(model: model)
            // View ▸ Show/Hide Sidebar (⌃⌘S) for the Recipe Library's list.
            SidebarCommands()

            FileCommands(model: model)
            // Edit ▸ Undo and Redo, titled with each step's name.
            UndoCommands()
            EditCommands(model: model)
            RecipeCommands(model: model)
            InstantCommands(model: model)
            // Granular has no help book, so its README on GitHub is the help.
            FamilyHelpCommands(
                help: URL(string: "https://github.com/dmccullum/Granular#readme")!,
                keyboardShortcuts: .url(URL(string: "https://github.com/dmccullum/Granular#keyboard-shortcuts")!),
                reportIssue: URL(string: "https://github.com/dmccullum/Granular/issues/new"),
                acknowledgements: GranularLinks.acknowledgements
            )
        }

        // The camera metal follows the system appearance, as Instant mode's body
        // does: both finishes are about as light or dark as the stock window, so
        // DMKit's label colors read on them as they do there.
        AboutScene(
            links: AboutLinks(
                sourceCode: GranularLinks.repository,
                acknowledgements: GranularLinks.acknowledgements
            ),
            backdrop: AnyView(AboutCameraMetal())
        ) {
            PipelineDial()
        }

        Window("Recipe Library", id: RecipeLibraryView.windowID) {
            RecipeLibraryView()
                .environment(model)
        }
        .defaultSize(width: 800, height: 520)
        .windowResizability(.contentMinSize)
        // Opens where it was last left, but only when asked for.
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .environment(model)
        }
        // Each tab already fits its content, so the window can't be resized or zoomed.
        .windowResizability(.contentSize)

        MenuBarExtra(isInserted: Binding(
            get: { model.menuBarVisibility == .always || model.showMenuBarExtra },
            set: { model.showMenuBarExtra = $0 }
        )) {
            MenuBarStatusView()
                .environment(model)
        } label: {
            Image(nsImage: MenuBarGlyph.image(isWatching: model.isWatching))
                .accessibilityLabel(model.isWatching ? "Granular, watching" : "Granular")
        }
        // A real menu, like every other menu bar item: keyboard navigation,
        // type-select, and it gets out of the way as soon as a choice is made.
        .menuBarExtraStyle(.menu)
    }
}

/// Where About and Help point.
enum GranularLinks {
    static let repository = URL(string: "https://github.com/dmccullum/Granular")!
    /// THIRD_PARTY_NOTICES.txt, copied into the bundle by Scripts/build-app.sh.
    static let acknowledgements = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt")
}
