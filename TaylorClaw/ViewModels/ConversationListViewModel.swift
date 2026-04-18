import Foundation
import Observation

@MainActor
@Observable
final class ConversationListViewModel {
    var conversations: [Conversation] = []
    var selectedID: UUID?
    var searchText: String = ""

    private let store: ConversationStore

    init(store: ConversationStore = .shared) {
        self.store = store
    }

    var filtered: [Conversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return conversations }
        return conversations.filter { convo in
            if convo.title.lowercased().contains(query) { return true }
            return convo.messages.contains { $0.content.lowercased().contains(query) }
        }
    }

    var selected: Conversation? {
        guard let id = selectedID else { return nil }
        return conversations.first { $0.id == id }
    }

    func reload() async {
        do {
            conversations = try await store.all()
            if let id = selectedID, !conversations.contains(where: { $0.id == id }) {
                selectedID = conversations.first?.id
            } else if selectedID == nil {
                selectedID = conversations.first?.id
            }
        } catch {
            conversations = []
        }
    }

    func newConversation() {
        let convo = Conversation()
        conversations.insert(convo, at: 0)
        selectedID = convo.id
        Task.detached { [store] in
            try? await store.upsert(convo)
        }
    }

    func delete(id: UUID) {
        conversations.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = conversations.first?.id
        }
        Task.detached { [store] in
            try? await store.delete(id: id)
        }
    }

    func applyChanges(from viewModel: ChatViewModel) {
        if let idx = conversations.firstIndex(where: { $0.id == viewModel.conversation.id }) {
            conversations[idx] = viewModel.conversation
        } else {
            conversations.insert(viewModel.conversation, at: 0)
        }
    }
}
