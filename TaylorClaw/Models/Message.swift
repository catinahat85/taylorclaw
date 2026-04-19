import Foundation

struct Message: Identifiable, Codable, Hashable, Sendable {
    enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
    }

    let id: UUID
    var role: Role
    var content: String
    var createdAt: Date
    var modelID: String?
    var providerID: String?
    var toolCalls: [ToolCall]

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        createdAt: Date = Date(),
        modelID: String? = nil,
        providerID: String? = nil,
        toolCalls: [ToolCall] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.modelID = modelID
        self.providerID = providerID
        self.toolCalls = toolCalls
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.role = try c.decode(Role.self, forKey: .role)
        self.content = try c.decode(String.self, forKey: .content)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.modelID = try c.decodeIfPresent(String.self, forKey: .modelID)
        self.providerID = try c.decodeIfPresent(String.self, forKey: .providerID)
        self.toolCalls = try c.decodeIfPresent([ToolCall].self, forKey: .toolCalls) ?? []
    }
}

/// One tool invocation tied to an assistant turn (when `result` is nil) or
/// a user "tool_result" turn (when `result` is set). The `id` ties the two
/// together — providers that need it (Anthropic) round-trip it on the wire.
struct ToolCall: Codable, Hashable, Sendable, Identifiable {
    let id: String
    var name: String
    var input: JSONValue
    var result: String?
    var isError: Bool

    init(
        id: String,
        name: String,
        input: JSONValue = .object([:]),
        result: String? = nil,
        isError: Bool = false
    ) {
        self.id = id
        self.name = name
        self.input = input
        self.result = result
        self.isError = isError
    }
}
