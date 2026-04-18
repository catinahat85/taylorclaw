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
                do {
                    for try await line in bytes.lines {
                        let events = parser.feed(line + "\n")
                        for event in events {
                            if let chunk = try Self.mapEvent(event) {
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

    private static func mapEvent(_ event: SSEEvent) throws -> ChatStreamChunk? {
        if event.event == "message_stop" { return .done }
        guard let data = event.data.data(using: .utf8) else { return nil }
        let decoded = try JSONDecoder().decode(StreamEvent.self, from: data)
        switch decoded.type {
        case "content_block_delta":
            if let text = decoded.delta?.text { return .text(text) }
            return nil
        case "message_stop":
            return .done
        default:
            return nil
        }
    }

    private struct Payload: Encodable {
        let model: String
        let messages: [PayloadMessage]
        let system: String?
        let max_tokens: Int
        let temperature: Double?
        let stream: Bool

        init(request: ChatRequest) {
            self.model = request.model.id
            self.messages = request.messages
                .filter { $0.role != .system }
                .map { PayloadMessage(role: $0.role == .assistant ? "assistant" : "user", content: $0.content) }
            let sys = request.messages.first { $0.role == .system }?.content
            self.system = request.systemPrompt ?? sys
            self.max_tokens = request.maxTokens ?? 4096
            self.temperature = request.temperature
            self.stream = true
        }
    }

    private struct PayloadMessage: Encodable {
        let role: String
        let content: String
    }

    private struct StreamEvent: Decodable {
        let type: String
        let delta: Delta?

        struct Delta: Decodable {
            let type: String?
            let text: String?
        }
    }
}
