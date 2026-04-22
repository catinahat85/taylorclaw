import Foundation
import Observation

@MainActor
@Observable
final class ChatViewModel {
    var conversation: Conversation
    var composerText: String = ""
    var selectedModel: LLMModel
    var isStreaming: Bool = false
    var errorMessage: String?

    private let registry: ProviderRegistry
    private let store: ConversationStore
    private let memPalace: MemPalaceServer
    private let guardian: AgentGuard
    private var streamingTask: Task<Void, Never>?

    /// Max sequential model turns per send (i.e. tool-use round trips).
    private let maxTurns = 10

    init(
        conversation: Conversation,
        selectedModel: LLMModel,
        registry: ProviderRegistry = .shared,
        store: ConversationStore = .shared,
        memPalace: MemPalaceServer = .shared,
        guardian: AgentGuard = AgentGuard(prompter: AutoApprovePrompter())
    ) {
        self.conversation = conversation
        self.selectedModel = selectedModel
        self.registry = registry
        self.store = store
        self.memPalace = memPalace
        self.guardian = guardian
    }

    var canSend: Bool {
        !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }

    /// Binding-friendly mode accessor. Writes persist the conversation so
    /// the mode survives across sessions.
    var mode: ChatMode {
        get { conversation.mode }
        set {
            guard conversation.mode != newValue else { return }
            conversation.mode = newValue
            persist()
        }
    }

    func send() {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        let userMessage = Message(
            role: .user,
            content: trimmed,
            modelID: selectedModel.id,
            providerID: selectedModel.provider.rawValue
        )
        let assistantMessage = Message(
            role: .assistant,
            content: "",
            modelID: selectedModel.id,
            providerID: selectedModel.provider.rawValue
        )

        conversation.messages.append(userMessage)
        conversation.messages.append(assistantMessage)
        conversation.lastProviderID = selectedModel.provider.rawValue
        conversation.lastModelID = selectedModel.id
        if conversation.title == "New Conversation" {
            conversation.title = Self.titleFrom(trimmed)
        }
        composerText = ""
        errorMessage = nil
        isStreaming = true

        persist()

        let provider = registry.provider(for: selectedModel.provider)
        let model = selectedModel
        let currentMode = conversation.mode
        let memoryQuery = trimmed
        let memPalace = self.memPalace
        let guardian = self.guardian

        streamingTask = Task { [weak self] in
            guard let self else { return }
            do {
                var tools: [MCPTool] = []
                var memory: any MemoryRetriever = NoMemoryRetriever()
                var documents: any DocumentRetriever = NoDocumentRetriever()

                if currentMode == .agent {
                    do {
                        try await memPalace.start()
                        memory = await memPalace.memoryRetriever()
                        documents = await memPalace.documentRetriever()
                        tools = await memPalace.listTools()
                    } catch {
                        self.errorMessage = "MemPalace unavailable (\(error.localizedDescription)). Continuing without tools."
                    }
                }

                var assistantIdx = self.conversation.messages.count - 1

                for _ in 0..<self.maxTurns {
                    try Task.checkCancellation()

                    let history = self.messagesForProvider()
                    let assembler = ContextAssembler(
                        mode: currentMode,
                        budget: .forModel(model),
                        tools: tools,
                        memoryRetriever: memory,
                        documentRetriever: documents
                    )
                    let context = await assembler.assemble(
                        messages: history,
                        memoryQuery: memoryQuery
                    )
                    let request = ChatRequest(
                        model: model,
                        messages: context.messages,
                        systemPrompt: context.systemPrompt.isEmpty ? nil : context.systemPrompt,
                        tools: tools
                    )

                    let pendingCalls = try await self.runTurn(
                        provider: provider,
                        request: request,
                        assistantIndex: assistantIdx
                    )

                    guard !pendingCalls.isEmpty else { break }

                    // Execute each tool call, then append a user message with
                    // results and a fresh empty assistant slot for the next turn.
                    var resultCalls: [ToolCall] = []
                    for call in pendingCalls {
                        try Task.checkCancellation()
                        let outcome = await Self.runTool(
                            call: call,
                            guardian: guardian,
                            memPalace: memPalace
                        )
                        resultCalls.append(outcome)
                    }

                    let resultMessage = Message(
                        role: .user,
                        content: "",
                        modelID: model.id,
                        providerID: model.provider.rawValue,
                        toolCalls: resultCalls
                    )
                    let nextAssistant = Message(
                        role: .assistant,
                        content: "",
                        modelID: model.id,
                        providerID: model.provider.rawValue
                    )
                    self.conversation.messages.append(resultMessage)
                    self.conversation.messages.append(nextAssistant)
                    assistantIdx = self.conversation.messages.count - 1
                    self.persist()
                }

                self.finishStreaming()
            } catch is CancellationError {
                self.finishStreaming(error: nil)
            } catch let error as LLMError {
                self.finishStreaming(error: error.errorDescription)
            } catch {
                self.finishStreaming(error: error.localizedDescription)
            }
        }
    }

    func stop() {
        streamingTask?.cancel()
    }

