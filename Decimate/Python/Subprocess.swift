import Foundation

/// Minimal async subprocess runner. Output is captured via temp files
/// (not pipes) so large output can never deadlock the child.
enum Subprocess {
    struct Result {
        let exitCode: Int32
        let stdout: Data
        let stderr: Data

        var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
        var stderrText: String { String(decoding: stderr, as: UTF8.self) }
    }

    @discardableResult
    static func run(_ executablePath: String, _ arguments: [String]) async throws -> Result {
        let tempDirectory = FileManager.default.temporaryDirectory
        let outURL = tempDirectory.appendingPathComponent("decimate-out-\(UUID().uuidString)")
        let errURL = tempDirectory.appendingPathComponent("decimate-err-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: outURL)
            try? FileManager.default.removeItem(at: errURL)
        }

        let outHandle = try FileHandle(forWritingTo: outURL)
        let errHandle = try FileHandle(forWritingTo: errURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = outHandle
        process.standardError = errHandle
        process.standardInput = FileHandle.nullDevice

        let exitCode: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        try? outHandle.close()
        try? errHandle.close()
        return Result(
            exitCode: exitCode,
            stdout: (try? Data(contentsOf: outURL)) ?? Data(),
            stderr: (try? Data(contentsOf: errURL)) ?? Data()
        )
    }
}
