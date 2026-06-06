import CoreGraphics
import CoreImage

enum EffectError: Error {
    case renderFailed
}

/// Shared CoreImage rendering: one context, CIImage in, CGImage out.
enum CoreImageEngine {
    static let context = CIContext()

    static func renderToCGImage(_ image: CIImage, extent: CGRect) throws -> CGImage {
        guard let cgImage = context.createCGImage(image, from: extent) else {
            throw EffectError.renderFailed
        }
        return cgImage
    }
}
