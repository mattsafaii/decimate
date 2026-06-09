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

extension ColorValue {
    /// 0–255 sRGB convenience.
    init(_ r: Int, _ g: Int, _ b: Int) {
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

extension Palette {
    /// Bundled presets. The palette editor adds in-session custom palettes on top.
    static let bundled: [Palette] = [
        Palette(id: "bw", name: "Black & White", colors: [.black, .white]),
        Palette(id: "gray4", name: "4 Grays", colors: [
            ColorValue(0, 0, 0), ColorValue(85, 85, 85), ColorValue(170, 170, 170), ColorValue(255, 255, 255),
        ]),
        Palette(id: "gameboy", name: "Game Boy", colors: [
            ColorValue(15, 56, 15), ColorValue(48, 98, 48), ColorValue(139, 172, 15), ColorValue(155, 188, 15),
        ]),
        Palette(id: "cga", name: "CGA", colors: [
            ColorValue(0, 0, 0), ColorValue(85, 255, 255), ColorValue(255, 85, 255), ColorValue(255, 255, 255),
        ]),
        Palette(id: "rgbcmyk", name: "RGB + CMYK", colors: [
            .black, .white,
            ColorValue(255, 0, 0), ColorValue(0, 255, 0), ColorValue(0, 0, 255),
            ColorValue(0, 255, 255), ColorValue(255, 0, 255), ColorValue(255, 255, 0),
        ]),
        Palette(id: "pico8", name: "Pico-8", colors: [
            ColorValue(0, 0, 0), ColorValue(29, 43, 83), ColorValue(126, 37, 83), ColorValue(0, 135, 81),
            ColorValue(171, 82, 54), ColorValue(95, 87, 79), ColorValue(194, 195, 199), ColorValue(255, 241, 232),
            ColorValue(255, 0, 77), ColorValue(255, 163, 0), ColorValue(255, 236, 39), ColorValue(0, 228, 54),
            ColorValue(41, 173, 255), ColorValue(131, 118, 156), ColorValue(255, 119, 168), ColorValue(255, 204, 170),
        ]),
    ]

    static let `default` = bundled[0]
}
