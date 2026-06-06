import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

struct HalftoneEffect: Effect {
    let declaration = EffectDeclaration(
        id: "halftone",
        name: "Halftone",
        engine: .coreImage,
        parameters: [
            EffectParameter(id: "dotWidth", label: "Dot Width", kind: .slider(range: 2...50, defaultValue: 6)),
            EffectParameter(id: "angle", label: "Angle", kind: .slider(range: 0...180, defaultValue: 0)),
            EffectParameter(id: "sharpness", label: "Sharpness", kind: .slider(range: 0...1, defaultValue: 0.7)),
        ],
        outputFormats: [.png]
    )

    func render(input: CGImage, parameters: [String: ParameterValue]) async throws -> EffectOutput {
        let image = CIImage(cgImage: input)
        let filter = CIFilter.dotScreen()
        filter.inputImage = image
        filter.center = CGPoint(x: image.extent.midX, y: image.extent.midY)
        filter.angle = Float((parameters["angle"]?.doubleValue ?? 0) * .pi / 180)
        filter.width = Float(parameters["dotWidth"]?.doubleValue ?? 6)
        filter.sharpness = Float(parameters["sharpness"]?.doubleValue ?? 0.7)
        guard let output = filter.outputImage?.cropped(to: image.extent) else {
            throw EffectError.renderFailed
        }
        return .image(try CoreImageEngine.renderToCGImage(output, extent: image.extent))
    }
}
