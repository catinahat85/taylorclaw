import Foundation

/// Result wrapper so callers can distinguish "ran, got nothing" from
/// "ran, decoded partially".
struct MemorySearchResult: Sendable, Hashable {
    let drawers: [MemoryDrawer]
    let rawCount: Int
}

/// Operations the browser needs, plus the add/delete write paths that are
/// gated by `AgentGuard` before execution.
actor MemoryService {
    /// Low-level tool invoker — abstracted so tests can stub the MCP layer.
    typealias ToolCaller = @Sendable (String, JSONValue) async throws -> [MCPToolCallResult.Content]

    private let serverName: String
    private let toolCall: ToolCaller
    private let guardActor: AgentGuard?

    init(
        serverName: String = "mempalace",
        guardActor: AgentGuard? = nil,
        toolCall: @escaping ToolCaller
    ) {
        self.serverName = serverName
        self.guardActor = guardActor
        self.toolCall = toolCall
    }

    /// Factory that wires the service to a live `MCPClient` and the shared
    /// safety guard.
    static func mempalace(
        client: MCPClient,
        guardActor: AgentGuard
    ) -> MemoryService {
        MemoryService(
            serverName: "mempalace",
            guardActor: guardActor,
            toolCall: { name, args in
                let result = try await client.callTool(name: name, arguments: args)
                if result.isError == true {
                    let msg = result.content.first?.text ?? "tool error"
                    throw MemoryServiceError.toolFailed(tool: name, message: msg)
                }
                return result.content
            }
        )
    }

    // MARK: - Reads

    func status() async throws -> MemoryStatus {
        let content = try await toolCall("mempalace_status", .object([:]))
        guard let obj = firstJSONObject(content) else { return .empty }
        return MemoryStatus(
            totalDrawers: intField(obj, keys: ["total_drawers", "totalDrawers", "drawers"]) ?? 0,
            wingCount:    intField(obj, keys: ["wings", "wing_count", "wingCount"]) ?? 0,
            roomCount:    intField(obj, keys: ["rooms", "room_count", "roomCount"]) ?? 0
        )
    }

    func listWings() async throws -> [MemoryWing] {
        let content = try await toolCall("mempalace_list_wings", .object([:]))
        guard let arr = firstJSONArray(content) else { return [] }
        return arr.compactMap { value in
            guard let obj = value.objectValue,
                  let name = stringField(obj, keys: ["name", "wing"]) else { return nil }
            let count = intField(obj, keys: ["drawer_count", "drawerCount", "count"]) ?? 0
            return MemoryWing(name: name, drawerCount: count)
        }
    }

    func listRooms(in wing: String) async throws -> [MemoryRoom] {
        let content = try await toolCall(
            "mempalace_list_rooms",
            .object(["wing": .string(wing)])
        )
        guard let arr = firstJSONArray(content) else { return [] }
        return arr.compactMap { value in
            guard let obj = value.objectValue,
                  let name = stringField(obj, keys: ["name", "room"]) else { return nil }
            let count = intField(obj, keys: ["drawer_count", "drawerCount", "count"]) ?? 0
            return MemoryRoom(wing: wing, name: name, drawerCount: count)
        }
    }

    func search(
        query: String,
        wing: String? = nil,
        room: String? = nil,
        limit: Int = 20
    ) async throws -> MemorySearchResult {
        var args: [String: JSONValue] = [
            "query": .string(query),
            "limit": .int(Int64(limit)),
        ]
        if let wing { args["wing"] = .string(wing) }
        if let room { args["room"] = .string(room) }
        let content = try await toolCall("mempalace_search", .object(args))
        let arr = firstJSONArray(content) ?? []
        let drawers = arr.compactMap { Self.parseDrawer($0) }
        return MemorySearchResult(drawers: drawers, rawCount: arr.count)
    }

    // MARK: - Writes (gated)

    /// Files a new drawer. Routed through `AgentGuard` for the approval
    /// flow; throws `SafetyError` on denial.
    func addDrawer(wing: String, room: String, content: String) async throws -> String? {
        let args: JSONValue = .object([
            "wing":    .string(wing),
            "room":    .string(room),
            "content": .string(content),
        ])
        try await authorize(tool: "mempalace_add_drawer", args: args, reason: "File a new memory")

        do {
            let result = try await toolCall("mempalace_add_drawer", args)
            await recordSuccess(tool: "mempalace_add_drawer")
            return Self.extractDrawerID(result)
        } catch {
            await recordFailure(tool: "mempalace_add_drawer", error: error)
            throw error
        }
    }

    /// Deletes a drawer by ID. Always prompts (destructive).
    func deleteDrawer(id drawerID: String) async throws {
        let args: JSONValue = .object(["drawer_id": .string(drawerID)])
        try await authorize(
            tool: "mempalace_delete_drawer",
            args: args,
            reason: "Permanently remove this drawer"
        )
        do {
            _ = try await toolCall("mempalace_delete_drawer", args)
            await recordSuccess(tool: "mempalace_delete_drawer")
        } catch {
            await recordFailure(tool: "mempalace_delete_drawer", error: error)
            throw error
        }
    }

    // MARK: - Parsing helpers

    nonisolated private static func parseDrawer(_ value: JSONValue) -> MemoryDrawer? {
        guard let obj = value.objectValue else { return nil }
        let content = stringField(obj, keys: ["content", "text"]) ?? ""
        let wing    = stringField(obj, keys: ["wing"]) ?? ""
        let room    = stringField(obj, keys: ["room"]) ?? ""
        let id      = stringField(obj, keys: ["drawer_id", "drawerID", "id"])
            ?? "\(wing)/\(room)/\(content.hashValue)"
        let score   = doubleField(obj, keys: ["score", "similarity"])
        guard !content.isEmpty else { return nil }
        return MemoryDrawer(
            drawerID: id,
            wing: wing,
            room: room,
            content: content,
            score: score
        )
    }

    nonisolated private static func extractDrawerID(_ content: [MCPToolCallResult.Content]) -> String? {
        guard let obj = firstJSONObject(content) else { return nil }
        return stringField(obj, keys: ["drawer_id", "drawerID", "id"])
    }

    // MARK: - Guard helpers

    private func authorize(
        tool: String,
        args: JSONValue,
        reason: String
    ) async throws {
        guard let g = guardActor else { return }
        try await g.authorize(
            toolName: tool,
            serverName: serverName,
            arguments: args,
            reason: reason
        )
    }

    private func recordSuccess(tool: String) async {
        await guardActor?.recordResult(
            toolName: tool,
            serverName: serverName,
            success: true
        )
    }

    private func recordFailure(tool: String, error: any Error) async {
        await guardActor?.recordResult(
            toolName: tool,
            serverName: serverName,
            success: false,
            error: "\(error)"
        )
    }
}

