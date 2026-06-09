import CoreGraphics
import Foundation

/// Renders stroked vector paths (engraving / line-screen lines) to SVG or PNG.
/// Rendering is independent of how paths were produced, mirroring StippleRenderer.
enum PathRenderer {
    /// SVG document: black polylines on a transparent background — imports into
    /// Affinity as editable vector curves. Stroked, or filled for closed shapes.
    static func svg(_ paths: [VectorPath], width: Int, height: Int, strokeWidth: Double, filled: Bool) -> Data {
        let style = filled
            ? "fill=\"black\" stroke=\"none\""
            : "fill=\"none\" stroke=\"black\" stroke-width=\"\(strokeWidth)\" stroke-linecap=\"round\" stroke-linejoin=\"round\""
        var doc = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)">
        <g \(style)>

        """
        for path in paths where path.points.count > 1 {
            let coords = path.points.map { "\($0.x),\($0.y)" }.joined(separator: " ")
            let tag = (path.closed || filled) ? "polygon" : "polyline"
            doc += "<\(tag) points=\"\(coords)\"/>\n"
        }
        doc += "</g>\n</svg>\n"
        return Data(doc.utf8)
    }

    /// Raster render: black on white. Path coordinates are top-left origin
    /// (image space); CGContext is bottom-left, so y flips.
    static func image(_ paths: [VectorPath], width: Int, height: Int, strokeWidth: Double, filled: Bool) throws -> CGImage {
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
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setFillColor(gray: 0, alpha: 1)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let flip = Double(height)
        for path in paths where path.points.count > 1 {
            let flipped = path.points.map { CGPoint(x: $0.x, y: flip - $0.y) }
            context.beginPath()
            context.addLines(between: flipped)
            if filled {
                context.closePath()
                context.fillPath()
            } else {
                if path.closed { context.closePath() }
                context.strokePath()
            }
        }
        guard let image = context.makeImage() else {
            throw EffectError.renderFailed
        }
        return image
    }
}
