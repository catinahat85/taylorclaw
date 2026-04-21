import Foundation

/// A top-level palace container — typically one per person/project.
struct MemoryWing: Sendable, Hashable, Identifiable, Codable {
    let name: String
    let drawerCount: Int

    var id: String { name }
}

/// A topic within a wing.
struct MemoryRoom: Sendable, Hashable, Identifiable, Codable {
    let wing: String
    let name: String
    let drawerCount: Int

    var id: String { wing + "/" + name }
}

/// A single verbatim memory.
struct MemoryDrawer: Sendable, Hashable, Identifiable, Codable {
    /// MemPalace's stable ID (SHA256 of wing/room/content).
    let drawerID: String
    let wing: String
    let room: String
    let content: String
    let score: Double?

    var id: String { drawerID }

    init(
        drawerID: String,
        wing: String,
        room: String,
        content: String,
        score: Double? = nil
    ) {
        self.drawerID = drawerID
        self.wing = wing
        self.room = room
        self.content = content
        self.score = score
    }

    /// Shorter preview for list rows.
    var preview: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 160 { return trimmed }
        let cutoff = trimmed.index(trimmed.startIndex, offsetBy: 160)
        return String(trimmed[..<cutoff]) + "…"
    }
}

/// Overall palace statistics for the header.
struct MemoryStatus: Sendable, Hashable, Codable {
    let totalDrawers: Int
    let wingCount: Int
    let roomCount: Int

    static let empty = MemoryStatus(totalDrawers: 0, wingCount: 0, roomCount: 0)
}
