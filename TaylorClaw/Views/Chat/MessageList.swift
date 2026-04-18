import SwiftUI

struct MessageList: View {
    let messages: [Message]
    let isStreaming: Bool

    var body: some View {
        let display = Self.collapseToolResults(messages)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(display.enumerated()), id: \.element.id) { index, message in
                        MessageBubble(
                            message: message,
                            isStreaming: isStreaming && index == display.count - 1
                                && message.role == .assistant
                        )
                        .id(message.id)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: messages.last?.id) { _, _ in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    /// Tool-result messages (user role, empty text, all tool calls have a
    /// `result`) only exist to round-trip results back to the model. Merge
    /// those results into the matching assistant tool_use call so the UI
    /// shows one block per tool invocation.
    private static func collapseToolResults(_ messages: [Message]) -> [Message] {
        var resultsByID: [String: ToolCall] = [:]
        for m in messages where Self.isToolResultMessage(m) {
            for call in m.toolCalls where call.result != nil {
                resultsByID[call.id] = call
            }
        }
        guard !resultsByID.isEmpty else { return messages }
        return messages.compactMap { m in
            if Self.isToolResultMessage(m) { return nil }
            guard m.role == .assistant, !m.toolCalls.isEmpty else { return m }
            var merged = m
            merged.toolCalls = m.toolCalls.map { call in
                if let result = resultsByID[call.id] {
                    var c = call
                    c.result = result.result
                    c.isError = result.isError
                    return c
                }
                return call
            }
            return merged
        }
    }

    private static func isToolResultMessage(_ message: Message) -> Bool {
        message.role == .user
            && message.content.isEmpty
            && !message.toolCalls.isEmpty
            && message.toolCalls.allSatisfy { $0.result != nil }
    }
}
