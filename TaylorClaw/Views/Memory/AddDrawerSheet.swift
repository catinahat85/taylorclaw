import SwiftUI

struct AddDrawerSheet: View {
    @Bindable var viewModel: MemoryBrowserViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Drawer")
                .font(.title3.weight(.semibold))
            Form {
                TextField("Wing", text: $viewModel.newDrawerWing)
                TextField("Room", text: $viewModel.newDrawerRoom)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Content")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $viewModel.newDrawerContent)
                        .font(.body)
                        .frame(minHeight: 160)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3))
                        )
                }
            }
            Text("Adding a drawer routes through the safety guard — you'll be asked to approve the write.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    viewModel.isAddDrawerSheetPresented = false
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Add") {
                    Task { await viewModel.confirmAddDrawer() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isAddDisabled)
            }
        }
        .padding(20)
        .frame(minWidth: 480, idealWidth: 540)
    }

    private var isAddDisabled: Bool {
        viewModel.newDrawerWing.trimmingCharacters(in: .whitespaces).isEmpty
            || viewModel.newDrawerRoom.trimmingCharacters(in: .whitespaces).isEmpty
            || viewModel.newDrawerContent.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
