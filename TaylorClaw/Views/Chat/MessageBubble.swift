import SwiftUI
import MarkdownUI

struct MessageBubble: View {
    let message: Message
    let isStreaming: Bool

    @State private var isHovering: Bool = false
    @State private var didCopy: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user { Spacer(minLength: 48) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if !message.content.isEmpty || message.toolCalls.isEmpty {
                    bubble
                }
                ForEach(message.toolCalls) { call in
                    ToolCallView(call: call)
                        .frame(maxWidth: 640, alignment: .leading)
                }
                metadata
                    .opacity(isHovering ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: isHovering)
            }

            if message.role != .user { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var bubble: some View {
        Markdown(message.content.isEmpty ? "…" : message.content)
            .markdownTheme(.gitHub)
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottomTrailing) { cursor }
            .frame(maxWidth: 640, alignment: message.role == .user ? .trailing : .leading)
    }

    @ViewBuilder
    private var cursor: some View {
        if isStreaming && message.role == .assistant {
            Text("▍")
                .font(.system(.body, design: .monospaced))
                .opacity(0.6)
                .padding(.trailing, 10)
                .padding(.bottom, 6)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var metadata: some View {
        HStack(spacing: 8) {
            if message.role == .assistant {
                Button {
                    copyContent()
                } label: {
                    Label(didCopy ? "Copied" : "Copy",
                          systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .help(didCopy ? "Copied" : "Copy message")
            }

            Text(timestamp)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if message.role == .user {
                Button {
                    copyContent()
                } label: {
                    Label(didCopy ? "Copied" : "Copy",
                          systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .help(didCopy ? "Copied" : "Copy message")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var background: some ShapeStyle {
        message.role == .user
            ? AnyShapeStyle(Color.accentColor)
            : AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
    }

    private var foreground: Color {
        message.role == .user ? .white : .primary
    }

    private var timestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: message.createdAt, relativeTo: Date())
    }

    private func copyContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            didCopy = false
        }
    }
}
