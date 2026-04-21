import SwiftUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    let availableProviders: Set<ProviderID>
    let ollamaModels: [LLMModel]
    let openRouterModels: [LLMModel]
    let onChange: (ChatViewModel) -> Void
    let onAttach: ([URL]) -> Void

    private let agent = AgentSession.shared

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                toolbar
                Divider()
                if viewModel.mode == .agent {
                    AgentPanel(viewModel: viewModel, session: agent)
                }
                content
                ComposerView(
                    text: $viewModel.composerText,
                    isStreaming: viewModel.isStreaming,
                    canSend: viewModel.canSend,
                    onSend: {
                        viewModel.send()
                        onChange(viewModel)
                    },
                    onStop: { viewModel.stop() },
                    onAttach: onAttach
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
        .sheet(item: Binding(
            get: { agent.prompter.pending },
            set: { newValue in
                if newValue == nil { agent.prompter.dismiss() }
            }
        )) { request in
            ApprovalSheet(request: request) { decision in
                agent.prompter.resolve(decision)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(viewModel.conversation.title)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            modePicker
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

    private var modePicker: some View {
        Picker("Mode", selection: Binding(
            get: { viewModel.mode },
            set: { newValue in
                viewModel.mode = newValue
                onChange(viewModel)
            }
        )) {
            ForEach(ChatMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 160)
        .labelsHidden()
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
