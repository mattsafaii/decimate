import CoreGraphics
import Foundation

/// Tone-following engraving: evenly-spaced horizontal lines that wiggle with an
/// amplitude driven by local darkness — flat in light areas, big sine swings in
/// dark ones — the classic line-engraving look. Emits one editable polyline per
/// line. Pure Swift (a sequential scan); output feeds editable curves.
struct EngravingEffect: Effect {
    let declaration = EffectDeclaration(
        id: "vector-engraving",
        name: "Vector Engraving",
        engine: .swiftPixel,
        parameters: [
            EffectParameter(id: "lines", label: "Lines", kind: .intSlider(range: 10...200, defaultValue: 60)),
            EffectParameter(id: "waveDensity", label: "Wave Density", kind: .slider(range: 4...80, defaultValue: 30)),
            EffectParameter(id: "amplitude", label: "Amplitude", kind: .slider(range: 0...1, defaultValue: 0.85)),
            EffectParameter(id: "weight", label: "Line Weight", kind: .slider(range: 0.3...3, defaultValue: 0.8)),
        ],
        outputFormats: [.svg, .png],
        outputType: .vector
    )

    func render(input: CGImage, parameters: [String: ParameterValue]) async throws -> EffectOutput {
        let lineCount = max(1, parameters["lines"]?.intValue ?? 60)
        let waveDensity = max(1, parameters["waveDensity"]?.doubleValue ?? 30)
        let amplitudeScale = parameters["amplitude"]?.doubleValue ?? 0.85
        let weight = parameters["weight"]?.doubleValue ?? 0.8

        let (pixels, width, height) = try PixelEngine.grayscaleBuffer(from: input)
        let w = Double(width), h = Double(height)
        let spacing = h / Double(lineCount)
        let maxAmplitude = spacing * 0.5 * amplitudeScale
        let wavelength = max(2, w / waveDensity)
        let step = max(1.0, wavelength / 10)

        func darkness(_ x: Double, _ y: Double) -> Double {
            let xi = min(width - 1, max(0, Int(x)))
            let yi = min(height - 1, max(0, Int(y)))
            return 1 - Double(pixels[yi * width + xi]) / 255
        }

        var paths: [VectorPath] = []
        for i in 0..<lineCount {
            try Task.checkCancellation()
            let baseY = (Double(i) + 0.5) * spacing
            var points: [CGPoint] = []
            var x = 0.0
            while x <= w {
                let amplitude = maxAmplitude * darkness(x, baseY)
                let y = baseY + amplitude * sin(2 * .pi * x / wavelength)
                points.append(CGPoint(x: x, y: y))
                x += step
            }
            paths.append(VectorPath(points))
        }
        return .paths(paths, strokeWidth: weight, filled: false)
    }
}
