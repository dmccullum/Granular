/// Landmarks on a continuous control: a slider's default and range ends, the
/// viewer's Fit and 100% zoom.
public enum SliderDetent {
    /// Whether moving from `old` to `new` reaches or passes `detent`.
    ///
    /// Leaving a detent, or staying on it, doesn't count.
    public static func crosses(from old: Double, to new: Double, detent: Double) -> Bool {
        guard old != new, old != detent else { return false }
        return (old < detent && new >= detent) || (old > detent && new <= detent)
    }

    /// Whether moving from `old` to `new` reaches or passes any of `detents`.
    public static func crossesAny(from old: Double, to new: Double, detents: [Double]) -> Bool {
        detents.contains { crosses(from: old, to: new, detent: $0) }
    }
}
