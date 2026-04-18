import SwiftUI

struct MemoryBrowserView: View {
    @Bindable var viewModel: MemoryBrowserViewModel
    private let agent = AgentSession.shared

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .task { await viewModel.start() }
        .sheet(isPresented: $viewModel.isAddDrawerSheetPresented) {
            AddDrawerSheet(viewModel: viewModel)
        }
        .sheet(item: Binding(
            get: { agent.prompter.pending },
            set: { newValue in
                if newValue == nil { agent.prompter.dismiss() }
            }
        )) { request in
            ApprovalSheet(request: request) { decision in
                agent.prompter.resolve(decision)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusHeader
            Divider()
            List(selection: $viewModel.selectedWing) {
                Section("Wings") {
                    ForEach(viewModel.wings) { wing in
                        HStack {
                            Image(systemName: "tray.2")
                            Text(wing.name)
                            Spacer()
                            Text("\(wing.drawerCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(Optional(wing))
                    }
                }
                if !viewModel.rooms.isEmpty {
                    Section("Rooms · \(viewModel.selectedWing?.name ?? "")") {
                        ForEach(viewModel.rooms) { room in
                            Button {
                                viewModel.selectedRoom =
                                    (viewModel.selectedRoom == room) ? nil : room
                            } label: {
                                HStack {
                                    Image(systemName: "archivebox")
                                        .foregroundStyle(
                                            viewModel.selectedRoom == room
                                                ? Color.accentColor : .secondary
                                        )
                                    Text(room.name)
                                    Spacer()
                                    Text("\(room.drawerCount)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("MemPalace")
                .font(.headline)
            Text("\(viewModel.status.totalDrawers) drawers · \(viewModel.status.wingCount) wings · \(viewModel.status.roomCount) rooms")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailToolbar
            Divider()
            if let error = viewModel.errorMessage {
                ErrorBanner(
                    message: error,
                    onRetry: nil,
                    onDismiss: { viewModel.clearError() }
                )
                .padding(.bottom, 4)
            }
            if viewModel.drawers.isEmpty && !viewModel.isLoading {
                EmptyStateView(
                    title: emptyTitle,
                    subtitle: emptySubtitle
                )
            } else {
                drawerList
            }
        }
    }

    private var detailToolbar: some View {
        HStack(spacing: 10) {
            TextField("Search memories…", text: $viewModel.searchQuery)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await viewModel.runSearch() } }
            Button("Search") {
                Task { await viewModel.runSearch() }
            }
            .disabled(viewModel.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Refresh") {
                Task { await viewModel.refresh() }
            }
            Button {
                viewModel.presentAddDrawer()
            } label: {
                Label("Add Drawer", systemImage: "plus")
            }
            if viewModel.isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(12)
    }

    private var drawerList: some View {
        List {
            ForEach(viewModel.drawers) { drawer in
                DrawerRow(drawer: drawer) {
                    Task { await viewModel.deleteDrawer(drawer) }
                }
            }
        }
        .listStyle(.inset)
    }

    private var emptyTitle: String {
        switch viewModel.mode {
        case .browsing:           return "No drawers yet"
        case .searching(let q):   return "No results for \u{201C}\(q)\u{201D}"
        }
    }

    private var emptySubtitle: String {
        switch viewModel.mode {
        case .browsing:
            return "Pick a wing on the left or add a new drawer."
        case .searching:
            return "Try a different query, or narrow the wing/room filter."
        }
    }
}

private struct DrawerRow: View {
    let drawer: MemoryDrawer
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(drawer.wing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text(drawer.room)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let score = drawer.score {
                    Text(String(format: "%.2f", score))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete drawer")
            }
            Text(drawer.preview)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}