enum MemoryServiceError: Error, Sendable, CustomStringConvertible {
    case toolFailed(tool: String, message: String)

    var description: String {
        switch self {
        case .toolFailed(let t, let m): "\(t): \(m)"
        }
    }
}

// MARK: - Content → JSON parsing (shared)

private func firstJSONObject(_ content: [MCPToolCallResult.Content]) -> [String: JSONValue]? {
    firstJSONValue(content)?.objectValue
}

private func firstJSONArray(_ content: [MCPToolCallResult.Content]) -> [JSONValue]? {
    firstJSONValue(content)?.arrayValue
}

private func firstJSONValue(_ content: [MCPToolCallResult.Content]) -> JSONValue? {
    for c in content {
        guard c.type == "text", let text = c.text else { continue }
        if let data = text.data(using: .utf8),
           let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
            return value
        }
    }
    return nil
}

private func stringField(_ obj: [String: JSONValue], keys: [String]) -> String? {
    for k in keys {
        if case .string(let s) = obj[k] { return s }
    }
    return nil
}

private func intField(_ obj: [String: JSONValue], keys: [String]) -> Int? {
    for k in keys {
        switch obj[k] {
        case .int(let i):      return Int(i)
        case .double(let d):   return Int(d)
        default:               continue
        }
    }
    return nil
}

private func doubleField(_ obj: [String: JSONValue], keys: [String]) -> Double? {
    for k in keys {
        switch obj[k] {
        case .double(let d):   return d
        case .int(let i):      return Double(i)
        default:               continue
        }
    }
    return nil
}

