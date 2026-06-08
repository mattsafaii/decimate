import Foundation

/// An RGBA color with components in 0...1. Codable so it round-trips through
/// params JSON; Equatable so it works inside `ParameterValue`.
struct ColorValue: Equatable, Codable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    static let black = ColorValue(red: 0, green: 0, blue: 0)
    static let white = ColorValue(red: 1, green: 1, blue: 1)
}

/// An ordered list of colors. Bundled presets and in-session custom palettes
/// share this type; the palette editor (and dithering) read `colors` in order.
struct Palette: Equatable, Identifiable {
    let id: String
    var name: String
    var colors: [ColorValue]

    init(id: String = UUID().uuidString, name: String, colors: [ColorValue]) {
        self.id = id
        self.name = name
        self.colors = colors
    }
}
