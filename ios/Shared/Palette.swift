import SwiftUI

/// Renders palette values (0xRRGGBB) supplied by the Kotlin facade. No habit logic here.
enum Palette {
    static func color(hex: Int) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255.0,
              green: Double((hex >> 8) & 0xFF) / 255.0,
              blue: Double(hex & 0xFF) / 255.0)
    }

    /// Color for a habit's `colorIndex` out of the facade palette; gray if out of range.
    static func color(index: Int, in palette: [Int]) -> Color {
        guard index >= 0, index < palette.count else { return .gray }
        return color(hex: palette[index])
    }
}
