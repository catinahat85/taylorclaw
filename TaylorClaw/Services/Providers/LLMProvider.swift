import Foundation

struct ChatRequest: Sendable {
    let model: LLMModel
    let messages: [Message]
    let systemPrompt: String?
    let temperature: Double?
    let maxTokens: Int?

    init(
        model: LLMModel,
        messages: [Message],
        systemPrompt: String? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) {
        self.model = model
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

enum ChatStreamChunk: Sendable {
    case text(String)
    case done
}

protocol LLMProvider: Sendable {
    var id: ProviderID { get }

    func availableModels() async throws -> [LLMModel]

    func streamChat(_ request: ChatRequest) async throws -> AsyncThrowingStream<ChatStreamChunk, any Error>

    func testConnection() async throws
}

extension LLMProvider {
    func availableModels() async throws -> [LLMModel] {
        ModelCatalog.staticModels(for: id)
    }
}
