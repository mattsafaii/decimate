import Foundation

/// JSON-RPC 2.0 over the MCP HTTP+SSE transport, built on URLSession alone —
/// no third-party dependency.
///
/// Transport: `GET <baseURL>/sse` opens a long-lived event stream. The server's
/// first `endpoint` event names the URL to POST requests to. Each POST returns
/// 202; the matching JSON-RPC response arrives back over the stream as a
/// `message` event, correlated to its request by `id`.
actor MCPClient {
    enum ClientError: LocalizedError, Equatable {
        case notConnected
        case connectionFailed(String)
        case endpointMissing
        case rpc(code: Int, message: String)
        case timeout

        var errorDescription: String? {
            switch self {
            case .notConnected: "Not connected to Affinity."
            case .connectionFailed(let detail): "Couldn't reach Affinity's script bridge (\(detail))."
            case .endpointMissing: "Affinity's bridge never sent a message endpoint."
            case .rpc(_, let message): message
            case .timeout: "Affinity didn't respond in time."
            }
        }
    }

    private let baseURL: URL
    private let session: URLSession
    private let requestTimeout: Duration

    private var postEndpoint: URL?
    private var streamTask: Task<Void, Never>?
    private var endpointContinuation: CheckedContinuation<URL, Error>?
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var nextID = 1

    /// Invoked once when the event stream ends or errors after a successful
    /// connect. Lets the bridge reflect a dropped connection in its status.
    private var disconnectHandler: (@Sendable (Error) -> Void)?

    // Generous: a full-res export of a large document can take ~30s+.
    init(baseURL: URL, requestTimeout: Duration = .seconds(180)) {
        self.baseURL = baseURL
        self.requestTimeout = requestTimeout
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = .infinity  // the SSE stream is long-lived
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    func onDisconnect(_ handler: @escaping @Sendable (Error) -> Void) {
        disconnectHandler = handler
    }

    /// Opens the SSE stream and waits for the server to name its POST endpoint.
    func connect() async throws {
        let sseURL = baseURL.appendingPathComponent("sse")
        var request = URLRequest(url: sseURL)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 3600

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.connectionFailed("no HTTP response")
        }
        guard http.statusCode == 200 else {
            throw ClientError.connectionFailed("status \(http.statusCode)")
        }

        let endpoint = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            endpointContinuation = cont
            streamTask = Task { await readStream(bytes) }
        }
        postEndpoint = endpoint
    }

    func disconnect() {
        streamTask?.cancel()
        streamTask = nil
        postEndpoint = nil
        failAll(ClientError.notConnected)
    }

    // MARK: - JSON-RPC

    /// Sends a request and awaits its response (delivered over the SSE stream).
    func request(method: String, params: JSONValue) async throws -> JSONValue {
        guard let endpoint = postEndpoint else { throw ClientError.notConnected }
        let id = nextID
        nextID += 1

        let envelope: JSONValue = .object([
            "jsonrpc": .string("2.0"),
            "id": .number(Double(id)),
            "method": .string(method),
            "params": params,
        ])
        let body = try JSONEncoder().encode(envelope)

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<JSONValue, Error>) in
            pending[id] = cont
            Task { await post(body: body, endpoint: endpoint, requestID: id) }
            Task {
                try? await Task.sleep(for: requestTimeout)
                failRequest(id, ClientError.timeout)
            }
        }
    }

    /// Sends a notification (no id, no response expected).
    func notify(method: String, params: JSONValue) async throws {
        guard let endpoint = postEndpoint else { throw ClientError.notConnected }
        let envelope: JSONValue = .object([
            "jsonrpc": .string("2.0"),
            "method": .string(method),
            "params": params,
        ])
        let body = try JSONEncoder().encode(envelope)
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        _ = try await session.data(for: req)
    }

    private func post(body: Data, endpoint: URL, requestID: Int) async {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        do {
            let (_, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                failRequest(requestID, ClientError.connectionFailed("POST status \(http.statusCode)"))
            }
            // success: the JSON-RPC response arrives over the SSE stream
        } catch {
            failRequest(requestID, error)
        }
    }

    private func failRequest(_ id: Int, _ error: Error) {
        if let cont = pending.removeValue(forKey: id) {
            cont.resume(throwing: error)
        }
    }

    private func failAll(_ error: Error) {
        let conts = pending.values
        pending.removeAll()
        for cont in conts { cont.resume(throwing: error) }
        if let endpointContinuation {
            endpointContinuation.resume(throwing: error)
            self.endpointContinuation = nil
        }
    }

    // MARK: - SSE stream

    private func readStream(_ bytes: URLSession.AsyncBytes) async {
        var event = "message"
        var dataLines: [String] = []
        var lineBytes: [UInt8] = []

        // SSE delimits events with a blank line. `AsyncLineSequence` drops blank
        // lines, so we split the raw byte stream ourselves to preserve them.
        func handle(_ line: String) {
            if line.isEmpty {
                if !dataLines.isEmpty || event != "message" {
                    dispatch(event: event, data: dataLines.joined(separator: "\n"))
                }
                event = "message"
                dataLines.removeAll()
            } else if line.hasPrefix(":") {
                return  // comment / keep-alive
            } else if let value = field("event", in: line) {
                event = value
            } else if let value = field("data", in: line) {
                dataLines.append(value)
            }
        }

        do {
            for try await byte in bytes {
                if byte == 0x0A {  // \n
                    var line = String(decoding: lineBytes, as: UTF8.self)
                    if line.hasSuffix("\r") { line.removeLast() }
                    lineBytes.removeAll(keepingCapacity: true)
                    handle(line)
                } else {
                    lineBytes.append(byte)
                }
            }
            handleStreamEnd(ClientError.connectionFailed("stream closed"))
        } catch {
            handleStreamEnd(error)
        }
    }

    private func field(_ name: String, in line: String) -> String? {
        guard line.hasPrefix(name + ":") else { return nil }
        let value = line.dropFirst(name.count + 1)
        return String(value.hasPrefix(" ") ? value.dropFirst() : value)
    }

    private func dispatch(event: String, data: String) {
        switch event {
        case "endpoint":
            guard let url = URL(string: data, relativeTo: baseURL)?.absoluteURL else { return }
            endpointContinuation?.resume(returning: url)
            endpointContinuation = nil
        case "message":
            guard let messageData = data.data(using: .utf8),
                  let message = try? JSONDecoder().decode(JSONValue.self, from: messageData) else { return }
            guard let id = message["id"]?.numberValue.flatMap({ Int(exactly: $0) }) else { return }
            guard let cont = pending.removeValue(forKey: id) else { return }
            if let error = message["error"] {
                let code = error["code"]?.numberValue.flatMap { Int(exactly: $0) } ?? 0
                let text = error["message"]?.stringValue ?? "unknown error"
                cont.resume(throwing: ClientError.rpc(code: code, message: text))
            } else {
                cont.resume(returning: message["result"] ?? .null)
            }
        default:
            break
        }
    }

    private func handleStreamEnd(_ error: Error) {
        let wasConnected = postEndpoint != nil
        failAll(error)
        postEndpoint = nil
        if wasConnected { disconnectHandler?(error) }
    }
}
