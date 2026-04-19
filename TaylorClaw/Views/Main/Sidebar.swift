import SwiftUI

struct Sidebar: View {
    @Bindable var viewModel: ConversationListViewModel
    @ObservedObject var preferences: Preferences

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchField
            list
        }
        .frame(minWidth: 220)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text("Taylor Claw")
                .font(.headline)
            Spacer()
            Button {
                viewModel.newConversation(mode: preferences.defaultChatMode)
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.plain)
            .help("New chat (⌘N)")
            .keyboardShortcut("n", modifiers: .command)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $viewModel.searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var list: some View {
        List(selection: $viewModel.selectedID) {
            ForEach(viewModel.filtered) { convo in
                ConversationRow(conversation: convo)
                    .tag(convo.id)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.delete(id: convo.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            viewModel.delete(id: convo.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(conversation.title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(conversation.lastMessagePreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(relativeTimestamp)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: conversation.updatedAt, relativeTo: Date())
    }
}
