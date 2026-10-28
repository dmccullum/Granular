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
        let recents = RecentImageStore.load()
        guard !recents.isEmpty else { return nil }

        let menu = NSMenu()
        for recent in recents.prefix(8) {
            let item = NSMenuItem(
                title: RecentImageStore.menuTitle(for: recent, among: recents),
                action: #selector(openRecentImage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = recent.url
            let icon = NSWorkspace.shared.icon(forFile: recent.url.path)
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
            MainWindowCommands()
            ViewerCommands(model: model)
            // View ▸ Show/Hide Sidebar (⌃⌘S) for the Recipe Library's list.
            SidebarCommands()

            FileCommands(model: model)
            EditCommands(model: model)
            RecipeCommands(model: model)
            InstantCommands(model: model)
            HelpCommands()
        }

        AboutScene(links: AboutLinks(
            sourceCode: URL(string: "https://github.com/dmccullum/Granular"),
            acknowledgements: Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt")
        )) {
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
