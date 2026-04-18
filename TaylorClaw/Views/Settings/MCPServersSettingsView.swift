import SwiftUI

struct MCPServersSettingsView: View {
    @State private var session = AgentSession.shared
    @State private var editorTarget: EditorTarget?

    enum EditorTarget: Identifiable {
        case create(MCPServerConfig)
        case edit(oldName: String, config: MCPServerConfig)

        var id: String {
            switch self {
            case .create(let c):     return "new:\(c.name)"
            case .edit(let n, _):    return "edit:\(n)"
            }
        }
    }

    var body: some View {
        Form {
            Section {
                Text("Taylor Claw speaks MCP over stdio. Add any server you can launch from the command line — the binary must already be on PATH. Presets are templates, not bundled runtimes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Configured Servers") {
                if session.userServers.isEmpty {
                    Text("No servers configured yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.userServers) { entry in
                        serverRow(entry)
                    }
                }
            }

            Section {
                HStack {
                    Menu("Add from Preset") {
                        ForEach(MCPServerPreset.catalog) { preset in
                            Button(preset.title) { addFromPreset(preset) }
                        }
                    }
                    Button("Add Custom…") {
                        editorTarget = .create(emptyConfig())
                    }
                    Spacer()
                    Button("Refresh") {
                        Task { await session.reconcileUserServers() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { await session.reconcileUserServers() }
        .sheet(item: $editorTarget) { target in
            MCPServerEditorSheet(
                target: target,
                existingNames: Set(session.userServers.map(\.config.name))
            ) { saved in
                Task {
                    switch target {
                    case .create:
                        await session.addUserServer(saved)
                    case .edit(let oldName, _):
                        await session.updateUserServer(oldName: oldName, to: saved)
                    }
                }
                editorTarget = nil
            } onCancel: {
                editorTarget = nil
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func serverRow(_ entry: AgentSession.UserServer) -> some View {
        HStack(alignment: .top, spacing: 12) {
            StateDot(state: entry.state)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.config.name).font(.headline)
                    Spacer()
                    stateLabel(entry.state)
                }
                Text("\(entry.config.command) \(entry.config.args.joined(separator: " "))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !entry.tools.isEmpty {
                    Text("\(entry.tools.count) tool\(entry.tools.count == 1 ? "" : "s"): "
                         + entry.tools.prefix(6).map(\.name).joined(separator: ", ")
                         + (entry.tools.count > 6 ? "…" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    if entry.state == .ready {
                        Button("Stop") {
                            Task { await session.stopUserServer(named: entry.config.name) }
                        }
                    } else if case .starting = entry.state {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Start") {
                            Task { await session.startUserServer(named: entry.config.name) }
                        }
                    }
                    Button("Edit") {
                        editorTarget = .edit(oldName: entry.config.name, config: entry.config)
                    }
                    Button(role: .destructive) {
                        Task { await session.deleteUserServer(named: entry.config.name) }
                    } label: {
                        Text("Remove")
                    }
                }
                .buttonStyle(.link)
            }
        }
        .padding(.vertical, 4)
    }

    private func stateLabel(_ state: AgentSession.ServerState) -> some View {
        switch state {
        case .stopped:              return Text("Stopped").foregroundStyle(.secondary).font(.caption)
        case .starting:             return Text("Starting…").foregroundStyle(.secondary).font(.caption)
        case .ready:                return Text("Ready").foregroundStyle(.green).font(.caption)
        case .failed(let msg):      return Text("Failed: \(msg)").foregroundStyle(.red).font(.caption)
        }
    }

    // MARK: - Actions

    private func addFromPreset(_ preset: MCPServerPreset) {
        var env: [String: String] = [:]
        for e in preset.requiredEnv { env[e.key] = "" }
        editorTarget = .create(preset.makeConfig(env: env))
    }

    private func emptyConfig() -> MCPServerConfig {
        MCPServerConfig(name: "", command: "", args: [], env: [:], cwd: nil, autoStart: true)
    }
}

// MARK: - State dot

private struct StateDot: View {
    let state: AgentSession.ServerState
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
    private var color: Color {
        switch state {
        case .stopped:  return .secondary
        case .starting: return .orange
        case .ready:    return .green
        case .failed:   return .red
        }
    }
}
