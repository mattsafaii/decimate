import CoreGraphics

/// What an effect produces. Image effects return pixels; vector effects
/// (stippling) return geometry that the rendering layer turns into SVG or PNG.
enum EffectOutput {
    case image(CGImage)
    case points([StipplePoint])
}

/// One stipple dot in image coordinates.
struct StipplePoint {
    let x: Double
    let y: Double
    let radius: Double
}

/// An effect: a declaration plus a render function. Adding an effect means
/// adding a conforming type and listing it in `EffectCatalog.all` — nothing else.
protocol Effect {
    var declaration: EffectDeclaration { get }
    func render(input: CGImage, parameters: [String: ParameterValue]) async throws -> EffectOutput
}
