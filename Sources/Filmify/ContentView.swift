import FilmifyCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Group {
            switch model.operationMode {
            case .drop:
                DropModeView()
            case .edit:
                EditModeView()
            }
        }
        .frame(minWidth: 620, minHeight: 340)
        .overlay(alignment: .topTrailing) {
            if model.operationMode == .edit {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
                    .offset(x: -310)
                    .ignoresSafeArea(.container, edges: .top)
                    .allowsHitTesting(false)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                RecipeMenu()
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
        .sheet(isPresented: $model.showRecipeManager) {
            RecipeManagerView()
                .environment(model)
        }
        .onReceive(NotificationCenter.default.publisher(for: .filmifyOpenURLs)) { notification in
            guard let urls = notification.object as? [URL] else { return }
            if model.operationMode == .edit {
                model.openForEditing(urls)
            } else {
                Task { await model.processInstantly(urls) }
            }
        }
        .alert(
            "Filmify Couldn’t Start",
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
    }
}

private struct ModePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Picker("Mode", selection: $model.operationMode) {
            ForEach(OperationMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

private struct RecipeMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Section("Built-in") {
                ForEach(FilmRecipe.builtIns) { recipe in
                    recipeButton(recipe)
                }
            }

            if !model.savedRecipes.isEmpty {
                Section("My Recipes") {
                    ForEach(model.savedRecipes) { recipe in
                        recipeButton(recipe)
                    }
                }
            }

            if model.operationMode == .edit {
                Divider()
                Button("Save Current as Recipe…", systemImage: "plus") {
                    model.saveCurrentAsRecipe()
                }
                if model.isSelectedRecipeCustom {
                    Button("Update “\(model.currentRecipe.name)”", systemImage: "square.and.arrow.down") {
                        model.updateSelectedRecipe()
                    }
                    Button("Delete “\(model.currentRecipe.name)”", systemImage: "trash", role: .destructive) {
                        model.deleteSelectedRecipe()
                    }
                }

            }

            Divider()
            Button("Manage Recipes…", systemImage: "list.bullet") {
                model.showRecipeManager = true
            }
        } label: {
            Image(systemName: "camera.filters")
                .accessibilityLabel(model.recipe.name)
        }
        .help("Choose or save a film recipe")
    }

    @ViewBuilder
    private func recipeButton(_ recipe: FilmRecipe) -> some View {
        Button {
            model.selectRecipe(recipe)
        } label: {
            if model.selectedRecipeID == recipe.id {
                Label(recipe.name, systemImage: "checkmark")
            } else {
                Text(recipe.name)
            }
        }
    }
}
