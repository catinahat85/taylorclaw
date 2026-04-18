import Foundation

struct OllamaProvider: LLMProvider {
    let id: ProviderID = .ollama

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://localhost:11434")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func testConnection() async throws {
        _ = try await fetchTags()
    }

    func availableModels() async throws -> [LLMModel] {
        let tags = try await fetchTags()
        return tags.models.map {
            LLMModel(provider: .ollama, id: $0.name, displayName: $0.name)
        }
    }

    func streamChat(
        _ request: ChatRequest
    ) async throws -> AsyncThrowingStream<ChatStreamChunk, any Error> {
        let url = baseURL.appendingPathComponent("/api/chat")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = Payload(request: request)
        req.httpBody = try JSONEncoder().encode(payload)

        let (bytes, response) = try await session.bytes(for: req)
        try ensureOK(response)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }
                        guard let data = trimmed.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(Chunk.self, from: data) else {
                            continue
                        }
                        if let text = chunk.message?.content, !text.isEmpty {
                            continuation.yield(.text(text))
                        }
                        if chunk.done {
                            continuation.yield(.done)
                            continuation.finish()
                            return
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

    private func fetchTags() async throws -> TagsResponse {
        let url = baseURL.appendingPathComponent("/api/tags")
        do {
            let (data, response) = try await session.data(from: url)
            try ensureOK(response)
            return try JSONDecoder().decode(TagsResponse.self, from: data)
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.providerUnavailable(
                .ollama,
                reason: "Could not reach \(baseURL.absoluteString). Is Ollama running?"
            )
        }
    }

    private func ensureOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.invalidResponse(status: http.statusCode, body: nil)
        }
    }

    private struct Payload: Encodable {
        let model: String
        let messages: [PayloadMessage]
        let stream: Bool
        let options: Options?

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
            self.stream = true
            if request.temperature != nil || request.maxTokens != nil {
                self.options = Options(
                    temperature: request.temperature,
                    num_predict: request.maxTokens
                )
            } else {
                self.options = nil
            }
        }
    }

    private struct PayloadMessage: Encodable {
        let role: String
        let content: String
    }

    private struct Options: Encodable {
        let temperature: Double?
        let num_predict: Int?
    }

    private struct Chunk: Decodable {
        let message: ChunkMessage?
        let done: Bool
    }

    private struct ChunkMessage: Decodable {
        let role: String?
        let content: String?
    }

    private struct TagsResponse: Decodable {
        let models: [TagModel]
    }

    private struct TagModel: Decodable {
        let name: String
    }
}
