import Foundation

struct OpenRouterProvider: LLMProvider {
    let id: ProviderID = .openrouter

    private let baseURL = URL(string: "https://openrouter.ai")!
    private let keychain: KeychainStore
    private let session: URLSession

    init(keychain: KeychainStore = .shared, session: URLSession = .shared) {
        self.keychain = keychain
        self.session = session
    }

    func testConnection() async throws {
        let key = try await resolveKey()
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/v1/auth/key"))
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: req)
        try ensureOK(response)
    }

    func streamChat(
        _ request: ChatRequest
    ) async throws -> AsyncThrowingStream<ChatStreamChunk, any Error> {
        let key = try await resolveKey()
        let url = baseURL.appendingPathComponent("/api/v1/chat/completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "accept")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("https://github.com/catinahat85/taylorclaw",
                     forHTTPHeaderField: "HTTP-Referer")
        req.setValue("Taylor Claw", forHTTPHeaderField: "X-Title")

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
                            if event.data == "[DONE]" {
                                continuation.yield(.done)
                                continuation.finish()
                                return
                            }
                            if let text = Self.textFrom(event) {
                                continuation.yield(.text(text))
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
        guard let key = try await keychain.load(for: .openrouter), !key.isEmpty else {
            throw LLMError.missingAPIKey(.openrouter)
        }
        return key
    }

    private func ensureOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.invalidResponse(status: http.statusCode, body: nil)
        }
    }

    private static func textFrom(_ event: SSEEvent) -> String? {
        guard let data = event.data.data(using: .utf8) else { return nil }
        guard let chunk = try? JSONDecoder().decode(Chunk.self, from: data) else { return nil }
        return chunk.choices.first?.delta.content
    }

    private struct Payload: Encodable {
        let model: String
        let messages: [PayloadMessage]
        let temperature: Double?
        let max_tokens: Int?
        let stream: Bool

        init(request: ChatRequest) {
            self.model = request.model.id
            var msgs: [PayloadMessage] = []
            if let sys = request.systemPrompt {
                msgs.append(PayloadMessage(role: "system", content: sys))
            }
            for m in request.messages {
                msgs.append(PayloadMessage(role: m.role.rawValue, content: m.content))
            }
            self.messages = msgs
            self.temperature = request.temperature
            self.max_tokens = request.maxTokens
            self.stream = true
        }
    }

    private struct PayloadMessage: Encodable {
        let role: String
        let content: String
    }

    private struct Chunk: Decodable {
        let choices: [Choice]
        struct Choice: Decodable { let delta: Delta }
        struct Delta: Decodable { let content: String? }
    }
}
