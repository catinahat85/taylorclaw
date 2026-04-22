import Foundation

/// JSON-RPC 2.0 client over an MCP stdio subprocess.
///
/// Lifecycle:
///   1. `start()` — launches the server, performs `initialize` handshake,
///      sends `notifications/initialized`, and caches `tools/list`.
///   2. `callTool(...)` — invokes a tool and decodes the result.
///   3. `stop()` — tears down transport and process.
///
/// On unexpected child exit, pending requests are failed with
/// `.processExited` and the client transitions to `.failed`. Callers can
/// call `start()` again to reconnect.
actor MCPClient {
    enum State: Sendable, Equatable {
        case idle
        case starting
        case ready
        case stopped
        case failed(String)
    }

    let config: MCPServerConfig
    private let manager: MCPProcessManager
    private var transport: MCPTransport?
    private(set) var state: State = .idle
    private(set) var tools: [MCPTool] = []
    private(set) var serverInfo: MCPServerInfo?

    private var nextID: Int64 = 1
    private var pending: [JSONRPCID: CheckedContinuation<JSONValue, any Error>] = [:]
    private var pendingTimeouts: [JSONRPCID: Task<Void, Never>] = [:]
    private var readerTask: Task<Void, Never>?
    private var exitWatcher: Task<Void, Never>?

    private let clientVersion = "0.2.0"
    private let clientName = "taylorclaw"
    private let protocolVersion = "2024-11-05"
    private let startupHandshakeTimeout: TimeInterval = 420

    init(config: MCPServerConfig) {
        self.config = config
        self.manager = MCPProcessManager(config: config)
    }

    /// Test-only: bypass `MCPProcessManager` and run the handshake over a
    /// caller-supplied transport (typically wired to an in-process mock).
    init(config: MCPServerConfig, injectedTransport: MCPTransport) {
        self.config = config
        self.manager = MCPProcessManager(config: config)
        self.transport = injectedTransport
    }

    // MARK: - Lifecycle

    func start() async throws {
        switch state {
        case .ready, .starting:
            throw MCPError.alreadyRunning
        default: break
        }
        state = .starting

        let t: MCPTransport
        let launchedProcess: Bool
        if let existing = transport {
            t = existing
            launchedProcess = false
        } else {
            do {
                t = try await manager.launch()
            } catch {
                state = .failed("\(error)")
                throw error
            }
            self.transport = t
            launchedProcess = true
        }
        await t.start()
        startReader(transport: t)
        if launchedProcess { startExitWatcher() }

        do {
            let initParams: JSONValue = .object([
                "protocolVersion": .string(protocolVersion),
                "capabilities": .object([:]),
                "clientInfo": .object([
                    "name": .string(clientName),
                    "version": .string(clientVersion),
                ]),
            ])
            // Server startup can legitimately take time on first run while Python
            // imports heavy deps / initializes local state.
            let initRaw = try await sendRequest(
                "initialize",
                params: initParams,
                timeout: startupHandshakeTimeout
            )
            if let initResult = decode(MCPInitializeResult.self, from: initRaw) {
                self.serverInfo = initResult.serverInfo
            }

            try await sendNotification("notifications/initialized", params: nil)

            let listRaw = try await sendRequest(
                "tools/list",
                params: .object([:]),
                timeout: startupHandshakeTimeout
            )
            if let listResult = decode(MCPToolListResult.self, from: listRaw) {
                self.tools = listResult.tools
            }
            state = .ready
        } catch {
            state = .failed("\(error)")
            await teardown(reason: "startup failure: \(error)")
            throw error
        }
    }

    func stop() async {
        await teardown(reason: "client stop requested")
        state = .stopped
    }

    /// Snapshot of recent subprocess stderr lines — useful for surfacing
    /// Python tracebacks or model-download progress when startup fails or
    /// times out.
    func stderrSnapshot() async -> [String] {
        await manager.currentStderr()
    }

    // MARK: - Tool API

    func listTools() -> [MCPTool] { tools }

    func callTool(name: String, arguments: JSONValue = .object([:])) async throws -> MCPToolCallResult {
        guard state == .ready else { throw MCPError.notInitialized }
        let params: JSONValue = .object([
            "name": .string(name),
            "arguments": arguments,
        ])
        let raw = try await sendRequest("tools/call", params: params)
        guard let result = decode(MCPToolCallResult.self, from: raw) else {
            throw MCPError.decodingError("tools/call result")
        }
        return result
    }

    /// Generic RPC for unit tests / methods not modeled above.
    func rawRequest(_ method: String, params: JSONValue?) async throws -> JSONValue {
        try await sendRequest(method, params: params)
    }

    // MARK: - RPC core

    private func sendRequest(
        _ method: String,
        params: JSONValue?,
        timeout: TimeInterval = 60
    ) async throws -> JSONValue {
        guard let transport = transport else { throw MCPError.transportClosed }

        let id: JSONRPCID = .int(nextID)
        nextID += 1
        let req = JSONRPCRequest(id: id, method: method, params: params)
        let data: Data
        do {
            data = try JSONEncoder().encode(req)
        } catch {
            throw MCPError.decodingError("encode request: \(error)")
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<JSONValue, any Error>) in
                pending[id] = cont
                let timeoutTask = Task.detached { [weak self] in
                    let nanos = UInt64(max(0, timeout) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanos)
                    guard !Task.isCancelled else { return }
                    await self?.failPending(id: id, error: MCPError.timeout)
                }
                pendingTimeouts[id] = timeoutTask
                Task.detached { [weak self] in
                    do {
                        try await transport.send(data)
                    } catch {
                        await self?.failPending(id: id, error: error)
                    }
                }
            }
        } onCancel: {
            Task.detached { [weak self] in await self?.cancelPending(id: id) }
        }
    }

    private func failPending(id: JSONRPCID, error: any Error) {
        pendingTimeouts.removeValue(forKey: id)?.cancel()
        if let cont = pending.removeValue(forKey: id) {
            cont.resume(throwing: error)
        }
    }

    private func sendNotification(_ method: String, params: JSONValue?) async throws {
        guard let transport = transport else { throw MCPError.transportClosed }
        let req = JSONRPCRequest(id: nil, method: method, params: params)
        let data = try JSONEncoder().encode(req)
        try await transport.send(data)
    }

    private func cancelPending(id: JSONRPCID) {
        pendingTimeouts.removeValue(forKey: id)?.cancel()
        if let cont = pending.removeValue(forKey: id) {
            cont.resume(throwing: CancellationError())
        }
    }

    // MARK: - Reader / teardown

    private func startReader(transport: MCPTransport) {
        readerTask = Task.detached { [weak self] in
            for await data in transport.incoming {
                await self?.handleIncoming(data)
            }
            await self?.handleStreamEnd()
        }
    }

    private func startExitWatcher() {
        exitWatcher = Task.detached { [weak self, manager] in
            let status = await manager.waitForExit()
            await self?.handleProcessExit(status: status)
        }
    }

    private func handleIncoming(_ data: Data) {
        // Responses carry `id`; notifications do not.
        if let resp = try? JSONDecoder().decode(JSONRPCResponse.self, from: data),
           let id = resp.id,
           let cont = pending.removeValue(forKey: id) {
            pendingTimeouts.removeValue(forKey: id)?.cancel()
            if let err = resp.error {
                cont.resume(throwing: MCPError.rpcError(code: err.code, message: err.message))
            } else {
                cont.resume(returning: resp.result ?? .null)
            }
            return
        }
        // Notifications / unparsed — ignored in Phase A.
    }

    private func handleStreamEnd() {
        failAllPending(with: MCPError.transportClosed)
    }

    private func handleProcessExit(status: Int32) {
        if state == .ready || state == .starting {
            state = .failed("process exited with status \(status)")
        }
        failAllPending(with: MCPError.processExited(status))
    }

    private func failAllPending(with error: any Error) {
        let items = pending
        pending.removeAll()
        let timeoutTasks = pendingTimeouts.values
        pendingTimeouts.removeAll()
        for task in timeoutTasks {
            task.cancel()
        }
        for (_, cont) in items {
            cont.resume(throwing: error)
        }
    }

    private func teardown(reason: String) async {
        readerTask?.cancel()
        readerTask = nil
        exitWatcher?.cancel()
        exitWatcher = nil
        await transport?.close()
        transport = nil
        await manager.terminate(reason: reason)
        failAllPending(with: MCPError.transportClosed)
    }

    // MARK: - Helpers

    private func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) -> T? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
