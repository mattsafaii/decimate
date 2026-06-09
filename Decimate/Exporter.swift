import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

extension OutputFormat {
    var utType: UTType {
        switch self {
        case .png: .png
        case .svg: .svg
        }
    }
}

extension AppState {
    /// Save dialog offering the formats the selected effect declares, then a
    /// full-resolution render written to the chosen URL.
    func export() {
        guard let source = sourceImage, let effect = selectedEffect else { return }
        let declaration = effect.declaration
        let values = parameterValues[declaration.id] ?? declaration.defaultParameterValues

        let panel = NSSavePanel()
        panel.allowedContentTypes = declaration.outputFormats.map(\.utType)
        panel.showsContentTypes = declaration.outputFormats.count > 1
        let baseName = sourceURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        panel.nameFieldStringValue = "\(baseName)-\(declaration.id)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let format = declaration.outputFormats.first { $0.rawValue == url.pathExtension.lowercased() }
            ?? declaration.outputFormats[0]

        isExporting = true
        Task {
            do {
                let output = try await effect.render(input: source, parameters: values)
                let data: Data
                switch (output, format) {
                case (.image(let image), _):
                    data = try Self.pngData(image)
                case (.points(let points), .svg):
                    data = StippleRenderer.svg(points, width: source.width, height: source.height)
                case (.points(let points), .png):
                    data = try Self.pngData(StippleRenderer.image(points, width: source.width, height: source.height))
                case (.paths(let paths, let strokeWidth), .svg):
                    data = PathRenderer.svg(paths, width: source.width, height: source.height, strokeWidth: strokeWidth)
                case (.paths(let paths, let strokeWidth), .png):
                    data = try Self.pngData(PathRenderer.image(paths, width: source.width, height: source.height, strokeWidth: strokeWidth))
                }
                try data.write(to: url)
            } catch {
                exportErrorMessage = error.localizedDescription
            }
            isExporting = false
        }
    }

    static func pngData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw EffectError.renderFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw EffectError.renderFailed
        }
        return data as Data
    }
}
