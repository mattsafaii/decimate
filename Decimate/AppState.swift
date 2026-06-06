import CoreGraphics
import Foundation
import Observation

/// Shared state for the main window: loaded image, selected effect,
/// and per-effect parameter values.
@MainActor
@Observable
final class AppState {
    let pythonEnvironment = PythonEnvironment()
    var sourceImage: CGImage?
    var sourceURL: URL?
    var selectedEffectID: String?
    var parameterValues: [String: [String: ParameterValue]] = [:]
    var isImporterPresented = false
    var loadErrorMessage: String?

    var selectedEffect: (any Effect)? {
        selectedEffectID.flatMap { EffectCatalog.effect(id: $0) }
    }

    func loadImage(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            sourceImage = try ImageLoader.loadCGImage(from: url)
            sourceURL = url
        } catch {
            loadErrorMessage = "Couldn't open \(url.lastPathComponent) as an image."
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
