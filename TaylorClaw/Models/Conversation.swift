import Foundation

struct Conversation: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var messages: [Message]
    var createdAt: Date
    var updatedAt: Date
    var lastProviderID: String?
    var lastModelID: String?
    var mode: ChatMode

    init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        messages: [Message] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastProviderID: String? = nil,
        lastModelID: String? = nil,
        mode: ChatMode = .chat
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastProviderID = lastProviderID
        self.lastModelID = lastModelID
        self.mode = mode
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.messages = try c.decode([Message].self, forKey: .messages)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        self.lastProviderID = try c.decodeIfPresent(String.self, forKey: .lastProviderID)
        self.lastModelID = try c.decodeIfPresent(String.self, forKey: .lastModelID)
        self.mode = try c.decodeIfPresent(ChatMode.self, forKey: .mode) ?? .chat
    }

    var lastMessagePreview: String {
        guard let last = messages.last else { return "Empty conversation" }
        let trimmed = last.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "…" : trimmed
    }

    var isEmpty: Bool { messages.isEmpty }
}
