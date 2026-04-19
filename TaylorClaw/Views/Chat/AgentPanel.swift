import SwiftUI

/// Read-only summary of agent-mode state shown above the message list when
/// `ChatViewModel.mode == .agent`. Phase F1 supports:
///   * MemPalace lifecycle status + start/stop button.
///   * Tool inventory.
///   * "Preview retrieval" — runs memory + document retrieval against the
///     composer text and shows what would be injected into the prompt.
///   * "Test approval" — fires a fake `ApprovalRequest` to exercise the
///     sheet wiring without involving the agent loop.
/// Phase F2 wires the real send loop.
struct AgentPanel: View {
    @Bindable var viewModel: ChatViewModel
    @Bindable var session: AgentSession

    @State private var memSnippets: [MemorySnippet] = []
    @State private var docSnippets: [DocumentSnippet] = []
    @State private var previewError: String?
    @State private var isPreviewLoading = false
    @State private var showTools = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow
            placeholderBanner
            actionRow
            if showTools { toolsList }
            if !memSnippets.isEmpty || !docSnippets.isEmpty || previewError != nil {
                previewSection
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.gray.opacity(0.08))
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .task { await session.ensureStarted() }
    }

    // MARK: - Status

    private var statusRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text("MemPalace · \(session.status.label)")
                .font(.subheadline.weight(.medium))
            Spacer()
            switch session.status {
            case .stopped, .failed:
                Button("Start") {
                    Task { await session.ensureStarted() }
                }
                .controlSize(.small)
            case .starting:
                ProgressView().controlSize(.small)
            case .ready:
                Button("Stop") {
                    Task { await session.stop() }
                }
                .controlSize(.small)
            }
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .stopped:    return .gray
        case .starting:   return .yellow
        case .ready:      return .green
        case .failed:     return .red
        }
    }

    // MARK: - Placeholder banner

    private var placeholderBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Agent tool-use lands in Phase F2. Send still behaves like Chat.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                Task { await runPreview() }
            } label: {
                if isPreviewLoading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Previewing…")
                    }
                } else {
                    Text("Preview Retrieval")
                }
            }
            .disabled(isPreviewLoading || viewModel.composerText.isEmpty)
            .controlSize(.small)

            Button("Test Approval") {
                session.prompter.presentTestPrompt()
            }
            .controlSize(.small)

            Spacer()

            Button(showTools ? "Hide Tools (\(session.tools.count))"
                              : "Show Tools (\(session.tools.count))") {
                showTools.toggle()
            }
            .controlSize(.small)
            .disabled(session.tools.isEmpty)
        }
    }

    // MARK: - Tools

    private var toolsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(session.tools) { tool in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                    Text(tool.name)
                        .font(.system(.caption, design: .monospaced))
                    if let desc = tool.description, !desc.isEmpty {
                        Text("— \(desc)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewSection: some View {
        Divider()
        if let err = previewError {
            Text(err)
                .font(.caption)
                .foregroundStyle(.red)
        }
        if !memSnippets.isEmpty {
            Text("Memory (\(memSnippets.count))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(memSnippets.enumerated()), id: \.offset) { _, snip in
                snippetRow(text: snip.text, label: snip.source)
            }
        }
        if !docSnippets.isEmpty {
            Text("Documents (\(docSnippets.count))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(docSnippets.enumerated()), id: \.offset) { _, snip in
                snippetRow(text: snip.text, label: snip.documentTitle)
            }
        }
    }

    private func snippetRow(text: String, label: String?) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if let label, !label.isEmpty {
                Text("[\(label)]")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(.caption)
                .lineLimit(3)
        }
    }

    @MainActor
    private func runPreview() async {
        isPreviewLoading = true
        previewError = nil
        memSnippets = []
        docSnippets = []
        defer { isPreviewLoading = false }

        await session.ensureStarted()
        let query = viewModel.composerText
        let mem = session.memoryRetriever
        let docs = session.documentRetriever
        do {
            async let m = mem.retrieve(query: query, limit: 5)
            async let d = docs.retrieve(query: query, limit: 5)
            memSnippets = try await m
            docSnippets = try await d
        } catch {
            previewError = error.localizedDescription
        }
    }
}
