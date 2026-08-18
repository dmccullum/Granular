import Foundation

public enum ViewerZoomMath {
    public static let minimumScale = 0.01
    public static let maximumScale = 8.0

    // Actual-size landmarks. These are powers of two around 100%, so the
    // buttons and keyboard commands always land on useful, predictable scales
    // regardless of the image's current Fit percentage.
    private static let zoomStops = [
        minimumScale,
        0.015625,
        0.03125,
        0.0625,
        0.125,
        0.25,
        0.5,
        1,
        2,
        4,
        maximumScale
    ]

    public static func fitScale(
        imageWidth: Double,
        imageHeight: Double,
        viewportWidth: Double,
        viewportHeight: Double,
        padding: Double = 48
    ) -> Double {
        guard imageWidth > 0, imageHeight > 0 else { return 1 }
        let availableWidth = max(1, viewportWidth - padding)
        let availableHeight = max(1, viewportHeight - padding)
        return clampedScale(min(availableWidth / imageWidth, availableHeight / imageHeight))
    }

    public static func zoomedIn(from scale: Double) -> Double {
        let current = clampedScale(scale)
        let tolerance = max(0.000_001, current * 0.000_001)
        return zoomStops.first { $0 > current + tolerance } ?? maximumScale
    }

    public static func zoomedOut(from scale: Double) -> Double {
        let current = clampedScale(scale)
        let tolerance = max(0.000_001, current * 0.000_001)
        return zoomStops.last { $0 < current - tolerance } ?? minimumScale
    }

    public static func clampedScale(_ scale: Double) -> Double {
        min(maximumScale, max(minimumScale, scale))
    }

    public static func sliderPosition(forScale scale: Double) -> Double {
        let clamped = clampedScale(scale)
        return log(clamped / minimumScale) / log(maximumScale / minimumScale)
    }

    public static func scale(forSliderPosition position: Double) -> Double {
        let clampedPosition = min(1, max(0, position))
        return minimumScale * pow(maximumScale / minimumScale, clampedPosition)
    }

    public static func clampedPanOffset(
        _ proposedOffset: Double,
        displayLength: Double,
        viewportLength: Double
    ) -> Double {
        let limit = max(0, (displayLength - viewportLength) / 2)
        return min(limit, max(-limit, proposedOffset))
    }
}
