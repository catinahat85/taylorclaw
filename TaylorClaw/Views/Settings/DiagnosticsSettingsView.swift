import SwiftUI

/// Read-only snapshot of app state — paths, key presence, MemPalace status,
/// store counts, recent audit entries. The "Copy report" button produces a
/// plain-text dump suitable for pasting into a bug report.
struct DiagnosticsSettingsView: View {
    @State private var viewModel = DiagnosticsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                appSection
                runtimeSection
                keysSection
                storesSection
                auditSection
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await viewModel.refresh() }
    }

    private var header: some View {
        HStack {
            Text("Diagnostics")
                .font(.title2.weight(.semibold))
            Spacer()
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isRefreshing)

            Button {
                viewModel.copyReport()
            } label: {
                Label(viewModel.didCopy ? "Copied" : "Copy report",
                      systemImage: viewModel.didCopy ? "checkmark" : "doc.on.doc")
            }
        }
    }

    private var appSection: some View {
        section(title: "App") {
            row("Version", "\(viewModel.snapshot.appVersion) (build \(viewModel.snapshot.buildNumber))")
            row("Bundle ID", viewModel.snapshot.bundleID, monospaced: true)
            row("Default model", viewModel.snapshot.defaultModel)
            row("Default chat mode", viewModel.snapshot.defaultChatMode)
        }
    }

    private var runtimeSection: some View {
        section(title: "Runtime & MemPalace") {
            statusRow("Python runtime installed", viewModel.snapshot.runtimeInstalled)
            statusRow("MemPalace running", viewModel.snapshot.mempalaceRunning)
            row("Tools exposed", "\(viewModel.snapshot.toolCount)")
            if !viewModel.snapshot.toolNames.isEmpty {
                row("Tool names",
                    viewModel.snapshot.toolNames.joined(separator: ", "),
                    monospaced: true)
            }
            row("venv python", viewModel.snapshot.venvPythonPath, monospaced: true)
            row("App Support", viewModel.snapshot.appSupportPath, monospaced: true)
        }
    }

    private var keysSection: some View {
        section(title: "API Keys") {
            ForEach(viewModel.snapshot.keyStatus) { status in
                statusRow(status.provider.displayName, status.hasKey)
            }
        }
    }

    private var storesSection: some View {
        section(title: "Stores") {
            row("Conversations", "\(viewModel.snapshot.conversationCount)")
            row("Documents", "\(viewModel.snapshot.documentCount)")
            row("conversations.json", viewModel.snapshot.conversationsPath, monospaced: true)
            row("documents.json", viewModel.snapshot.documentsPath, monospaced: true)
            row("audit.jsonl", viewModel.snapshot.auditLogPath, monospaced: true)
            if let err = viewModel.snapshot.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var auditSection: some View {
        section(title: "Recent Audit (newest first)") {
            if viewModel.snapshot.recentAudit.isEmpty {
                Text("No tool calls recorded yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(viewModel.snapshot.recentAudit.enumerated()), id: \.offset) { _, entry in
                        auditRow(entry)
                    }
                }
            }
        }
    }

    private func auditRow(_ entry: AuditEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.shortTime(entry.timestamp))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text("\(entry.serverName)/\(entry.toolName)")
                .font(.system(.caption2, design: .monospaced))
                .frame(minWidth: 160, alignment: .leading)
            Text(entry.outcome.rawValue)
                .font(.caption2)
                .foregroundStyle(outcomeColor(entry.outcome))
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                content()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    private func row(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statusRow(_ label: String, _ ok: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Label(ok ? "Yes" : "No",
                  systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(ok ? .green : .secondary)
            Spacer(minLength: 0)
        }
    }

    private func outcomeColor(_ outcome: AuditEntry.Outcome) -> Color {
        switch outcome {
        case .autoApproved, .sessionApproved, .userApproved, .toolSuccess:
            return .green
        case .toolError, .userDenied, .blocked, .loopLimit:
            return .red
        }
    }

    private static func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}
