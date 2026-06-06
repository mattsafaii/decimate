import AppKit
import Foundation

/// Headless verification hooks for build tooling, driven by launch arguments:
///   -openImage <path>    load an image at launch (real ImageLoader path)
///   -applyEffect <id>    select an effect and render its preview
///   -verifyDump <dir>    write source.png, preview.png, full-res exports, and
///                        status.json into <dir>, then quit
/// Inert when the arguments are absent.
@MainActor
enum DebugHarness {
    /// Read `-name value` straight from the argument list — UserDefaults
    /// tries to plist-parse values, which mangles JSON arguments.
    private static func argument(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-\(name)"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static func run(state: AppState) async {
        let openImage = argument("openImage")
        let applyEffect = argument("applyEffect")
        let verifyDump = argument("verifyDump")
        guard openImage != nil || applyEffect != nil || verifyDump != nil else { return }

        if let openImage {
            state.loadImage(from: URL(fileURLWithPath: openImage))
        }
        if let applyEffect {
            state.selectedEffectID = applyEffect
            state.ensureParameterValues(for: applyEffect)
            if let paramsJSON = argument("paramsJSON"),
               let overrides = try? JSONSerialization.jsonObject(with: Data(paramsJSON.utf8)) as? [String: Any] {
                var values = state.parameterValues[applyEffect] ?? [:]
                for (key, value) in overrides {
                    if let int = value as? Int {
                        values[key] = .integer(int)
                    } else if let double = value as? Double {
                        values[key] = .double(double)
                    } else if let string = value as? String {
                        values[key] = .choice(string)
                    }
                }
                state.parameterValues[applyEffect] = values
            }
            state.schedulePreviewRender()
        }
        guard let verifyDump else { return }

        let directory = URL(fileURLWithPath: verifyDump)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var status: [String: Any] = [:]

        if let source = state.sourceImage {
            status["sourceWidth"] = source.width
            status["sourceHeight"] = source.height
            if let data = try? AppState.pngData(source) {
                try? data.write(to: directory.appendingPathComponent("source.png"))
            }
        }
        status["sourceLoaded"] = state.sourceImage != nil
        status["loadError"] = state.loadErrorMessage ?? NSNull()

        if let effect = state.selectedEffect {
            status["effect"] = effect.declaration.id

            if effect.declaration.engine == .python {
                await waitUntil(timeout: 300) { state.pythonEnvironment.status == .ready || isEnvFailed(state) }
                status["pythonEnvironment"] = describeEnv(state)
            }

            let started = Date()
            await waitUntil(timeout: 300) { state.previewImage != nil || state.renderErrorMessage != nil }
            status["previewSeconds"] = Date().timeIntervalSince(started)
            status["renderError"] = state.renderErrorMessage ?? NSNull()
            if let preview = state.previewImage {
                status["previewWidth"] = preview.width
                status["previewHeight"] = preview.height
                if let data = try? AppState.pngData(preview) {
                    try? data.write(to: directory.appendingPathComponent("preview.png"))
                }
            }

            // Full-res export of every declared format, same primitives as Exporter
            if let source = state.sourceImage {
                let values = state.parameterValues[effect.declaration.id] ?? effect.declaration.defaultParameterValues
                var exports: [String: Any] = [:]
                do {
                    let output = try await effect.render(input: source, parameters: values)
                    for format in effect.declaration.outputFormats {
                        let url = directory.appendingPathComponent("export.\(format.rawValue)")
                        let data: Data
                        switch (output, format) {
                        case (.image(let image), _):
                            data = try AppState.pngData(image)
                        case (.points(let points), .svg):
                            data = StippleRenderer.svg(points, width: source.width, height: source.height)
                        case (.points(let points), .png):
                            data = try AppState.pngData(StippleRenderer.image(points, width: source.width, height: source.height))
                        }
                        try data.write(to: url)
                        exports[format.rawValue] = data.count
                    }
                    if case .points(let points) = output {
                        status["pointCount"] = points.count
                    }
                } catch {
                    exports["error"] = "\(error)"
                }
                status["exports"] = exports
            }
        }

        let json = try? JSONSerialization.data(withJSONObject: status, options: [.sortedKeys, .prettyPrinted])
        try? json?.write(to: directory.appendingPathComponent("status.json"))
        try? Data("done\n".utf8).write(to: directory.appendingPathComponent("done"))
        exit(0)
    }

    private static func isEnvFailed(_ state: AppState) -> Bool {
        if case .failed = state.pythonEnvironment.status { return true }
        return false
    }

    private static func describeEnv(_ state: AppState) -> String {
        switch state.pythonEnvironment.status {
        case .checking: "checking"
        case .settingUp(let message): "settingUp: \(message)"
        case .ready: "ready"
        case .failed(let message): "failed: \(message)"
        }
    }

    private static func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
