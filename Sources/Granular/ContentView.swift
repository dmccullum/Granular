import AppKit
import GranularCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Edit mode put away under Instant mode: out of reach of the keyboard
    /// and VoiceOver. Putting it away makes its sliders update, which would
    /// stall an animation, so it waits until Instant mode has settled.
    @State private var isEditModeAway = false

    var body: some View {
        @Bindable var model = model

        let showsCameraBody = model.operationMode == .drop
        let isCameraBodyOnScreen = model.displayedMode == .drop

        // A mode switch is one motion: the window resizes while Instant
        // mode's camera body fades in over Edit mode or out to reveal it,
        // each held at its own size so neither reflows mid-move.
        ZStack {
            // Edit mode stays built, and opaque, under Instant mode. Building
            // it afresh, or fading it, made its sliders lay themselves out
            // again, which held up the switch.
            EditModeView()
                .holdingLayoutDuringModeChange(for: .edit)
                .allowsHitTesting(!showsCameraBody)
                .disabled(isEditModeAway)
                .accessibilityHidden(isEditModeAway)
                .task(id: showsCameraBody && !model.isSettlingWindow) {
                    guard showsCameraBody, !model.isSettlingWindow else {
                        // Back before the window moves, while nothing animates.
                        isEditModeAway = false
                        return
                    }
                    // After the film has loaded.
                    try? await Task.sleep(for: .seconds(1))
                    isEditModeAway = !Task.isCancelled
                }
            // Built as soon as Instant mode is chosen, and drawn once, all but
            // transparent, so its first frame on screen isn't its first
            // render. It fades in and out as the window moves, and goes only
            // once the window has settled, out of sight: taking it away, or
            // drawing it for the first time, held up the start of the move.
            if showsCameraBody || isCameraBodyOnScreen || model.isSettlingWindow {
                ZStack {
                    AlloySurface()
                        .ignoresSafeArea()
                    DropModeView()
                        .holdingLayoutDuringModeChange(for: .drop)
                }
                // Never quite opaque or quite clear, so fading doesn't change
                // how it is drawn, which stalled the start of the switch.
                .opacity(isCameraBodyOnScreen ? 0.999 : 0.001)
                .animation(fadeAnimation, value: isCameraBodyOnScreen)
                .allowsHitTesting(showsCameraBody)
                .transition(.identity)
            }
        }
        .frame(minWidth: 620, minHeight: 340)
        // Edit mode's canvas and panel run up under the title, with the line
        // between them, rather than behind a toolbar material, which picks
        // up the desktop's tint.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar(removing: showsCameraBody ? .title : nil)
        // In Edit mode the window stands for the open image: its name and
        // proxy icon, with the recipe beneath. Instant mode keeps its nameplate.
        .background {
            EditorWindowDocument()
        }
        .toolbar {
            if showsCameraBody {
                ToolbarItem(placement: .principal) {
                    CameraNameplate()
                }
                .sharedBackgroundVisibility(.hidden)
            }
            if model.operationMode == .edit {
                ToolbarItem(placement: .primaryAction) {
                    EditorShareButton()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                ModePicker()
            }
        }
        .onChange(of: model.operationMode) { _, _ in
            model.modeDidChange()
        }
        .onAppear {
            model.scheduleWindowResize(for: model.operationMode, animated: false)
        }
        .openingRecipeLibrary()
        .sheet(isPresented: $model.isSavingRecipe) {
            SaveRecipeSheet()
                .environment(model)
        }
        .onReceive(NotificationCenter.default.publisher(for: .granularOpenRecentImage)) { notification in
            guard let url = notification.object as? URL else { return }
            model.openForEditing([url])
        }
        .onReceive(NotificationCenter.default.publisher(for: .granularOpenURLs)) { notification in
            guard let urls = notification.object as? [URL] else { return }
            // Edit mode opens the first and offers the rest to Instant mode.
            if model.operationMode == .edit {
                model.openForEditing(urls)
            } else {
                Task { await model.processInstantly(urls) }
            }
        }
        .alert(
            "Granular Couldn’t Start",
            isPresented: Binding(
                get: { model.startupError != nil },
                set: { if !$0 { model.startupError = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(model.startupError ?? "Unknown error")
            }
        )
        .alert(
            model.editorAlert?.title ?? "",
            isPresented: Binding(
                get: { model.editorAlert != nil },
                set: { if !$0 { model.editorAlert = nil } }
            ),
            presenting: model.editorAlert,
            actions: { alert in
                if case .chooseDropOutputFolder(let urls) = alert.action {
                    Button("Choose Folder…") {
                        // After the alert is gone, so the panel isn't opened under it.
                        Task { model.chooseDropOutputFolder(thenProcessing: urls) }
                    }
                    Button("Cancel", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            },
            message: { alert in
                Text(alert.message)
            }
        )
    }

    /// The camera body fades quickly, in the first part of the window's
    /// move, so it is seen over the image only briefly.
    private var fadeAnimation: Animation {
        .easeOut(duration: reduceMotion ? 0.1 : 0.2)
    }
}

private struct ModeChangeLayoutHold: ViewModifier {
    @Environment(AppModel.self) private var model
    let mode: OperationMode
    @State private var settledSize: CGSize?

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            let size = layoutSize(live: proxy.size)
            content
                .frame(width: size.width, height: size.height)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .onChange(of: proxy.size, initial: true) { _, newSize in
                    if !model.isSettlingWindow, model.operationMode == mode {
                        settledSize = newSize
                    }
                }
        }
    }

    /// Live size in the current mode; during a mode switch, the arriving mode
    /// is laid out at its final size. A mode that isn't showing keeps the size
    /// it had, so a hidden Edit mode isn't laid out again for Instant's window.
    /// Both are pinned top-centre, where the window resizes around them.
    private func layoutSize(live: CGSize) -> CGSize {
        if model.operationMode != mode {
            return settledSize ?? live
        }
        guard model.isSettlingWindow else { return live }
        return model.arrivingLayoutSize ?? live
    }
}

extension View {
    func holdingLayoutDuringModeChange(for mode: OperationMode) -> some View {
        modifier(ModeChangeLayoutHold(mode: mode))
    }
}

private struct ModePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Picker("Mode", selection: $model.operationMode) {
            ForEach(OperationMode.allCases) { mode in
                Text(mode.rawValue)
                    .tag(mode)
                    .help(mode.help)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Switch between Instant and Edit (⌘1, ⌘2)")
    }
}

private extension OperationMode {
    var help: String {
        switch self {
        case .drop: "Instant: drop images to process them straight to a folder (⌘1)"
        case .edit: "Edit: adjust one image with a live preview, then export (⌘2)"
        }
    }
}

/// Shows the recipe menu from Instant mode's film canister.
enum RecipeMenuPresenter {
    static func popUp(model: AppModel) {
        let controller = RecipeMenuController(model: model)
        // Menu items hold their target weakly; keep it while the menu is open.
        withExtendedLifetime(controller) {
            controller.showMenuAtMouseLocation()
        }
    }
}

final class RecipeMenuController: NSObject {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func showMenuAtMouseLocation() {
        makeMenu().popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func selectRecipe(_ item: NSMenuItem) {
        guard let recipeID = item.representedObject as? String,
              let recipe = model.availableRecipes.first(where: { $0.id == recipeID }) else { return }
        model.selectRecipe(recipe)
    }

    @objc private func manageRecipes() {
        model.showRecipeLibrary()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if model.isRecipeModified {
            let custom = NSMenuItem(title: "Custom", action: nil, keyEquivalent: "")
            custom.state = .on
            custom.isEnabled = false
            menu.addItem(custom)
            menu.addItem(.separator())
        }

        addRecipeSection("Built-in", recipes: FilmRecipe.builtIns, to: menu)

        if !model.savedRecipes.isEmpty {
            menu.addItem(.separator())
            addRecipeSection("My Recipes", recipes: model.savedRecipes, to: menu)
        }

        menu.addItem(.separator())
        let library = NSMenuItem(title: "Recipe Library…", action: #selector(manageRecipes), keyEquivalent: "")
        library.target = self
        menu.addItem(library)
        return menu
    }

    private func addRecipeSection(_ title: String, recipes: [FilmRecipe], to menu: NSMenu) {
        menu.addItem(.sectionHeader(title: title))
        for recipe in recipes {
            let item = NSMenuItem(title: recipe.name, action: #selector(selectRecipe(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = recipe.id
            item.state = !model.isRecipeModified && recipe.id == model.selectedRecipeID ? .on : .off
            menu.addItem(item)
        }
    }
}
