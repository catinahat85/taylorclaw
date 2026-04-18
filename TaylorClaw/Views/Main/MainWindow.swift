import SwiftUI

@MainActor
final class ChatViewModelStore {
    private var vms: [UUID: ChatViewModel] = [:]

    func viewModel(for convo: Conversation, model: LLMModel) -> ChatViewModel {
        if let existing = vms[convo.id] { return existing }
        let vm = ChatViewModel(conversation: convo, selectedModel: model)
        vms[convo.id] = vm
        return vm
    }
}

struct MainWindow: View {
    @Bindable var listViewModel: ConversationListViewModel
    @Bindable var settingsViewModel: SettingsViewModel
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var preferences: Preferences

    @State private var chatVMStore = ChatViewModelStore()

    var body: some View {
        NavigationSplitView {
            Sidebar(viewModel: listViewModel)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            await settingsViewModel.load()
            await listViewModel.reload()
            if listViewModel.conversations.isEmpty {
                listViewModel.newConversation()
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if !settingsViewModel.hasAnyConfiguredProvider() {
            EmptyStateView(
                title: "Add an API key to get started",
                subtitle: "Taylor Claw uses your own API keys. Your keys stay in Keychain on this device — nothing is sent anywhere except the provider you pick.",
                actionTitle: "Open Settings",
                action: { openSettings() }
            )
        } else if let convo = listViewModel.selected {
            let vm = chatVMStore.viewModel(for: convo, model: resolveModel(for: convo))
            ChatView(
                viewModel: vm,
                availableProviders: availableProviders,
                ollamaModels: settingsViewModel.ollamaModels,
                openRouterModels: openRouterModels,
                onChange: { updated in
                    listViewModel.applyChanges(from: updated)
                }
            )
            .id(convo.id)
        } else {
            EmptyStateView(
                title: "No conversation selected",
                subtitle: "Pick one from the sidebar or start a new one.",
                actionTitle: "New Chat",
                action: { listViewModel.newConversation() }
            )
        }
    }

    private var availableProviders: Set<ProviderID> {
        var set: Set<ProviderID> = []
        for (provider, status) in settingsViewModel.statuses where status.hasKey {
            set.insert(provider)
        }
        if !settingsViewModel.ollamaModels.isEmpty {
            set.insert(.ollama)
        }
        return set
    }

    private var openRouterModels: [LLMModel] {
        preferences.openRouterModelIDs.map {
            LLMModel(provider: .openrouter, id: $0, displayName: $0)
        }
    }

    private func resolveModel(for convo: Conversation) -> LLMModel {
        if let providerRaw = convo.lastProviderID,
           let modelID = convo.lastModelID,
           let provider = ProviderID(rawValue: providerRaw) {
            if let existing = ModelCatalog.staticModels(for: provider).first(where: { $0.id == modelID }) {
                return existing
            }
            return LLMModel(provider: provider, id: modelID, displayName: modelID)
        }
        let preferred = preferences.defaultModel
        if availableProviders.contains(preferred.provider) { return preferred }
        if let first = availableProviders.first,
           let model = ModelCatalog.staticModels(for: first).first {
            return model
        }
        return ModelCatalog.defaultModel
    }
}
