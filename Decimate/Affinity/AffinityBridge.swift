import CoreGraphics
import Foundation
import Observation

/// MCP client for Affinity's local script bridge. Speaks the MCP handshake
/// (initialize → initialized → read-preamble) over `MCPClient`, then runs
/// scripts via `execute_script`. The bulk-data round-trip (Pull/Send) layers
/// on top of `execute` and a Desktop temp file.
@MainActor
@Observable
final class AffinityBridge {
    enum Status: Equatable {
        case disconnected
        case connecting
        case connected
        case affinityUnavailable        // MCP unreachable — Affinity closed or AI connector off
        case permissionDenied(String)   // filesystem / script access not granted in Affinity
        case failed(String)

        var isConnected: Bool { self == .connected }

        /// Human-readable status / setup guidance for the UI.
        var message: String {
            switch self {
            case .disconnected: "Not connected to Affinity."
            case .connecting: "Connecting to Affinity…"
            case .connected: "Connected to Affinity."
            case .affinityUnavailable:
                "Affinity isn't reachable. Open Affinity and turn on its AI connector (it serves localhost:6767)."
            case .permissionDenied:
                "Affinity blocked filesystem access. Enable Affinity → Preferences → General → “Allow scripts to access the filesystem.”"
            case .failed(let detail): detail
            }
        }
    }

    enum PullError: LocalizedError {
        case noDocument
        case unreadable

        var errorDescription: String? {
            switch self {
            case .noDocument: "Affinity has no open document to pull."
            case .unreadable: "Couldn't read the image Affinity exported."
            }
        }
    }

    private(set) var status: Status = .disconnected

    private let baseURL: URL
    private var client: MCPClient?

    /// Affinity's MCP errors with this until the preamble doc is read in-session.
    static let preamblePrompt = "preamble documentation topic has not yet been read"

    init(baseURL: URL = URL(string: "http://localhost:6767")!) {
        self.baseURL = baseURL
    }

    // MARK: - Connection

    /// Opens the stream, runs the MCP handshake, and reads the preamble so that
    /// later `execute_script` calls are accepted. Sets `status` accordingly.
    func connect() async {
        if status == .connecting { return }
        status = .connecting

        let client = MCPClient(baseURL: baseURL)
        await client.onDisconnect { [weak self] error in
            Task { @MainActor in self?.handleDisconnect(error) }
        }

        do {
            try await client.connect()
            self.client = client
            try await initializeSession()
            try await readPreamble()
            status = .connected
        } catch {
            self.client = nil
            await client.disconnect()
            status = Self.classify(error)
        }
    }

    func disconnect() async {
        await client?.disconnect()
        client = nil
        status = .disconnected
    }

    /// Connects if not already connected. Safe to call before each operation.
    func ensureConnected() async {
        if status != .connected { await connect() }
    }

    // MARK: - Pull

    /// Exports the active Affinity document at full resolution to a Desktop temp
    /// file, loads it as a CGImage, then removes the temp file.
    func pull() async throws -> CGImage {
        let filename = "decimate-pull-\(UUID().uuidString).png"
        let output = try await execute(Self.pullScript(filename: filename))
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("OK:") {
            let url = URL(fileURLWithPath: String(trimmed.dropFirst(3)))
            defer { try? FileManager.default.removeItem(at: url) }
            guard let image = try? ImageLoader.loadCGImage(from: url) else {
                throw PullError.unreadable
            }
            return image
        }
        if trimmed.contains("NO_DOCUMENT") { throw PullError.noDocument }

        let message = trimmed.hasPrefix("ERR:") ? String(trimmed.dropFirst(4)) : trimmed
        let upper = message.uppercased()
        if upper.contains("PERMISSION_DENIED") || upper.contains("NOT_ALLOWED") {
            status = .permissionDenied(message)
        }
        throw MCPClient.ClientError.rpc(code: -1, message: message)
    }

    /// Full-res whole-document PNG export to a Desktop temp file. Prints
    /// `OK:<path>` on success or `ERR:<reason>` (e.g. NO_DOCUMENT, PERMISSION_DENIED).
    private static func pullScript(filename: String) -> String {
        """
        try {
          const { app } = require('/application');
          const { FileExportOptions, FileExportArea } = require('/document');
          const doc = app.documents.current;
          if (!doc) { console.log('ERR:NO_DOCUMENT'); }
          else {
            const path = app.userDesktopPath + '/\(filename)';
            const opts = FileExportOptions.createWithPresetName('PNG');
            const area = FileExportArea.createForWholeDocument();
            doc.export(path, opts, area);
            console.log('OK:' + path);
          }
        } catch (e) { console.log('ERR:' + e); }
        """
    }

    private func initializeSession() async throws {
        guard let client else { throw MCPClient.ClientError.notConnected }
        let params: JSONValue = .object([
            "protocolVersion": .string("2025-11-25"),  // the only version Affinity's bridge accepts
            "capabilities": .object([:]),
            "clientInfo": .object(["name": .string("Decimate"), "version": .string("2.0")]),
        ])
        _ = try await client.request(method: "initialize", params: params)
        try await client.notify(method: "notifications/initialized", params: .object([:]))
    }

    /// Mandatory handshake: Affinity rejects `execute_script` until the preamble
    /// SDK doc has been read in the same MCP session.
    func readPreamble() async throws {
        _ = try await callTool(
            name: "read_sdk_documentation_topic",
            arguments: .object(["filename": .string("preamble")])
        )
    }

    // MARK: - Scripting

    /// Runs a JavaScript snippet in Affinity and returns its console output.
    @discardableResult
    func execute(_ script: String) async throws -> String {
        let result = try await callTool(name: "execute_script", arguments: .object(["script": .string(script)]))
        return Self.text(from: result)
    }

    /// Calls an MCP tool and returns its raw result, surfacing tool-reported
    /// errors (`isError: true`) as thrown `rpc` errors.
    @discardableResult
    func callTool(name: String, arguments: JSONValue) async throws -> JSONValue {
        guard let client else { throw MCPClient.ClientError.notConnected }
        let params: JSONValue = .object(["name": .string(name), "arguments": arguments])
        let result = try await client.request(method: "tools/call", params: params)
        if result["isError"]?.boolValue == true {
            throw MCPClient.ClientError.rpc(code: -1, message: Self.text(from: result))
        }
        return result
    }

    // MARK: - Helpers

    /// Concatenates the text from an MCP tool result's `content` array.
    static func text(from result: JSONValue) -> String {
        guard let content = result["content"]?.arrayValue else {
            return result.stringValue ?? ""
        }
        return content.compactMap { $0["text"]?.stringValue }.joined(separator: "\n")
    }

    private func handleDisconnect(_ error: Error) {
        client = nil
        if status == .connected || status == .connecting {
            status = Self.classify(error)
        }
    }

    static func classify(_ error: Error) -> Status {
        if let rpc = error as? MCPClient.ClientError {
            switch rpc {
            case .connectionFailed, .timeout, .notConnected, .endpointMissing:
                return .affinityUnavailable
            case .rpc(_, let message):
                let upper = message.uppercased()
                if upper.contains("NOT_ALLOWED") || upper.contains("PERMISSION_DENIED") || upper.contains("FILESYSTEM") {
                    return .permissionDenied(message)
                }
                return .failed(message)
            }
        }
        // URLError (connection refused etc.) — Affinity isn't reachable.
        if error is URLError { return .affinityUnavailable }
        return .failed(error.localizedDescription)
    }
}
