import CoreGraphics

/// What an effect produces. Image effects return pixels; vector effects return
/// geometry the rendering layer turns into SVG/PNG for export, or editable
/// curves when sent to Affinity. `points` are filled dots (Vector Stipple);
/// `paths` are stroked polylines (engraving, line-screen).
enum EffectOutput {
    case image(CGImage)
    case points([StipplePoint])
    case paths([VectorPath], strokeWidth: Double)
}

/// One stipple dot in image coordinates.
struct StipplePoint {
    let x: Double
    let y: Double
    let radius: Double
}

/// A stroked polyline in image coordinates (top-left origin). Used by the
/// line-based vector effects; a uniform stroke weight is applied at render time.
struct VectorPath {
    var points: [CGPoint]
    var closed: Bool

    init(_ points: [CGPoint], closed: Bool = false) {
        self.points = points
        self.closed = closed
    }
}

/// An effect: a declaration plus a render function. Adding an effect means
/// adding a conforming type and listing it in `EffectCatalog.all` — nothing else.
protocol Effect {
    var declaration: EffectDeclaration { get }
    func render(input: CGImage, parameters: [String: ParameterValue]) async throws -> EffectOutput
}
