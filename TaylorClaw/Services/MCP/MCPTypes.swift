import Foundation

/// JSON-RPC 2.0 envelope constants and wire types used by MCP.
enum JSONRPC {
    static let version = "2.0"
}

/// Dynamic JSON value used for MCP params/results (schemas are tool-defined).
enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Codable {
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int64.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(
            in: c, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

extension JSONValue {
    var stringValue: String? { if case .string(let s) = self { s } else { nil } }
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { o } else { nil } }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { a } else { nil } }
}

// MARK: - JSON-RPC wire types

struct JSONRPCRequest: Codable, Sendable {
    let jsonrpc: String
    let id: JSONRPCID?
    let method: String
    let params: JSONValue?

    init(id: JSONRPCID?, method: String, params: JSONValue?) {
        self.jsonrpc = JSONRPC.version
        self.id = id
        self.method = method
        self.params = params
    }

}

struct JSONRPCResponse: Codable, Sendable {
    let jsonrpc: String
    let id: JSONRPCID?
    let result: JSONValue?
    let error: JSONRPCError?
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.jsonrpc = try c.decode(String.self, forKey: .jsonrpc)
        self.result = try c.decodeIfPresent(JSONValue.self, forKey: .result)
        self.error = try c.decodeIfPresent(JSONRPCError.self, forKey: .error)
        if let intID = try c.decodeIfPresent(Int64.self, forKey: .id) {
            self.id = intID
        } else if let stringID = try c.decodeIfPresent(String.self, forKey: .id),
                  let parsed = Int64(stringID) {
            self.id = parsed
        } else {
            self.id = nil
        }
    }
}

/// JSON-RPC request/response IDs may be numbers or strings.
enum JSONRPCID: Hashable, Sendable, Codable {
    case int(Int64)
    case string(String)

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int64.self) {
            self = .int(i)
            return
        }
        if let s = try? c.decode(String.self) {
            self = .string(s)
            return
        }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid JSON-RPC id")
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let i): try c.encode(i)
        case .string(let s): try c.encode(s)
        }
    }
}

struct JSONRPCError: Codable, Sendable, Error {
    let code: Int
    let message: String
    let data: JSONValue?
}

// MARK: - MCP domain types

struct MCPTool: Codable, Sendable, Hashable, Identifiable {
    let name: String
    let description: String?
    let inputSchema: JSONValue?

    var id: String { name }
}

struct MCPToolListResult: Codable, Sendable {
    let tools: [MCPTool]
}

struct MCPToolCallResult: Codable, Sendable {
    struct Content: Codable, Sendable, Hashable {
        let type: String
        let text: String?
    }
    let content: [Content]
    let isError: Bool?
}

struct MCPServerInfo: Codable, Sendable, Hashable {
    let name: String
    let version: String
}

struct MCPInitializeResult: Codable, Sendable {
    let protocolVersion: String
    let capabilities: JSONValue?
    let serverInfo: MCPServerInfo?
}

// MARK: - Errors

enum MCPError: Error, Sendable, Equatable {
    case notInitialized
    case alreadyRunning
    case transportClosed
    case timeout
    case rpcError(code: Int, message: String)
    case decodingError(String)
    case processExited(Int32)
    case tooManyRestarts(Int)
    case launchFailed(String)
}
