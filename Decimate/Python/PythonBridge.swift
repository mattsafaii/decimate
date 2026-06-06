import CoreGraphics
import Foundation

/// File-based CLI contract with bundled Python scripts:
/// Swift writes input.pgm (8-bit grayscale) and params.json into a fresh temp
/// work dir, invokes `venv/bin/python3 <script>.py <workdir>`, and reads
/// workdir/output.json back. PGM keeps the scripts dependency-light — no
/// image library needed to read the input.
@MainActor
struct PythonBridge {
    let environment: PythonEnvironment

    enum BridgeError: LocalizedError {
        case environmentNotReady
        case scriptMissing(String)
        case scriptFailed(String)
        case outputMissing

        var errorDescription: String? {
            switch self {
            case .environmentNotReady:
                "The Python environment isn't ready yet."
            case .scriptMissing(let name):
                "Bundled script \(name).py is missing — reinstall Decimate."
            case .scriptFailed(let message):
                "Python script failed: \(message)"
            case .outputMissing:
                "Python script produced no output."
            }
        }
    }

    /// Runs a bundled script against the venv and returns the raw output.json data.
    func run(script name: String, image: CGImage, parameters: [String: ParameterValue]) async throws -> Data {
        guard environment.status == .ready else { throw BridgeError.environmentNotReady }
        guard let scriptURL = Bundle.main.url(forResource: name, withExtension: "py", subdirectory: "python") else {
            throw BridgeError.scriptMissing(name)
        }

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("decimate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        try Self.writePGM(image, to: workDirectory.appendingPathComponent("input.pgm"))
        let paramsData = try JSONSerialization.data(withJSONObject: Self.jsonObject(from: parameters))
        try paramsData.write(to: workDirectory.appendingPathComponent("params.json"))

        let result = try await Subprocess.run(environment.venvPython, [scriptURL.path, workDirectory.path])
        guard result.exitCode == 0 else {
            throw BridgeError.scriptFailed(String(result.stderrText.suffix(500)))
        }

        guard let output = try? Data(contentsOf: workDirectory.appendingPathComponent("output.json")) else {
            throw BridgeError.outputMissing
        }
        return output
    }

    static func jsonObject(from parameters: [String: ParameterValue]) -> [String: Any] {
        parameters.mapValues { value -> Any in
            switch value {
            case .double(let double): double
            case .integer(let int): int
            case .choice(let choice): choice
            }
        }
    }

    /// 8-bit grayscale binary PGM (P5).
    static func writePGM(_ image: CGImage, to url: URL) throws {
        let (pixels, width, height) = try PixelEngine.grayscaleBuffer(from: image)
        var data = Data("P5\n\(width) \(height)\n255\n".utf8)
        data.append(contentsOf: pixels)
        try data.write(to: url)
    }
}
