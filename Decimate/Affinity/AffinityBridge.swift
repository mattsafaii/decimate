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

        /// Short label for the status indicator.
        var shortTitle: String {
            switch self {
            case .disconnected: "Not connected"
            case .connecting: "Connecting…"
            case .connected: "Connected"
            case .affinityUnavailable: "Affinity not reachable"
            case .permissionDenied: "Permission needed"
            case .failed: "Error"
            }
        }

        /// True when the status warrants showing the setup-guidance message.
        var needsSetup: Bool {
            switch self {
            case .affinityUnavailable, .permissionDenied, .failed: true
            case .disconnected, .connecting, .connected: false
            }
        }

        /// Human-readable status / setup guidance for the UI.
        var message: String {
            switch self {
            case .disconnected: "Not connected to Affinity."
            case .connecting: "Connecting to Affinity…"
            case .connected: "Connected to Affinity."
            case .affinityUnavailable:
                "Affinity isn't reachable. Open Affinity and turn on its AI connector, which serves localhost:6767."
            case .permissionDenied:
                "Affinity blocked script access. In Affinity → Preferences → General, enable the AI connector and “Allow scripts to access the filesystem.”"
            case .failed(let detail): detail
            }
        }
    }

    enum AffinityError: LocalizedError {
        case noDocument
        case unreadable

        var errorDescription: String? {
            switch self {
            case .noDocument: "Affinity has no open document."
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

        guard trimmed.hasPrefix("OK:") else { throw errorFor(trimmed) }
        let url = URL(fileURLWithPath: String(trimmed.dropFirst(3)))
        defer { try? FileManager.default.removeItem(at: url) }
        guard let image = try? ImageLoader.loadCGImage(from: url) else {
            throw AffinityError.unreadable
        }
        return image
    }

    // MARK: - Send (raster)

    /// Writes the processed PNG to a Desktop temp file and injects it into the
    /// active document as a new raster layer via `Bitmap.loadFromFile` +
    /// `AddChildNodesCommandBuilder`, then removes the temp file.
    func sendRaster(pngData: Data, description: String) async throws {
        let url = Self.desktopURL("decimate-send-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try pngData.write(to: url)
        let output = try await execute(Self.sendRasterScript(path: url.path, description: description))
        if !output.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("OK") {
            throw errorFor(output)
        }
    }

    // MARK: - Send (vector)

    /// Injects stipple dots into the active document as a single editable
    /// PolyCurve node — one filled ellipse per dot — via `Curve.createEllipse`
    /// + `PolyCurveNodeDefinition`. Geometry travels in the script itself (no
    /// temp file): dots are compact and need no Desktop access.
    func sendVector(_ points: [StipplePoint], description: String) async throws {
        let dots = points.map { [$0.x, $0.y, $0.radius] }
        let dotsJSON = (try? JSONSerialization.data(withJSONObject: dots))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let output = try await execute(Self.sendVectorScript(dotsJSON: dotsJSON, description: description))
        if !output.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("OK") {
            throw errorFor(output)
        }
    }

    /// Injects polylines (engraving / line-screen) into the active document as a
    /// single editable PolyCurve node built with `CurveBuilder`. Stroked when
    /// `filled` is false; filled (closed) when true.
    func sendCurves(_ paths: [VectorPath], strokeWidth: Double, filled: Bool, description: String) async throws {
        let lines = paths
            .filter { $0.points.count > 1 }
            .map { path in path.points.map { [$0.x, $0.y] } }
        let linesJSON = (try? JSONSerialization.data(withJSONObject: lines))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let output = try await execute(Self.sendCurvesScript(linesJSON: linesJSON, strokeWidth: strokeWidth, filled: filled, description: description))
        if !output.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("OK") {
            throw errorFor(output)
        }
    }

    private static func sendCurvesScript(linesJSON: String, strokeWidth: Double, filled: Bool, description: String) -> String {
        // Stroked: line fill only. Filled: brush fill, closed curves, no stroke.
        let fills = filled
            ? "const brushFill = solid; const lineFill = noFill; const closed = true;"
            : "const brushFill = noFill; const lineFill = solid; const closed = false;"
        return """
        try {
          const { app } = require('/application');
          const { PolyCurveNodeDefinition, NodeChildType } = require('/nodes');
          const { PolyCurve, CurveBuilder } = require('/geometry');
          const { FillDescriptor } = require('/fills');
          const { Colour, RGBA8 } = require('/colours');
          const { LineStyleDescriptor } = require('/linestyle');
          const { BlendMode } = require('affinity:common');
          const { AddChildNodesCommandBuilder } = require('/commands');
          const doc = app.documents.current;
          if (!doc) { console.log('ERR:NO_DOCUMENT'); }
          else {
            const lines = \(linesJSON);
            const pc = new PolyCurve();
            const solid = FillDescriptor.createSolid(Colour.createRGBA8(new RGBA8(0, 0, 0, 255)), BlendMode.Normal);
            const noFill = FillDescriptor.createNone();
            \(fills)
            for (let i = 0; i < lines.length; i++) {
              const ln = lines[i];
              if (ln.length < 2) continue;
              const cb = CurveBuilder.create();
              cb.beginXY(ln[0][0], ln[0][1]);
              for (let j = 1; j < ln.length; j++) cb.lineToXY(ln[j][0], ln[j][1]);
              if (closed) cb.close();
              pc.addCurve(cb.createCurve());
            }
            const lineStyle = LineStyleDescriptor.createDefault(\(strokeWidth));
            const def = PolyCurveNodeDefinition.create(pc, brushFill, lineStyle, lineFill, noFill);
            def.userDescription = \(jsString(description));
            const b = AddChildNodesCommandBuilder.create();
            b.addNode(def);
            b.setInsertionTarget(doc.spreads.current || doc.spreads.first);
            doc.executeCommand(b.createCommand(false, NodeChildType.Main));
            console.log('OK');
          }
        } catch (e) { console.log('ERR:' + e); }
        """
    }

    /// One PolyCurve node, one filled black ellipse per dot, on the current
    /// spread. Dots are `[x, y, radius]` in document-pixel coordinates.
    private static func sendVectorScript(dotsJSON: String, description: String) -> String {
        """
        try {
          const { app } = require('/application');
          const { PolyCurveNodeDefinition, NodeChildType } = require('/nodes');
          const { PolyCurve, Curve, Rectangle } = require('/geometry');
          const { FillDescriptor } = require('/fills');
          const { Colour, RGBA8 } = require('/colours');
          const { LineStyleDescriptor } = require('/linestyle');
          const { BlendMode } = require('affinity:common');
          const { AddChildNodesCommandBuilder } = require('/commands');
          const doc = app.documents.current;
          if (!doc) { console.log('ERR:NO_DOCUMENT'); }
          else {
            const dots = \(dotsJSON);
            const pc = new PolyCurve();
            for (let i = 0; i < dots.length; i++) {
              const d = dots[i];
              pc.addCurve(Curve.createEllipse(new Rectangle(d[0] - d[2], d[1] - d[2], 2 * d[2], 2 * d[2])));
            }
            const fill = FillDescriptor.createSolid(Colour.createRGBA8(new RGBA8(0, 0, 0, 255)), BlendMode.Normal);
            const noFill = FillDescriptor.createNone();
            const lineStyle = LineStyleDescriptor.createDefault();
            const def = PolyCurveNodeDefinition.create(pc, fill, lineStyle, noFill, noFill);
            def.userDescription = \(jsString(description));
            const b = AddChildNodesCommandBuilder.create();
            b.addNode(def);
            b.setInsertionTarget(doc.spreads.current || doc.spreads.first);
            doc.executeCommand(b.createCommand(false, NodeChildType.Main));
            console.log('OK');
          }
        } catch (e) { console.log('ERR:' + e); }
        """
    }

    /// Maps a script's non-OK output to an error, reflecting permission failures
    /// in `status`. Shared by Pull and Send.
    private func errorFor(_ output: String) -> Error {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("NO_DOCUMENT") { return AffinityError.noDocument }
        let message = trimmed.hasPrefix("ERR:") ? String(trimmed.dropFirst(4)) : trimmed
        let upper = message.uppercased()
        if upper.contains("PERMISSION_DENIED") || upper.contains("NOT_ALLOWED") {
            status = .permissionDenied(message)
        }
        return MCPClient.ClientError.rpc(code: -1, message: message)
    }

    static func desktopURL(_ filename: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent(filename)
    }

    /// Encodes a Swift string as a JS string literal (quoted, escaped).
    static func jsString(_ value: String) -> String {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    private static func sendRasterScript(path: String, description: String) -> String {
        """
        try {
          const { app } = require('/application');
          const { ImageNodeDefinition, NodeChildType } = require('/nodes');
          const { Bitmap, RasterFormat } = require('/rasterobject');
          const { AddChildNodesCommandBuilder } = require('/commands');
          const doc = app.documents.current;
          if (!doc) { console.log('ERR:NO_DOCUMENT'); }
          else {
            const bmp = Bitmap.loadFromFile(\(jsString(path)), RasterFormat.RGBA8);
            const nodeDef = ImageNodeDefinition.create(RasterFormat.RGBA8);
            nodeDef.userDescription = \(jsString(description));
            nodeDef.bitmap = bmp;
            const spread = doc.spreads.current || doc.spreads.first;
            const b = AddChildNodesCommandBuilder.create();
            b.addNode(nodeDef);
            b.setInsertionTarget(spread);
            doc.executeCommand(b.createCommand(false, NodeChildType.Main));
            console.log('OK');
          }
        } catch (e) { console.log('ERR:' + e); }
        """
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
