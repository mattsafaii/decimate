import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

struct NoiseEffect: Effect {
    let declaration = EffectDeclaration(
        id: "noise",
        name: "Noise",
        engine: .coreImage,
        parameters: [
            EffectParameter(id: "amount", label: "Amount", kind: .slider(range: 0...1, defaultValue: 0.25)),
            EffectParameter(id: "grainSize", label: "Grain Size", kind: .intSlider(range: 1...8, defaultValue: 1)),
        ],
        outputFormats: [.png]
    )

    func render(input: CGImage, parameters: [String: ParameterValue]) async throws -> EffectOutput {
        let image = CIImage(cgImage: input)
        let amount = parameters["amount"]?.doubleValue ?? 0.25
        let grainSize = max(1, parameters["grainSize"]?.intValue ?? 1)

        guard var noise = CIFilter.randomGenerator().outputImage else {
            throw EffectError.renderFailed
        }
        if grainSize > 1 {
            noise = noise.transformed(by: CGAffineTransform(scaleX: CGFloat(grainSize), y: CGFloat(grainSize)))
        }
        noise = noise.cropped(to: image.extent)

        // Monochrome grain
        let mono = CIFilter.colorControls()
        mono.inputImage = noise
        mono.saturation = 0

        // Scale grain alpha by amount
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = mono.outputImage
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount))

        // Composite grain over the source
        let composite = CIFilter.sourceOverCompositing()
        composite.inputImage = matrix.outputImage
        composite.backgroundImage = image

        guard let output = composite.outputImage?.cropped(to: image.extent) else {
            throw EffectError.renderFailed
        }
        return .image(try CoreImageEngine.renderToCGImage(output, extent: image.extent))
    }
}
