import Foundation

/// The adjustments in the order the renderer applies them. The inspector's
/// cards and the About window's pipeline dial both read their names and
/// symbols from here, so the two always match.
enum PipelineStage: CaseIterable {
    case filmTone
    case vignette
    case lensBlur
    case diffusion
    case halation
    case landscapeGlow
    case filmGrain

    var name: String {
        switch self {
        case .filmTone: "Film Tone"
        case .vignette: "Vignette"
        case .lensBlur: "Lens Blur"
        case .diffusion: "Diffusion"
        case .halation: "Halation"
        case .landscapeGlow: "Landscape Glow"
        case .filmGrain: "Film Grain"
        }
    }

    var systemImage: String {
        switch self {
        case .filmTone: "film"
        case .vignette: "smallcircle.filled.circle"
        case .lensBlur: "camera.aperture"
        case .diffusion: "camera.filters"
        case .halation: "sun.horizon"
        case .landscapeGlow: "mountain.2"
        case .filmGrain: "aqi.medium"
        }
    }

    /// The point-size multiplier that gives the symbol the same footprint as
    /// the round ones. At 13 pt semibold the round symbols' ink spans
    /// 13.8 × 13.8 pt (190 pt²); the mountains span 23 × 11.5 (264 pt²) and the
    /// grain 13.8 × 15.8 (218 pt²), so they scale by the square root of the
    /// ratio. Film (186 pt²) and the horizon (173 pt²) are close enough as drawn.
    var opticalScale: Double {
        switch self {
        case .landscapeGlow: 0.85
        case .filmGrain: 0.93
        default: 1
        }
    }
}
