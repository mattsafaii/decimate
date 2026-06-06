import Foundation
import Observation

/// Manages the app-owned Python venv under ~/Library/Application Support/Decimate.
/// Created on first launch from the bundled python/requirements.txt; later
/// launches see the install marker and skip straight to ready. Only
/// Python-engine effects are blocked while setup runs — the app stays usable.
@MainActor
@Observable
final class PythonEnvironment {
    enum Status: Equatable {
        case checking
        case settingUp(String)
        case ready
        case failed(String)
    }

    static let shared = PythonEnvironment()

    private(set) var status: Status = .checking

    let venvDirectory: URL
    var venvPython: String { venvDirectory.appendingPathComponent("bin/python3").path }
    private var venvPip: String { venvDirectory.appendingPathComponent("bin/pip3").path }
    private var installMarker: URL { venvDirectory.appendingPathComponent(".requirements-installed") }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        venvDirectory = appSupport.appendingPathComponent("Decimate/venv")
    }

    /// Paths where python3 typically lives. GUI apps don't inherit a shell
    /// PATH, so we probe known locations instead of `which`.
    private static let pythonCandidates = [
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3",
        "/usr/bin/python3",
    ]

    func setUpIfNeeded() async {
        guard status == .checking || isFailed else { return }

        guard let requirementsURL = Bundle.main.url(forResource: "requirements", withExtension: "txt", subdirectory: "python"),
              let requirements = try? String(contentsOf: requirementsURL, encoding: .utf8) else {
            status = .failed("Bundled python/requirements.txt is missing — reinstall Decimate.")
            return
        }

        // Skip on later launches: venv exists and was installed from these exact requirements.
        if FileManager.default.fileExists(atPath: venvPython),
           let installed = try? String(contentsOf: installMarker, encoding: .utf8),
           installed == requirements {
            status = .ready
            return
        }

        do {
            status = .settingUp("Locating Python 3…")
            guard let systemPython = await Self.findSystemPython() else {
                status = .failed("Python 3 wasn't found. Install it (e.g. brew install python) and relaunch Decimate.")
                return
            }

            // A venv without a marker is a leftover from an interrupted setup — rebuild it.
            if FileManager.default.fileExists(atPath: venvDirectory.path) {
                try FileManager.default.removeItem(at: venvDirectory)
            }
            try FileManager.default.createDirectory(
                at: venvDirectory.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            status = .settingUp("Creating Python environment…")
            let venvResult = try await Subprocess.run(systemPython, ["-m", "venv", venvDirectory.path])
            guard venvResult.exitCode == 0 else {
                status = .failed("Couldn't create the Python environment: \(venvResult.stderrText.suffix(300))")
                return
            }

            status = .settingUp("Installing packages (SciPy) — this can take a minute…")
            let pipResult = try await Subprocess.run(venvPip, ["install", "-r", requirementsURL.path])
            guard pipResult.exitCode == 0 else {
                status = .failed("Package install failed: \(pipResult.stderrText.suffix(300))")
                return
            }

            try requirements.write(to: installMarker, atomically: true, encoding: .utf8)
            status = .ready
        } catch {
            status = .failed("Python setup failed: \(error.localizedDescription)")
        }
    }

    private var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    private static func findSystemPython() async -> String? {
        for candidate in pythonCandidates where FileManager.default.isExecutableFile(atPath: candidate) {
            if let result = try? await Subprocess.run(candidate, ["--version"]), result.exitCode == 0 {
                return candidate
            }
        }
        return nil
    }
}
