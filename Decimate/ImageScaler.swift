import CoreGraphics

enum ImageScaler {
    /// Returns the image scaled so its longest side is at most `maxDimension`.
    /// Returns the original when it's already small enough.
    static func downsample(_ image: CGImage, maxDimension: Int) -> CGImage {
        let width = image.width
        let height = image.height
        let longest = max(width, height)
        guard longest > maxDimension else { return image }

        let scale = Double(maxDimension) / Double(longest)
        let newWidth = max(1, Int((Double(width) * scale).rounded()))
        let newHeight = max(1, Int((Double(height) * scale).rounded()))

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage() ?? image
    }
}
