import Foundation

/// A single chunk returned from a RAG search.
struct DocumentSnippet: Sendable, Hashable, Codable {
    let text: String
    let score: Double?
    let documentID: String?
    let documentTitle: String?
    let chunkIndex: Int?

    init(
        text: String,
        score: Double? = nil,
        documentID: String? = nil,
        documentTitle: String? = nil,
        chunkIndex: Int? = nil
    ) {
        self.text = text
        self.score = score
        self.documentID = documentID
        self.documentTitle = documentTitle
        self.chunkIndex = chunkIndex
    }
}

/// Abstracts document search. Agent mode calls this alongside the
/// `MemoryRetriever` to pull relevant chunks into the system prompt.
protocol DocumentRetriever: Sendable {
    func retrieve(query: String, limit: Int) async throws -> [DocumentSnippet]
}

/// Returns nothing. Safe default when no RAG backend is available.
struct NoDocumentRetriever: DocumentRetriever {
    func retrieve(query: String, limit: Int) async throws -> [DocumentSnippet] { [] }
}

/// Retrieves chunks by calling an MCP tool on MemPalace.
///
/// MemPalace has no standalone document corpus — document chunks are
/// stored as drawers in a dedicated wing (default `documents`). This
/// retriever calls `mempalace_search` filtered to that wing.
actor MCPDocumentRetriever: DocumentRetriever {
    static let defaultWing = "documents"

    private let client: MCPClient
    private let toolName: String
    private let wing: String?

    init(
        client: MCPClient,
        toolName: String = "mempalace_search",
        wing: String? = MCPDocumentRetriever.defaultWing
    ) {
        self.client = client
        self.toolName = toolName
        self.wing = wing
    }

    func retrieve(query: String, limit: Int) async throws -> [DocumentSnippet] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var fields: [String: JSONValue] = [
            "query": .string(trimmed),
            "limit": .int(Int64(limit)),
        ]
        if let wing { fields["wing"] = .string(wing) }
        let result = try await client.callTool(
            name: toolName,
            arguments: .object(fields)
        )
        if result.isError == true { return [] }
        return result.content.compactMap { Self.parse(content: $0) }
    }

    private static func parse(content: MCPToolCallResult.Content) -> DocumentSnippet? {
        guard content.type == "text", let text = content.text, !text.isEmpty else {
            return nil
        }
        if let data = text.data(using: .utf8),
           let snippet = try? JSONDecoder().decode(DocumentSnippet.self, from: data) {
            return snippet
        }
        return DocumentSnippet(text: text)
    }
}
