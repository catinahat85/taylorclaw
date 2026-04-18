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
    private var streamingTask: Task<Void, Never>?

    init(
        conversation: Conversation,
        selectedModel: LLMModel,
        registry: ProviderRegistry = .shared,
        store: ConversationStore = .shared
    ) {
        self.conversation = conversation
        self.selectedModel = selectedModel
        self.registry = registry
        self.store = store
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
        var assistantMessage = Message(
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

        let assistantIndex = conversation.messages.count - 1
        let provider = registry.provider(for: selectedModel.provider)
        let request = ChatRequest(model: selectedModel, messages: messagesForProvider())

        streamingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await provider.streamChat(request)
                for try await chunk in stream {
                    try Task.checkCancellation()
                    switch chunk {
                    case .text(let text):
                        assistantMessage.content.append(text)
                        if assistantIndex < self.conversation.messages.count {
                            self.conversation.messages[assistantIndex].content = assistantMessage.content
                        }
                    case .done:
                        break
                    }
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
    }

    private func messagesForProvider() -> [Message] {
        conversation.messages.dropLast().filter {
            !($0.role == .assistant && $0.content.isEmpty)
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
           conversation.messages[lastIdx].content.isEmpty {
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
