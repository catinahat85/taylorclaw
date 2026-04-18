import Foundation

struct ChatRequest: Sendable {
    let model: LLMModel
    let messages: [Message]
    let systemPrompt: String?
    let tools: [MCPTool]
    let temperature: Double?
    let maxTokens: Int?

    init(
        model: LLMModel,
        messages: [Message],
        systemPrompt: String? = nil,
        tools: [MCPTool] = [],
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) {
        self.model = model
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.tools = tools
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

enum ChatStreamChunk: Sendable {
    case text(String)
    /// A tool call has begun. Subsequent `toolInputDelta` events with the
    /// same id append to the partial JSON input until `toolUseEnd`.
    case toolUseStart(id: String, name: String)
    case toolInputDelta(id: String, jsonFragment: String)
    case toolUseEnd(id: String)
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
