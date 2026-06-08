import CoreGraphics
import Foundation

struct StipplingEffect: Effect {
    let declaration = EffectDeclaration(
        id: "stippling",
        name: "Stippling",
        engine: .python,
        parameters: [
            EffectParameter(id: "points", label: "Points", kind: .intSlider(range: 100...20000, defaultValue: 4000)),
            EffectParameter(id: "iterations", label: "Iterations", kind: .intSlider(range: 1...50, defaultValue: 20)),
            EffectParameter(id: "minRadius", label: "Min Dot Size", kind: .slider(range: 0.5...5, defaultValue: 1)),
            EffectParameter(id: "maxRadius", label: "Max Dot Size", kind: .slider(range: 0.5...10, defaultValue: 3)),
        ],
        outputFormats: [.svg, .png],
        outputType: .vector
    )

    func render(input: CGImage, parameters: [String: ParameterValue]) async throws -> EffectOutput {
        let bridge = await PythonBridge(environment: .shared)
        let data = try await bridge.run(script: "stipple", image: input, parameters: parameters)
        let output = try JSONDecoder().decode(StippleOutput.self, from: data)
        return .points(output.points.map { StipplePoint(x: $0.x, y: $0.y, radius: $0.r) })
    }

    private struct StippleOutput: Decodable {
        struct Point: Decodable {
            let x: Double
            let y: Double
            let r: Double
        }
        let width: Int
        let height: Int
        let points: [Point]
    }
}
