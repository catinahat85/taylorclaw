import XCTest
@testable import TaylorClaw

final class MemoryServiceTests: XCTestCase {

    // MARK: - Reads

    func testStatusParsesSnakeCaseJSON() async throws {
        let recorder = ToolRecorder(responses: [
            "mempalace_status": .text("""
                {"total_drawers": 42, "wings": 3, "rooms": 9}
                """),
        ])
        let service = recorder.makeService(guardActor: nil)
        let status = try await service.status()
        XCTAssertEqual(status.totalDrawers, 42)
        XCTAssertEqual(status.wingCount, 3)
        XCTAssertEqual(status.roomCount, 9)
    }

    func testListWingsParsesArray() async throws {
        let recorder = ToolRecorder(responses: [
            "mempalace_list_wings": .text("""
                [
                    {"name": "project-a", "drawer_count": 10},
                    {"name": "project-b", "drawer_count": 5}
                ]
                """),
        ])
        let service = recorder.makeService(guardActor: nil)
        let wings = try await service.listWings()
        XCTAssertEqual(wings.map(\.name), ["project-a", "project-b"])
        XCTAssertEqual(wings.map(\.drawerCount), [10, 5])
    }

    func testListRoomsSendsWingArg() async throws {
        let recorder = ToolRecorder(responses: [
            "mempalace_list_rooms": .text("""
                [{"name": "notes", "drawer_count": 2}]
                """),
        ])
        let service = recorder.makeService(guardActor: nil)
        let rooms = try await service.listRooms(in: "project-a")
        XCTAssertEqual(rooms.first?.name, "notes")
        let call = await recorder.lastCall(for: "mempalace_list_rooms")
        XCTAssertEqual(call?.args.objectValue?["wing"]?.stringValue, "project-a")
    }

    func testSearchParsesDrawers() async throws {
        let recorder = ToolRecorder(responses: [
            "mempalace_search": .text("""
                [
                    {
                        "drawer_id": "abc123",
                        "wing": "project-a",
                        "room": "notes",
                        "content": "hello world",
                        "score": 0.95
                    }
                ]
                """),
        ])
        let service = recorder.makeService(guardActor: nil)
        let result = try await service.search(query: "hello")
        XCTAssertEqual(result.drawers.count, 1)
        XCTAssertEqual(result.drawers.first?.drawerID, "abc123")
        XCTAssertEqual(result.drawers.first?.score, 0.95)
    }

    // MARK: - Writes

    func testAddDrawerRunsThroughGuardAndCallsTool() async throws {
        let log = AuditLog(fileURL: nil)
        let g = AgentGuard(
            prompter: AutoApprovePrompter(),
            auditLog: log
        )
        let recorder = ToolRecorder(responses: [
            "mempalace_add_drawer": .text("""
                {"drawer_id": "new-id-123"}
                """),
        ])
        let service = recorder.makeService(guardActor: g)
        let id = try await service.addDrawer(
            wing: "project-a",
            room: "notes",
            content: "remember this"
        )
        XCTAssertEqual(id, "new-id-123")
        let call = await recorder.lastCall(for: "mempalace_add_drawer")
        XCTAssertEqual(call?.args.objectValue?["wing"]?.stringValue, "project-a")
        XCTAssertEqual(call?.args.objectValue?["content"]?.stringValue, "remember this")
        let entries = await log.all()
        XCTAssertTrue(entries.contains { $0.outcome == .userApproved })
        XCTAssertTrue(entries.contains { $0.outcome == .toolSuccess })
    }

    func testAddDrawerDeniedThrowsAndSkipsCall() async {
        let log = AuditLog(fileURL: nil)
        let g = AgentGuard(
            prompter: AutoDenyPrompter(),
            auditLog: log
        )
        let recorder = ToolRecorder(responses: [:])
        let service = recorder.makeService(guardActor: g)
        do {
            _ = try await service.addDrawer(
                wing: "w", room: "r", content: "c"
            )
            XCTFail("Expected denial")
        } catch SafetyError.denied {
            // expected
        } catch {
            XCTFail("Unexpected: \(error)")
        }
        let calls = await recorder.allCalls
        XCTAssertTrue(calls.isEmpty, "Denied tool must not reach the MCP client")
    }

    func testDeleteDrawerAlwaysPromptsDestructive() async throws {
        let log = AuditLog(fileURL: nil)
        let scripted = ScriptedPrompter(
            script: ["mempalace_delete_drawer": [.allowOnce, .allowOnce]],
            fallback: .deny
        )
        let g = AgentGuard(prompter: scripted, auditLog: log)
        let recorder = ToolRecorder(responses: [
            "mempalace_delete_drawer": .text("{}"),
        ])
        let service = recorder.makeService(guardActor: g)
        try await service.deleteDrawer(id: "abc")
        try await service.deleteDrawer(id: "def")
        let seen = await scripted.seen
        XCTAssertEqual(seen.count, 2, "Destructive tool must prompt each call")
    }

    func testToolErrorPropagates() async {
        let recorder = ToolRecorder(responses: [
            "mempalace_search": .error("embedding service offline"),
        ])
        let service = recorder.makeService(guardActor: nil)
        do {
            _ = try await service.search(query: "x")
            XCTFail("Expected throw")
        } catch MemoryServiceError.toolFailed(let tool, let msg) {
            XCTAssertEqual(tool, "mempalace_search")
            XCTAssertTrue(msg.contains("offline"))
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }
}

// MARK: - Test double

private actor ToolRecorder {
    enum Response: Sendable {
        case text(String)
        case error(String)
    }
    struct Call: Sendable {
        let tool: String
        let args: JSONValue
    }

    private var responses: [String: Response]
    private(set) var allCalls: [Call] = []

    init(responses: [String: Response]) {
        self.responses = responses
    }

    func lastCall(for tool: String) -> Call? {
        allCalls.last(where: { $0.tool == tool })
    }

    private func handle(tool: String, args: JSONValue) throws -> [MCPToolCallResult.Content] {
        allCalls.append(Call(tool: tool, args: args))
        guard let response = responses[tool] else {
            return [MCPToolCallResult.Content(type: "text", text: "{}")]
        }
        switch response {
        case .text(let t):
            return [MCPToolCallResult.Content(type: "text", text: t)]
        case .error(let msg):
            throw MemoryServiceError.toolFailed(tool: tool, message: msg)
        }
    }

    /// Builds a `MemoryService` whose `ToolCaller` closure routes through
    /// this actor. Capturing via an explicit closure makes the
    /// `@Sendable` requirement obvious.
    nonisolated func makeService(guardActor: AgentGuard?) -> MemoryService {
        MemoryService(
            guardActor: guardActor,
            toolCall: { tool, args in
                try await self.handle(tool: tool, args: args)
            }
        )
    }
}
