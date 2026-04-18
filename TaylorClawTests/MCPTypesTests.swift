import XCTest
@testable import TaylorClaw

final class MCPTypesTests: XCTestCase {

    // MARK: - JSONValue round-trips

    func testJSONValueRoundTripsPrimitives() throws {
        let values: [JSONValue] = [
            .null,
            .bool(true),
            .int(42),
            .double(3.14),
            .string("hello"),
        ]
        for v in values {
            let data = try JSONEncoder().encode(v)
            let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
            XCTAssertEqual(decoded, v)
        }
    }

    func testJSONValueRoundTripsContainers() throws {
        let nested: JSONValue = .object([
            "list": .array([.int(1), .string("x"), .bool(false), .null]),
            "nested": .object(["k": .string("v")]),
        ])
        let data = try JSONEncoder().encode(nested)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, nested)
    }

    // MARK: - JSON-RPC request shape

    func testJSONRPCRequestEncodesExpectedShape() throws {
        let req = JSONRPCRequest(
            id: 7,
            method: "tools/call",
            params: .object(["name": .string("echo")])
        )
        let data = try JSONEncoder().encode(req)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(json["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json["id"] as? Int, 7)
        XCTAssertEqual(json["method"] as? String, "tools/call")
        XCTAssertNotNil(json["params"])
    }

    func testJSONRPCResponseDecodesError() throws {
        let raw = #"{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"Method not found"}}"#
        let resp = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(raw.utf8))
        XCTAssertEqual(resp.id, 1)
        XCTAssertNil(resp.result)
        XCTAssertEqual(resp.error?.code, -32601)
        XCTAssertEqual(resp.error?.message, "Method not found")
    }

    // MARK: - MCP tool shape

    func testMCPToolListResultDecodes() throws {
        let raw = """
        {"tools":[{"name":"echo","description":"echo back","inputSchema":{}}]}
        """
        let result = try JSONDecoder().decode(MCPToolListResult.self, from: Data(raw.utf8))
        XCTAssertEqual(result.tools.count, 1)
        XCTAssertEqual(result.tools.first?.name, "echo")
        XCTAssertEqual(result.tools.first?.description, "echo back")
    }

    func testMCPToolCallResultDecodes() throws {
        let raw = """
        {"content":[{"type":"text","text":"hello"}],"isError":false}
        """
        let result = try JSONDecoder().decode(MCPToolCallResult.self, from: Data(raw.utf8))
        XCTAssertEqual(result.content.count, 1)
        XCTAssertEqual(result.content.first?.type, "text")
        XCTAssertEqual(result.content.first?.text, "hello")
        XCTAssertEqual(result.isError, false)
    }
}
