import SwiftUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    let availableProviders: Set<ProviderID>
    let ollamaModels: [LLMModel]
    let openRouterModels: [LLMModel]
    let onChange: (ChatViewModel) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                toolbar
                Divider()
                content
                ComposerView(
                    text: $viewModel.composerText,
                    isStreaming: viewModel.isStreaming,
                    canSend: viewModel.canSend,
                    onSend: {
                        viewModel.send()
                        onChange(viewModel)
                    },
                    onStop: { viewModel.stop() }
                )
            }
            if let error = viewModel.errorMessage {
                ErrorBanner(
                    message: error,
                    onRetry: { viewModel.retryLast() },
                    onDismiss: { viewModel.errorMessage = nil }
                )
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(viewModel.conversation.title)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Picker("Mode", selection: Binding(
                get: { viewModel.mode },
                set: { viewModel.mode = $0; onChange(viewModel) }
            )) {
                ForEach(ChatMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("Chat: stateless. Agent: adds memory, documents, and tool schemas to the system prompt.")
            ModelPicker(
                selected: $viewModel.selectedModel,
                availableProviders: availableProviders,
                ollamaModels: ollamaModels,
                openRouterModels: openRouterModels
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.conversation.messages.isEmpty {
            EmptyStateView(
                title: "Start the conversation",
                subtitle: "Ask anything. Switch models with the menu in the top right; your chat history is saved locally."
            )
        } else {
            MessageList(
                messages: viewModel.conversation.messages,
                isStreaming: viewModel.isStreaming
            )
        }
    }
}
