import CoreGraphics
import Foundation
import Observation

/// Shared state for the main window: loaded image, selected effect,
/// and per-effect parameter values.
@MainActor
@Observable
final class AppState {
    let pythonEnvironment = PythonEnvironment.shared
    let affinity = AffinityBridge()
    var sourceImage: CGImage?
    var sourceURL: URL?
    var isPullingFromAffinity = false
    var isSendingToAffinity = false
    var affinityErrorMessage: String?
    var selectedEffectID: String?
    var parameterValues: [String: [String: ParameterValue]] = [:]
    var isImporterPresented = false
    var loadErrorMessage: String?
    var previewImage: CGImage?
    var isRenderingPreview = false
    var renderErrorMessage: String?
    var isExporting = false
    var exportErrorMessage: String?

    private var previewTask: Task<Void, Never>?

    var selectedEffect: (any Effect)? {
        selectedEffectID.flatMap { EffectCatalog.effect(id: $0) }
    }

    func loadImage(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            sourceImage = try ImageLoader.loadCGImage(from: url)
            sourceURL = url
            schedulePreviewRender()
        } catch {
            loadErrorMessage = "Couldn't open \(url.lastPathComponent) as an image."
        }
    }

    // MARK: - Affinity

    /// Pulls the active Affinity document at full resolution into the preview.
    func pullFromAffinity() {
        Task {
            isPullingFromAffinity = true
            defer { isPullingFromAffinity = false }
            await affinity.ensureConnected()
            guard affinity.status == .connected else {
                affinityErrorMessage = affinity.status.message
                return
            }
            do {
                sourceImage = try await affinity.pull()
                sourceURL = nil
                schedulePreviewRender()
            } catch {
                affinityErrorMessage = error.localizedDescription
            }
        }
    }

    /// Renders the selected effect at full resolution and sends the result to
    /// Affinity as a new layer (raster or editable curves per output type).
    func sendToAffinity() {
        guard let source = sourceImage, let effect = selectedEffect else { return }
        let declaration = effect.declaration
        let values = parameterValues[declaration.id] ?? declaration.defaultParameterValues
        Task {
            isSendingToAffinity = true
            defer { isSendingToAffinity = false }
            await affinity.ensureConnected()
            guard affinity.status == .connected else {
                affinityErrorMessage = affinity.status.message
                return
            }
            do {
                let output = try await effect.render(input: source, parameters: values)
                let description = "Decimate: \(declaration.name)"
                switch output {
                case .image(let image):
                    try await affinity.sendRaster(pngData: Self.pngData(image), description: description)
                case .points(let points):
                    try await affinity.sendVector(points, width: source.width, height: source.height, description: description)
                }
            } catch {
                affinityErrorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Preview pipeline

    /// Longest preview side per engine. Python effects (full Voronoi can take
    /// minutes at full res) preview on a much smaller copy.
    private static func previewCap(for engine: EffectEngine) -> Int {
        switch engine {
        case .python: 600
        case .coreImage, .swiftPixel: 1200
        }
    }

    /// Debounced, cancellable preview render on a downsampled copy of the source.
    func schedulePreviewRender() {
        previewTask?.cancel()
        guard let source = sourceImage, let effect = selectedEffect else {
            previewImage = nil
            isRenderingPreview = false
            renderErrorMessage = nil
            return
        }
        let declaration = effect.declaration
        let values = parameterValues[declaration.id] ?? declaration.defaultParameterValues

        previewTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))  // debounce slider drags
                isRenderingPreview = true
                let downsampled = ImageScaler.downsample(source, maxDimension: Self.previewCap(for: declaration.engine))
                let output = try await effect.render(input: downsampled, parameters: values)
                try Task.checkCancellation()
                switch output {
                case .image(let image):
                    previewImage = image
                case .points(let points):
                    previewImage = try StippleRenderer.image(points, width: downsampled.width, height: downsampled.height)
                }
                renderErrorMessage = nil
                isRenderingPreview = false
            } catch is CancellationError {
                // superseded by a newer render — leave state to the newer task
            } catch {
                renderErrorMessage = error.localizedDescription
                isRenderingPreview = false
            }
        }
    }

    /// Seed defaults the first time an effect is selected.
    func ensureParameterValues(for effectID: String?) {
        guard let effectID,
              parameterValues[effectID] == nil,
              let effect = EffectCatalog.effect(id: effectID) else { return }
        parameterValues[effectID] = effect.declaration.defaultParameterValues
    }
}
