import SwiftUI
import UniformTypeIdentifiers

struct ComposerView: View {
    @Binding var text: String
    let isStreaming: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onAttach: ([URL]) -> Void

    @FocusState private var isFocused: Bool
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                attachButton

                TextEditor(text: $text)
                    .focused($isFocused)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .frame(minHeight: 32, maxHeight: 180)
                    .overlay(alignment: .topLeading) { placeholder }
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onSubmit(sendIfSingleLine)

                actionButton
            }
            .padding(12)
        }
        .background(.bar)
        .onAppear { isFocused = true }
    }

    @ViewBuilder
    private var placeholder: some View {
        if text.isEmpty {
            Text("Ask anything…")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .allowsHitTesting(false)
        }
    }

    private var attachButton: some View {
        Button {
            showImporter = true
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 16))
        }
        .buttonStyle(.plain)
        .help("Add documents to your knowledge base (used in Agent mode)")
        .frame(width: 32, height: 32)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: Self.allowedTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                onAttach(urls)
            }
        }
    }

    private static let allowedTypes: [UTType] = [
        .plainText, .text, .pdf, .rtf, .html,
        .json, .yaml, .sourceCode, .swiftSource,
    ]

    @ViewBuilder
    private var actionButton: some View {
        if isStreaming {
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(".", modifiers: .command)
            .help("Stop streaming (⌘.)")
        } else {
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        canSend ? Color.accentColor : Color.secondary.opacity(0.3),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Send (⌘↩)")
        }
    }

    private func sendIfSingleLine() {
        if !text.contains("\n") && canSend {
            onSend()
        }
    }
}
