import SwiftUI

/// Collapsible block showing a single tool invocation: the call (name +
/// pretty-printed input) and, when present, the result text.
struct ToolCallView: View {
    let call: ToolCall

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                Divider()
                detail
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.12)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                Text(call.name)
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 8) {
            section(label: "Input", text: prettyJSON(call.input))
            if let result = call.result {
                section(
                    label: call.isError ? "Error" : "Result",
                    text: result,
                    isError: call.isError
                )
            } else {
                Text("Running…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private func section(label: String, text: String, isError: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(isError ? Color.red : Color.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
        }
    }

    private var statusIcon: String {
        if call.result == nil { return "wrench.and.screwdriver" }
        return call.isError ? "exclamationmark.triangle.fill" : "checkmark.seal.fill"
    }

    private var statusColor: Color {
        if call.result == nil { return .secondary }
        return call.isError ? .red : .green
    }

    private var statusText: String {
        if call.result == nil { return "Running…" }
        return call.isError ? "Failed" : "Done"
    }

    private var borderColor: Color {
        call.isError ? Color.red.opacity(0.4) : Color(nsColor: .separatorColor)
    }

    private func prettyJSON(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "{}"
    }
}