    func retryLast() {
        guard let last = conversation.messages.last(where: { $0.role == .user }) else { return }
        composerText = last.content
        if let assistantIdx = conversation.messages.lastIndex(where: { $0.role == .assistant }),
           assistantIdx > (conversation.messages.lastIndex(where: { $0.role == .user }) ?? -1) {
            conversation.messages.remove(at: assistantIdx)
        }
        if let userIdx = conversation.messages.lastIndex(where: { $0.role == .user }) {
            conversation.messages.remove(at: userIdx)
        }
        errorMessage = nil
        send()
    }

    func clear() {
        stop()
        conversation.messages.removeAll()
        conversation.title = "New Conversation"
        errorMessage = nil
        persist()
        Task { [guardian] in await guardian.reset() }
    }

    // MARK: - Turn execution

    /// Streams one model turn into `conversation.messages[assistantIndex]`.
    /// Returns the (input-complete) tool calls produced this turn — caller
    /// runs them, appends the result message, and loops.
    private func runTurn(
        provider: any LLMProvider,
        request: ChatRequest,
        assistantIndex: Int
    ) async throws -> [ToolCall] {
        var inProgress: [String: ToolBuilder] = [:]
        var orderedIDs: [String] = []
        var completed: [ToolCall] = []

        let stream = try await provider.streamChat(request)
        for try await chunk in stream {
            try Task.checkCancellation()
            switch chunk {
            case .text(let text):
                if assistantIndex < self.conversation.messages.count {
                    self.conversation.messages[assistantIndex].content.append(text)
                }
            case .toolUseStart(let id, let name):
                inProgress[id] = ToolBuilder(name: name)
                orderedIDs.append(id)
            case .toolInputDelta(let id, let fragment):
                inProgress[id]?.inputJSON.append(fragment)
            case .toolUseEnd(let id):
                guard let builder = inProgress.removeValue(forKey: id) else { continue }
                let input = Self.parseInput(builder.inputJSON)
                let call = ToolCall(id: id, name: builder.name, input: input)
                completed.append(call)
                if assistantIndex < self.conversation.messages.count {
                    self.conversation.messages[assistantIndex].toolCalls.append(call)
                }
            case .done:
                break
            }
        }
        // Flush any tool blocks that didn't get an explicit stop event.
        for id in orderedIDs where inProgress[id] != nil {
            if let builder = inProgress.removeValue(forKey: id) {
                let input = Self.parseInput(builder.inputJSON)
                let call = ToolCall(id: id, name: builder.name, input: input)
                completed.append(call)
                if assistantIndex < self.conversation.messages.count {
                    self.conversation.messages[assistantIndex].toolCalls.append(call)
                }
            }
        }
        return completed
    }

    /// Authorize via `AgentGuard`, dispatch to `MemPalaceServer`, and return
    /// the same `ToolCall` populated with `result` / `isError`. Errors and
    /// denials are encoded as tool-side errors so the model can recover.
    private static func runTool(
        call: ToolCall,
        guardian: AgentGuard,
        memPalace: MemPalaceServer
    ) async -> ToolCall {
        var resolved = call
        do {
            try await guardian.authorize(
                toolName: call.name,
                serverName: "mempalace",
                arguments: call.input
            )
        } catch {
            resolved.result = "Tool call refused: \(error)"
            resolved.isError = true
            return resolved
        }
        do {
            let result = try await memPalace.callTool(name: call.name, arguments: call.input)
            let text = result.content.compactMap { $0.text }.joined(separator: "\n")
            resolved.result = text.isEmpty ? "(no output)" : text
            resolved.isError = result.isError ?? false
            await guardian.recordResult(
                toolName: call.name,
                serverName: "mempalace",
                success: !resolved.isError
            )
        } catch {
            resolved.result = "Tool error: \(error)"
            resolved.isError = true
            await guardian.recordResult(
                toolName: call.name,
                serverName: "mempalace",
                success: false,
                error: "\(error)"
            )
        }
        return resolved
    }

    private static func parseInput(_ raw: String) -> JSONValue {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .object([:])
        }
        return value
    }

    private struct ToolBuilder {
        let name: String
        var inputJSON: String = ""
    }

    // MARK: - Bookkeeping

    private func messagesForProvider() -> [Message] {
        conversation.messages.dropLast().filter {
            !($0.role == .assistant && $0.content.isEmpty && $0.toolCalls.isEmpty)
        }
    }

    private func finishStreaming(error: String? = nil) {
        isStreaming = false
        streamingTask = nil
        if let error {
            errorMessage = error
        }
        if let lastIdx = conversation.messages.indices.last,
           conversation.messages[lastIdx].role == .assistant,
           conversation.messages[lastIdx].content.isEmpty,
           conversation.messages[lastIdx].toolCalls.isEmpty {
            conversation.messages.remove(at: lastIdx)
        }
        persist()
    }

    private func persist() {
        let snapshot = conversation
        Task.detached { [store] in
            try? await store.upsert(snapshot)
        }
    }

    private static func titleFrom(_ text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        if trimmed.count <= 40 { return String(trimmed) }
        let cutoff = trimmed.index(trimmed.startIndex, offsetBy: 40)
        return String(trimmed[..<cutoff]) + "…"
    }
}
