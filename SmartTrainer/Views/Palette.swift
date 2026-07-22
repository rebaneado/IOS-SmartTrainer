import SwiftUI

/// Colors ported from the web app's validated categorical palette, so the two
/// apps read as one product. Heart rate is red by universal fitness convention.
enum Palette {
    static let power = Color(red: 0.165, green: 0.471, blue: 0.839)     // #2a78d6 blue
    static let cadence = Color(red: 0.0, green: 0.514, blue: 0.0)        // #008300 green
    static let heartRate = Color(red: 0.890, green: 0.286, blue: 0.282)  // #e34948 red
    static let speed = Color(red: 0.106, green: 0.686, blue: 0.478)      // #1baf7a aqua
    static let distance = Color(red: 0.929, green: 0.631, blue: 0.0)     // #eda100 yellow
    static let warning = Color(red: 0.980, green: 0.698, blue: 0.098)    // #fab219

    /// Intensity color for a power fraction of FTP, light→dark blue. Mirrors
    /// the web app's `powerFractionToColor` (domain 0.4–1.3).
    static func powerFractionColor(_ fraction: Double) -> Color {
        let domainMin = 0.4, domainMax = 1.3
        let t = min(1, max(0, (fraction - domainMin) / (domainMax - domainMin)))
        // Anchors: light #86b6ef -> dark #0d366b
        let light = (r: 0.525, g: 0.714, b: 0.937)
        let dark = (r: 0.051, g: 0.212, b: 0.420)
        return Color(
            red: light.r + (dark.r - light.r) * t,
            green: light.g + (dark.g - light.g) * t,
            blue: light.b + (dark.b - light.b) * t
        )
    }
}
