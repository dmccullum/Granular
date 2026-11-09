import AppKit

/// Trackpad feedback. Only Force Touch trackpads play it, and only while
/// “Force Click and haptic feedback” is on in System Settings.
enum Haptics {
    /// A control passing a landmark: a slider's default or range end, Fit or 100% zoom.
    static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Something landing: files dropped on the gate.
    static func bump() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
