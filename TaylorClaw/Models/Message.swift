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

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        createdAt: Date = Date(),
        modelID: String? = nil,
        providerID: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.modelID = modelID
        self.providerID = providerID
    }
}
