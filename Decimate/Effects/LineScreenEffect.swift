import CoreGraphics
import Foundation

/// Line-screen halftone as vectors: evenly-spaced horizontal lines rendered as
/// filled ribbons whose half-thickness tracks local darkness — hairline where
/// light, touching their neighbours where black. Each ribbon is one editable
/// closed curve. Pure Swift; output feeds editable (filled) curves.
struct LineScreenEffect: Effect {
    let declaration = EffectDeclaration(
        id: "vector-line-screen",
        name: "Vector Line-screen",
        engine: .swiftPixel,
        parameters: [
            EffectParameter(id: "lines", label: "Lines", kind: .intSlider(range: 20...300, defaultValue: 120)),
            EffectParameter(id: "thickness", label: "Max Thickness", kind: .slider(range: 0.1...1, defaultValue: 1)),
            EffectParameter(id: "contrast", label: "Contrast", kind: .slider(range: 0.5...2.5, defaultValue: 1)),
        ],
        outputFormats: [.svg, .png],
        outputType: .vector
    )

    func render(input: CGImage, parameters: [String: ParameterValue]) async throws -> EffectOutput {
        let lineCount = max(1, parameters["lines"]?.intValue ?? 120)
        let thicknessScale = parameters["thickness"]?.doubleValue ?? 1
        let contrast = max(0.1, parameters["contrast"]?.doubleValue ?? 1)

        let (pixels, width, height) = try PixelEngine.grayscaleBuffer(from: input)
        let w = Double(width), h = Double(height)
        let spacing = h / Double(lineCount)
        let maxHalf = spacing * 0.5 * thicknessScale
        let step = max(1.0, spacing * 0.5)

        func darkness(_ x: Double, _ y: Double) -> Double {
            let xi = min(width - 1, max(0, Int(x)))
            let yi = min(height - 1, max(0, Int(y)))
            let d = 1 - Double(pixels[yi * width + xi]) / 255
            return pow(d, 1 / contrast)
        }

        var paths: [VectorPath] = []
        for i in 0..<lineCount {
            try Task.checkCancellation()
            let baseY = (Double(i) + 0.5) * spacing

            // Sample half-thickness across the row.
            var xs: [Double] = []
            var top: [CGPoint] = []
            var x = 0.0
            while x <= w {
                let half = maxHalf * darkness(x, baseY)
                top.append(CGPoint(x: x, y: baseY - half))
                xs.append(x)
                x += step
            }
            // Close the ribbon: top edge L→R, bottom edge R→L.
            var ring = top
            for j in stride(from: xs.count - 1, through: 0, by: -1) {
                let half = maxHalf * darkness(xs[j], baseY)
                ring.append(CGPoint(x: xs[j], y: baseY + half))
            }
            paths.append(VectorPath(ring, closed: true))
        }
        return .paths(paths, strokeWidth: 0, filled: true)
    }
}
