import CoreGraphics
import Foundation

/// Renders a stipple point list to SVG or PNG. Rendering is independent of
/// how points were produced, so future custom-shape stippling only touches
/// this layer.
enum StippleRenderer {
    /// SVG document: plain black circles, transparent background — imports
    /// into Affinity as editable vector dots.
    static func svg(_ points: [StipplePoint], width: Int, height: Int) -> Data {
        var doc = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)">
        <g fill="black">

        """
        for point in points {
            doc += "<circle cx=\"\(point.x)\" cy=\"\(point.y)\" r=\"\(point.radius)\"/>\n"
        }
        doc += "</g>\n</svg>\n"
        return Data(doc.utf8)
    }

    /// Raster render: black dots on white. Point coordinates are top-left
    /// origin (image space); CGContext is bottom-left, so y flips.
    static func image(_ points: [StipplePoint], width: Int, height: Int) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw EffectError.renderFailed
        }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 0, alpha: 1)
        for point in points {
            context.fillEllipse(in: CGRect(
                x: point.x - point.radius,
                y: Double(height) - point.y - point.radius,
                width: point.radius * 2,
                height: point.radius * 2
            ))
        }
        guard let image = context.makeImage() else {
            throw EffectError.renderFailed
        }
        return image
    }
}
