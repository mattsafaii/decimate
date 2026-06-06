import CoreGraphics
import Foundation
import ImageIO

enum ImageLoader {
    enum LoadError: Error {
        case unreadable
    }

    static func loadCGImage(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw LoadError.unreadable
        }
        return image
    }
}
