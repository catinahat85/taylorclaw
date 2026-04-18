import Foundation

struct GeminiProvider: LLMProvider {
    let id: ProviderID = .gemini

    private let baseURL = URL(string: "https://generativelanguage.googleapis.com")!
    private let keychain: KeychainStore
    private let session: URLSession

    init(keychain: KeychainStore = .shared, session: URLSession = .shared) {
        self.keychain = keychain
        self.session = session
    }

    func testConnection() async throws {
        let key = try await resolveKey()
        var components = URLComponents(
            url: baseURL.appendingPathComponent("/v1beta/models"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "key", value: key)]
        guard let url = components?.url else { throw LLMError.invalidURL }
        let (_, response) = try await session.data(from: url)
        try ensureOK(response)
    }

    func streamChat(
        _ request: ChatRequest
    ) async throws -> AsyncThrowingStream<ChatStreamChunk, any Error> {
        let key = try await resolveKey()
        let path = "/v1beta/models/\(request.model.id):streamGenerateContent"
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "alt", value: "sse"),
            URLQueryItem(name: "key", value: key)
        ]
        guard let url = components?.url else { throw LLMError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        guard let key = try await keychain.load(for: .gemini), !key.isEmpty else {
            throw LLMError.missingAPIKey(.gemini)
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
        return chunk.candidates?.first?.content?.parts?.compactMap(\.text).joined()
    }

    private struct Payload: Encodable {
        let contents: [Content]
        let systemInstruction: Content?
        let generationConfig: GenerationConfig?

        init(request: ChatRequest) {
            self.contents = request.messages
                .filter { $0.role != .system }
                .map { Content(role: $0.role == .assistant ? "model" : "user",
                               parts: [Part(text: $0.content)]) }
            let sys = request.systemPrompt
                ?? request.messages.first { $0.role == .system }?.content
            self.systemInstruction = sys.map { Content(role: "system", parts: [Part(text: $0)]) }
            if request.temperature != nil || request.maxTokens != nil {
                self.generationConfig = GenerationConfig(
                    temperature: request.temperature,
                    maxOutputTokens: request.maxTokens
                )
            } else {
                self.generationConfig = nil
            }
        }
    }

    private struct Content: Codable {
        let role: String?
        let parts: [Part]?
    }

    private struct Part: Codable {
        let text: String?
    }

    private struct GenerationConfig: Encodable {
        let temperature: Double?
        let maxOutputTokens: Int?
    }

    private struct Chunk: Decodable {
        let candidates: [Candidate]?
        struct Candidate: Decodable {
            let content: Content?
        }
    }
}
