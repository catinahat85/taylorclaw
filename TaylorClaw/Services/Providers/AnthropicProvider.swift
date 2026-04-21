import Foundation

struct AnthropicProvider: LLMProvider {
    let id: ProviderID = .anthropic

    private let baseURL = URL(string: "https://api.anthropic.com")!
    private let apiVersion = "2023-06-01"
    private let keychain: KeychainStore
    private let session: URLSession

    init(keychain: KeychainStore = .shared, session: URLSession = .shared) {
        self.keychain = keychain
        self.session = session
    }

    func testConnection() async throws {
        _ = try await resolveKey()
        let probe = Message(role: .user, content: "ping")
        let model = ModelCatalog.anthropic.last ?? ModelCatalog.defaultModel
        let stream = try await streamChat(
            ChatRequest(model: model, messages: [probe], maxTokens: 1)
        )
        for try await _ in stream { break }
    }

    func streamChat(
        _ request: ChatRequest
    ) async throws -> AsyncThrowingStream<ChatStreamChunk, any Error> {
        let key = try await resolveKey()
        let url = baseURL.appendingPathComponent("/v1/messages")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("text/event-stream", forHTTPHeaderField: "accept")

        let payload = Payload(request: request)
        req.httpBody = try JSONEncoder().encode(payload)

        let (bytes, response) = try await session.bytes(for: req)
        try ensureOK(response)

        return AsyncThrowingStream { continuation in
            let task = Task {
                var parser = SSEParser()
                // Per-content-block tracking: index → tool_use id+name when the
                // block is a tool_use. Lets us tag input_json_delta events with
                // their tool id.
                var toolBlocks: [Int: String] = [:]
                do {
                    for try await line in bytes.lines {
                        let events = parser.feed(line + "\n")
                        for event in events {
                            let chunks = Self.mapEvent(event, toolBlocks: &toolBlocks)
                            for chunk in chunks {
                                continuation.yield(chunk)
                                if case .done = chunk {
                                    continuation.finish()
                                    return
                                }
                            }
                        }
                        try Task.checkCancellation()
                    }
                    continuation.yield(.done)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func resolveKey() async throws -> String {
        guard let key = try await keychain.load(for: .anthropic), !key.isEmpty else {
            throw LLMError.missingAPIKey(.anthropic)
        }
        return key
    }

    private func ensureOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.invalidResponse(status: http.statusCode, body: nil)
        }
    }

    private static func mapEvent(
        _ event: SSEEvent,
        toolBlocks: inout [Int: String]
    ) -> [ChatStreamChunk] {
        if event.event == "message_stop" { return [.done] }
        guard let data = event.data.data(using: .utf8) else { return [] }
        guard let decoded = try? JSONDecoder().decode(StreamEvent.self, from: data) else {
            return []
        }
        switch decoded.type {
        case "content_block_start":
            guard let idx = decoded.index, let block = decoded.content_block else { return [] }
            if block.type == "tool_use", let id = block.id, let name = block.name {
                toolBlocks[idx] = id
                return [.toolUseStart(id: id, name: name)]
            }
            return []
        case "content_block_delta":
            guard let idx = decoded.index, let delta = decoded.delta else { return [] }
            if let text = delta.text { return [.text(text)] }
            if let partial = delta.partial_json, let id = toolBlocks[idx] {
                return [.toolInputDelta(id: id, jsonFragment: partial)]
            }
            return []
        case "content_block_stop":
            if let idx = decoded.index, let id = toolBlocks.removeValue(forKey: idx) {
                return [.toolUseEnd(id: id)]
            }
            return []
        case "message_stop":
            return [.done]
        default:
            return []
        }
    }

    // MARK: - Payload encoding

    private struct Payload: Encodable {
        let model: String
        let messages: [PayloadMessage]
        let system: String?
        let tools: [PayloadTool]?
        let max_tokens: Int
        let temperature: Double?
        let stream: Bool

        init(request: ChatRequest) {
            self.model = request.model.id
            self.messages = request.messages
                .filter { $0.role != .system }
                .map { PayloadMessage(message: $0) }
            let sys = request.messages.first { $0.role == .system }?.content
            self.system = request.systemPrompt ?? sys
            self.tools = request.tools.isEmpty ? nil : request.tools.map(PayloadTool.init)
            self.max_tokens = request.maxTokens ?? 4096
            self.temperature = request.temperature
            self.stream = true
        }
    }

    /// Anthropic's content blocks: text, tool_use (assistant), tool_result (user).
    private struct PayloadMessage: Encodable {
        let role: String
        let content: [Block]

        init(message: Message) {
            self.role = message.role == .assistant ? "assistant" : "user"
            var blocks: [Block] = []
            switch message.role {
            case .assistant:
                if !message.content.isEmpty {
                    blocks.append(.text(message.content))
                }
                for call in message.toolCalls {
                    blocks.append(.toolUse(id: call.id, name: call.name, input: call.input))
                }
            case .user, .system:
                let results = message.toolCalls.filter { $0.result != nil }
                if !results.isEmpty {
                    for call in results {
                        blocks.append(.toolResult(
                            toolUseID: call.id,
                            content: call.result ?? "",
                            isError: call.isError
                        ))
                    }
                    if !message.content.isEmpty {
                        blocks.append(.text(message.content))
                    }
                } else {
                    blocks.append(.text(message.content))
                }
            }
            self.content = blocks.isEmpty ? [.text("")] : blocks
        }

        enum Block: Encodable {
            case text(String)
            case toolUse(id: String, name: String, input: JSONValue)
            case toolResult(toolUseID: String, content: String, isError: Bool)

            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .text(let t):
                    try c.encode("text", forKey: .type)
                    try c.encode(t, forKey: .text)
                case .toolUse(let id, let name, let input):
                    try c.encode("tool_use", forKey: .type)
                    try c.encode(id, forKey: .id)
                    try c.encode(name, forKey: .name)
                    try c.encode(input, forKey: .input)
                case .toolResult(let id, let content, let isError):
                    try c.encode("tool_result", forKey: .type)
                    try c.encode(id, forKey: .tool_use_id)
                    try c.encode(content, forKey: .content)
                    if isError { try c.encode(true, forKey: .is_error) }
                }
            }

            enum CodingKeys: String, CodingKey {
                case type, text, id, name, input
                case tool_use_id, content, is_error
            }
        }
    }

    private struct PayloadTool: Encodable {
        let name: String
        let description: String?
        let input_schema: JSONValue

        init(tool: MCPTool) {
            self.name = tool.name
            self.description = tool.description
            // Anthropic requires an object schema; default to permissive empty.
            self.input_schema = tool.inputSchema ?? .object([
                "type": .string("object"),
                "properties": .object([:]),
            ])
        }
    }

    // MARK: - Stream decoding

    private struct StreamEvent: Decodable {
        let type: String
        let index: Int?
        let delta: Delta?
        let content_block: ContentBlock?

        struct Delta: Decodable {
            let type: String?
            let text: String?
            let partial_json: String?
            let stop_reason: String?
        }

        struct ContentBlock: Decodable {
            let type: String
            let id: String?
            let name: String?
        }
    }
}
