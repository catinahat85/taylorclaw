import XCTest
@testable import TaylorClaw

final class ConversationCodableTests: XCTestCase {

    /// v0.1 records have no `mode` field. The custom `init(from:)` should
    /// default the field to `.chat` so existing on-disk conversations still
    /// decode after the upgrade.
    func testV01JSONDecodesWithChatMode() throws {
        let id = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "title": "Old conversation",
            "messages": [],
            "createdAt": 0,
            "updatedAt": 0,
            "lastProviderID": "anthropic",
            "lastModelID": "claude-3-5-sonnet"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let data = json.data(using: .utf8)!
        let convo = try decoder.decode(Conversation.self, from: data)
        XCTAssertEqual(convo.id, id)
        XCTAssertEqual(convo.title, "Old conversation")
        XCTAssertEqual(convo.mode, .chat)
    }

    func testV02JSONRoundTripsMode() throws {
        let convo = Conversation(title: "Agent run", mode: .agent)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(convo)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(Conversation.self, from: data)
        XCTAssertEqual(decoded.mode, .agent)
        XCTAssertEqual(decoded.title, "Agent run")
        XCTAssertEqual(decoded.id, convo.id)
    }

    func testNewConversationDefaultsToChat() {
        let convo = Conversation()
        XCTAssertEqual(convo.mode, .chat)
    }
}
