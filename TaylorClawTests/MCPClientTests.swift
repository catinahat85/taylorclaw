import XCTest
@testable import TaylorClaw

/// End-to-end test of the handshake + tool call using an in-process mock
/// MCP server wired to the client via a pair of OS pipes.
final class MCPClientTests: XCTestCase {

    func testInitializeAndListTools() async throws {
        let harness = MCPMockHarness()
        try harness.start()

        let client = MCPClient(
            config: MCPServerConfig(name: "mock", command: "/bin/true"),
            injectedTransport: harness.clientTransport
        )
        try await client.start()

        let tools = await client.listTools()
        XCTAssertEqual(tools.map(\.name), ["echo", "add"])
        let info = await client.serverInfo
        XCTAssertEqual(info?.name, "mock-server")

        await client.stop()
        harness.stop()
    }

    func testCallToolEchoesArgument() async throws {
        let harness = MCPMockHarness()
        try harness.start()

        let client = MCPClient(
            config: MCPServerConfig(name: "mock", command: "/bin/true"),
            injectedTransport: harness.clientTransport
        )
        try await client.start()

        let result = try await client.callTool(
            name: "echo",
            arguments: .object(["text": .string("hello from client")])
        )
        XCTAssertEqual(result.content.first?.text, "hello from client")
        XCTAssertEqual(result.isError, false)

        await client.stop()
        harness.stop()
    }

    func testRPCErrorPropagates() async throws {
        let harness = MCPMockHarness()
        try harness.start()

        let client = MCPClient(
            config: MCPServerConfig(name: "mock", command: "/bin/true"),
            injectedTransport: harness.clientTransport
        )
        try await client.start()

        do {
            _ = try await client.callTool(name: "nonexistent", arguments: .object([:]))
            XCTFail("expected error")
        } catch let MCPError.rpcError(code, message) {
            XCTAssertEqual(code, -32601)
            XCTAssertTrue(message.contains("Unknown tool"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        await client.stop()
        harness.stop()
    }
}

// MARK: - In-process mock server harness

private struct HandleBox: @unchecked Sendable { let handle: FileHandle }

private final class MCPMockHarness: @unchecked Sendable {
    let clientTransport: MCPTransport
    private let serverIn: FileHandle   // server reads what client wrote
    private let serverOut: FileHandle  // server writes what client reads
    private var task: Task<Void, Never>?

    init() {
        let up = Pipe()
        let down = Pipe()
        self.clientTransport = MCPTransport(
            stdin: up.fileHandleForWriting,
            stdout: down.fileHandleForReading
        )
        self.serverIn = up.fileHandleForReading
        self.serverOut = down.fileHandleForWriting
    }

    func start() throws {
        let inBox = HandleBox(handle: serverIn)
        let outBox = HandleBox(handle: serverOut)
        task = Task.detached(priority: .utility) {
            var buffer = Data()
            while !Task.isCancelled {
                let chunk: Data?
                do { chunk = try inBox.handle.read(upToCount: 4096) } catch { break }
                guard let chunk, !chunk.isEmpty else { break }
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let line = buffer.subdata(in: buffer.startIndex..<nl)
                    let next = buffer.index(after: nl)
                    buffer.removeSubrange(buffer.startIndex..<next)
                    Self.handle(line: line, out: outBox.handle)
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        try? serverIn.close()
        try? serverOut.close()
    }

    private static func handle(line: Data, out: FileHandle) {
        guard let req = try? JSONDecoder().decode(JSONRPCRequest.self, from: line) else {
            return
        }
        if req.id == nil { return } // notification — no reply

        let response: JSONRPCResponse
        switch req.method {
        case "initialize":
            let result: JSONValue = .object([
                "protocolVersion": .string("2024-11-05"),
                "capabilities": .object([:]),
                "serverInfo": .object([
                    "name": .string("mock-server"),
                    "version": .string("0.0.1"),
                ]),
            ])
            response = JSONRPCResponse(jsonrpc: "2.0", id: req.id, result: result, error: nil)

        case "tools/list":
            let result: JSONValue = .object([
                "tools": .array([
                    .object([
                        "name": .string("echo"),
                        "description": .string("Echo back text."),
                        "inputSchema": .object([:]),
                    ]),
                    .object([
                        "name": .string("add"),
                        "description": .string("Sum two numbers."),
                        "inputSchema": .object([:]),
                    ]),
                ]),
            ])
            response = JSONRPCResponse(jsonrpc: "2.0", id: req.id, result: result, error: nil)

        case "tools/call":
            let name = req.params?.objectValue?["name"]?.stringValue ?? ""
            let args = req.params?.objectValue?["arguments"]?.objectValue ?? [:]
            if name == "echo" {
                let text = args["text"]?.stringValue ?? ""
                let result: JSONValue = .object([
                    "content": .array([
                        .object(["type": .string("text"), "text": .string(text)]),
                    ]),
                    "isError": .bool(false),
                ])
                response = JSONRPCResponse(jsonrpc: "2.0", id: req.id, result: result, error: nil)
            } else {
                let err = JSONRPCError(code: -32601, message: "Unknown tool: \(name)", data: nil)
                response = JSONRPCResponse(jsonrpc: "2.0", id: req.id, result: nil, error: err)
            }

        default:
            let err = JSONRPCError(code: -32601, message: "Method not found: \(req.method)", data: nil)
            response = JSONRPCResponse(jsonrpc: "2.0", id: req.id, result: nil, error: err)
        }

        guard var data = try? JSONEncoder().encode(response) else { return }
        data.append(0x0A)
        try? out.write(contentsOf: data)
    }
}
