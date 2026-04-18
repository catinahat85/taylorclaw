import Foundation
import Observation

/// State container for the Memory Browser window.
///
/// Drives the sidebar (wings + rooms), the drawer list, and the
/// add/delete flows. All MCP traffic goes through `AgentSession` so the
/// safety guard + approval sheet are consistent with agent-mode chat.
@MainActor
@Observable
final class MemoryBrowserViewModel {
    enum Mode: Sendable, Equatable {
        case browsing
        case searching(query: String)
    }

    private(set) var status: MemoryStatus = .empty
    private(set) var wings: [MemoryWing] = []
    private(set) var rooms: [MemoryRoom] = []
    private(set) var drawers: [MemoryDrawer] = []
    private(set) var mode: Mode = .browsing

    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    var searchQuery: String = ""
    var selectedWing: MemoryWing? {
        didSet {
            guard oldValue != selectedWing else { return }
            selectedRoom = nil
            drawers = []
            Task { await self.loadRooms() }
        }
    }
    var selectedRoom: MemoryRoom? {
        didSet {
            guard oldValue != selectedRoom else { return }
            Task { await self.loadDrawers() }
        }
    }

    // Add-drawer sheet state.
    var isAddDrawerSheetPresented: Bool = false
    var newDrawerWing: String = ""
    var newDrawerRoom: String = ""
    var newDrawerContent: String = ""

    private let session: AgentSession

    init(session: AgentSession = .shared) {
        self.session = session
    }

    // MARK: - Lifecycle

    func start() async {
        await session.ensureStarted()
        await refresh()
    }

    func refresh() async {
        await withService { service in
            async let s = service.status()
            async let w = service.listWings()
            self.status = (try? await s) ?? .empty
            self.wings  = (try? await w) ?? []
            if self.selectedWing == nil, let first = self.wings.first {
                self.selectedWing = first
            } else if let current = self.selectedWing,
                      let updated = self.wings.first(where: { $0.name == current.name }) {
                self.selectedWing = updated
            }
        }
    }

    // MARK: - Loading paths

    func loadRooms() async {
        guard let wing = selectedWing else {
            rooms = []
            drawers = []
            return
        }
        await withService { service in
            self.rooms = (try? await service.listRooms(in: wing.name)) ?? []
        }
    }

    /// Load drawers for the current selection by doing a broad search
    /// filtered by wing/room. MemPalace has no plain "list drawers" API —
    /// search with an empty-ish query is the closest thing.
    func loadDrawers() async {
        guard let wing = selectedWing else {
            drawers = []
            return
        }
        await withService { service in
            let result = try await service.search(
                query: " ",
                wing: wing.name,
                room: self.selectedRoom?.name,
                limit: 100
            )
            self.drawers = result.drawers
        }
    }

    func runSearch() async {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            mode = .browsing
            await loadDrawers()
            return
        }
        await withService { service in
            let result = try await service.search(
                query: trimmed,
                wing: self.selectedWing?.name,
                room: self.selectedRoom?.name,
                limit: 50
            )
            self.drawers = result.drawers
            self.mode = .searching(query: trimmed)
        }
    }

    // MARK: - Writes

    func presentAddDrawer() {
        newDrawerWing = selectedWing?.name ?? ""
        newDrawerRoom = selectedRoom?.name ?? ""
        newDrawerContent = ""
        isAddDrawerSheetPresented = true
    }

    func confirmAddDrawer() async {
        let wing    = newDrawerWing.trimmingCharacters(in: .whitespacesAndNewlines)
        let room    = newDrawerRoom.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = newDrawerContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wing.isEmpty, !room.isEmpty, !content.isEmpty else {
            errorMessage = "Wing, room, and content are required."
            return
        }
        await withService { service in
            _ = try await service.addDrawer(wing: wing, room: room, content: content)
            self.isAddDrawerSheetPresented = false
            self.newDrawerContent = ""
        }
        await refresh()
        await loadRooms()
        await loadDrawers()
    }

    func clearError() {
        errorMessage = nil
    }

    func deleteDrawer(_ drawer: MemoryDrawer) async {
        await withService { service in
            try await service.deleteDrawer(id: drawer.drawerID)
            self.drawers.removeAll { $0.drawerID == drawer.drawerID }
        }
        await refresh()
    }

    // MARK: - Private

    private func withService(_ work: (MemoryService) async throws -> Void) async {
        guard let service = session.makeMemoryService() else {
            errorMessage = serviceUnavailableMessage
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await work(service)
        } catch let error as SafetyError {
            switch error {
            case .denied:                errorMessage = "The tool call was denied."
            case .blocked(let t):        errorMessage = "'\(t)' is blocked by policy."
            case .loopLimitExceeded:     errorMessage = "Too many tool calls — try again later."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var serviceUnavailableMessage: String {
        switch session.status {
        case .ready:          return "Memory service unavailable."
        case .starting:       return "MemPalace is still starting…"
        case .stopped:        return "MemPalace is stopped. Start it from the Agent panel."
        case .failed(let m):  return "MemPalace failed to start: \(m)"
        }
    }
}
