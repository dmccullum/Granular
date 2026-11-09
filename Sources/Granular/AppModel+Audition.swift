import Foundation
import GranularCore

/// Auditioning: the preview shows a stock or recipe while the pointer rests on
/// its tile, without choosing it. Only the preview reads the audition; exports,
/// copies, thumbnails, undo and the saved recipe keep reading `recipe`.
extension AppModel {
    /// The look the preview renders.
    var previewRecipe: FilmRecipe {
        auditionRecipe ?? recipe
    }

    /// Shows `recipe` in the preview once the pointer has rested on its tile
    /// for 120 ms, so sweeping across a grid doesn't render every tile passed.
    func auditionOnRest(_ recipe: FilmRecipe) {
        auditionTask?.cancel()
        auditionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            auditionTask = nil
            audition(recipe)
        }
    }

    /// The pointer left a tile before resting on it.
    func cancelPendingAudition() {
        auditionTask?.cancel()
        auditionTask = nil
    }

    /// The pointer left the grid, or the grid closed: back to the chosen look.
    func endAudition() {
        cancelPendingAudition()
        audition(nil)
    }

    /// Drops the audition without rendering, for callers about to render the
    /// chosen look themselves.
    func clearAudition() {
        cancelPendingAudition()
        auditionRecipe = nil
    }

    private func audition(_ recipe: FilmRecipe?) {
        // Resting on the chosen look is no audition.
        let audition = recipe == self.recipe ? nil : recipe
        guard audition != auditionRecipe else { return }
        auditionRecipe = audition
        pendingPreviewTransition = .crossfade
        schedulePreview()
    }
}
