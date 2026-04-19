import SwiftUI

/// Modal sheet that presents a pending `ApprovalRequest` and lets the user
/// allow or deny a tool call. Dismissal counts as denial.
struct ApprovalSheet: View {
    let request: ApprovalRequest
    let onDecide: (ApprovalDecision) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            argumentsBlock
            if let reason = request.reason, !reason.isEmpty {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            buttonRow
        }
        .padding(20)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 320)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: riskIcon)
                .font(.title)
                .foregroundStyle(riskTint)
            VStack(alignment: .leading, spacing: 4) {
                Text(request.toolName)
                    .font(.title3.weight(.semibold))
                Text("\(request.serverName) · \(request.risk.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var argumentsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Arguments")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(prettyArgs)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 140)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.gray.opacity(0.12))
            )
        }
    }

    private var buttonRow: some View {
        HStack(spacing: 10) {
            Button("Deny", role: .destructive) {
                resolve(.deny)
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if request.risk != .destructive {
                Button("Allow For Session") {
                    resolve(.allowForSession)
                }
            }
            Button("Allow Once") {
                resolve(.allowOnce)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
    }

    private func resolve(_ decision: ApprovalDecision) {
        onDecide(decision)
        dismiss()
    }

    private var prettyArgs: String {
        guard let data = try? JSONEncoder.pretty.encode(request.arguments),
              let s = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return s
    }

    private var riskIcon: String {
        switch request.risk {
        case .safe:        return "checkmark.shield"
        case .caution:     return "exclamationmark.triangle"
        case .destructive: return "flame"
        case .blocked:     return "nosign"
        }
    }

    private var riskTint: Color {
        switch request.risk {
        case .safe:        return .green
        case .caution:     return .orange
        case .destructive: return .red
        case .blocked:     return .gray
        }
    }
}

private extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}
