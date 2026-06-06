import CoreGraphics

struct FloydSteinbergEffect: Effect {
    let declaration = EffectDeclaration(
        id: "floyd-steinberg",
        name: "Floyd-Steinberg Dither",
        engine: .swiftPixel,
        parameters: [
            EffectParameter(id: "levels", label: "Levels", kind: .intSlider(range: 2...8, defaultValue: 2)),
        ],
        outputFormats: [.png]
    )

    func render(input: CGImage, parameters: [String: ParameterValue]) async throws -> EffectOutput {
        let levels = max(2, parameters["levels"]?.intValue ?? 2)
        let (source, width, height) = try PixelEngine.grayscaleBuffer(from: input)

        var pixels = source.map(Float.init)
        let scale = Float(levels - 1) / 255

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let old = pixels[index]
                let new = (old * scale).rounded() / scale
                pixels[index] = new
                let error = old - new

                if x + 1 < width { pixels[index + 1] += error * 7 / 16 }
                if y + 1 < height {
                    if x > 0 { pixels[index + width - 1] += error * 3 / 16 }
                    pixels[index + width] += error * 5 / 16
                    if x + 1 < width { pixels[index + width + 1] += error * 1 / 16 }
                }
            }
        }

        let output = pixels.map { UInt8(min(255, max(0, $0.rounded()))) }
        return .image(try PixelEngine.grayscaleImage(from: output, width: width, height: height))
    }
}
