import Foundation

// Set TAYLOR_CLAW_DEBUG=1 in the Xcode scheme to enable stream logging.
private let debugLogging: Bool = ProcessInfo.processInfo.environment["TAYLOR_CLAW_DEBUG"] == "1"

private func orLog(_ message: String) {
    guard debugLogging else { return }
    NSLog("[OpenRouter] %@", message)
}

struct OpenRouterProvider: LLMProvider {
    let id: ProviderID = .openrouter

    private let baseURL = URL(string: "https://openrouter.ai")!
    private let keychain: KeychainStore
    private let session: URLSession
    private let firstTokenTimeout: TimeInterval

    init(
        keychain: KeychainStore = .shared,
        session: URLSession = .shared,
        firstTokenTimeout: TimeInterval = 60
    ) {
        self.keychain = keychain
        self.session = session
        self.firstTokenTimeout = firstTokenTimeout
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
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("https://github.com/catinahat85/taylorclaw",
                     forHTTPHeaderField: "HTTP-Referer")
        req.setValue("Taylor Claw", forHTTPHeaderField: "X-Title")

        orLog("POST \(url) model=\(request.model.id)")

        let payload = Payload(request: request)
        req.httpBody = try JSONEncoder().encode(payload)

        let (bytes, response) = try await session.bytes(for: req)
        try ensureOK(response)

        let timeoutInterval = firstTokenTimeout

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var lineCount = 0

                    let timeoutTask = Task {
                        do {
                            try await Task.sleep(nanoseconds: UInt64(timeoutInterval * 1_000_000_000))
                            continuation.finish(
                                throwing: LLMError.network("No response from OpenRouter after \(Int(timeoutInterval))s. Check model ID and credits.")
                            )
                        } catch {
                            // Cancelled — first token arrived or stream ended.
                        }
                    }
                    defer { timeoutTask.cancel() }

                    for try await line in bytes.lines {
                        lineCount += 1
                        orLog("raw[\(lineCount)]: \(line)")

                        let trimmed = line.trimmingCharacters(in: .whitespaces)

                        // Skip blank lines and SSE comments
                        guard !trimmed.isEmpty, !trimmed.hasPrefix(":") else { continue }

                        // Only handle data: fields
                        guard trimmed.hasPrefix("data:") else {
                            orLog("skip non-data field: \(trimmed)")
                            continue
                        }

                        // Strip "data:" prefix and optional leading space
                        var payload = String(trimmed.dropFirst(5))
                        if payload.hasPrefix(" ") { payload.removeFirst() }

                        orLog("data: \(payload)")

                        if payload == "[DONE]" {
                            orLog("stream done")
                            timeoutTask.cancel()
                            continuation.yield(.done)
                            continuation.finish()
                            return
                        }

                        // Try to extract an error from the body before yielding text
                        if let bodyError = Self.errorFrom(payload) {
                            orLog("body error: \(bodyError)")
                            timeoutTask.cancel()
                            continuation.finish(throwing: LLMError.invalidResponse(status: 200, body: bodyError))
                            return
                        }

                        if let text = Self.textFrom(payload) {
                            orLog("text: \(text)")
                            timeoutTask.cancel()
                            continuation.yield(.text(text))
                        } else {
                            orLog("parsed chunk had no text (role-only or empty delta)")
                        }

                        try Task.checkCancellation()
                    }

                    orLog("stream ended after \(lineCount) lines")
                    timeoutTask.cancel()
                    continuation.yield(.done)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMError.cancelled)
                } catch let error as LLMError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: LLMError.network(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Private helpers

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

    private static func textFrom(_ dataPayload: String) -> String? {
        guard let data = dataPayload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(Chunk.self, from: data) else {
            return nil
        }
        return chunk.choices.first?.delta.content
    }

    private static func errorFrom(_ dataPayload: String) -> String? {
        guard let data = dataPayload.data(using: .utf8),
              let obj = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
              let msg = obj.error?.message else {
            return nil
        }
        return msg
    }

    // MARK: - Codable types

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
        struct Choice: Decodable {
            let delta: Delta
        }
        struct Delta: Decodable {
            let content: String?
        }
    }

    private struct ErrorEnvelope: Decodable {
        let error: APIError?
        struct APIError: Decodable {
            let message: String?
            let code: Int?
        }
    }
}
