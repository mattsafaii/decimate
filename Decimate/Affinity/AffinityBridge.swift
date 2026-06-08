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
