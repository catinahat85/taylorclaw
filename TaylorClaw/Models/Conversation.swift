import Foundation

struct Conversation: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var messages: [Message]
    var createdAt: Date
    var updatedAt: Date
    var lastProviderID: String?
    var lastModelID: String?

    init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        messages: [Message] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastProviderID: String? = nil,
        lastModelID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastProviderID = lastProviderID
        self.lastModelID = lastModelID
    }

    var lastMessagePreview: String {
        guard let last = messages.last else { return "Empty conversation" }
        let trimmed = last.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "…" : trimmed
    }

    var isEmpty: Bool { messages.isEmpty }
}
