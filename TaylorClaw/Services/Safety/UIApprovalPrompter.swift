import Foundation
import Observation

/// SwiftUI-driven approval prompter.
///
/// Conforms to `ApprovalPrompter` so it can be plugged into `AgentGuard`,
/// but bridges across actors: `request(_:)` is called from any context, and
/// resumes only after the UI calls `resolve(_:)` on the main actor.
///
/// `pending` is published so a SwiftUI sheet can observe it via
/// `@Bindable` and present whenever non-nil.
@MainActor
@Observable
final class UIApprovalPrompter: ApprovalPrompter {
    /// The request currently awaiting user input. `nil` means no sheet.
    private(set) var pending: ApprovalRequest?

    private var continuation: CheckedContinuation<ApprovalDecision, Never>?

    init() {}

    // MARK: - ApprovalPrompter

    nonisolated func request(_ request: ApprovalRequest) async -> ApprovalDecision {
        await withCheckedContinuation { (cont: CheckedContinuation<ApprovalDecision, Never>) in
            Task { @MainActor in
                self.beginPrompt(request, continuation: cont)
            }
        }
    }

    // MARK: - UI bindings

    /// Called by the sheet's buttons. Resolves the in-flight `request`.
    func resolve(_ decision: ApprovalDecision) {
        guard let cont = continuation else { return }
        continuation = nil
        pending = nil
        cont.resume(returning: decision)
    }

    /// Treats sheet dismissal as a denial.
    func dismiss() {
        resolve(.deny)
    }

    // MARK: - Test helpers

    /// Manually trigger a prompt for the "Test approval" button in the
    /// agent panel. Returns immediately — the resolved decision is
    /// surfaced to the caller via the supplied closure.
    func presentTestPrompt(
        toolName: String = "test_tool",
        serverName: String = "preview",
        risk: ToolRisk = .caution
    ) {
        let req = ApprovalRequest(
            toolName: toolName,
            serverName: serverName,
            arguments: .object(["preview": .bool(true)]),
            risk: risk,
            reason: "Triggered by Test Approval button."
        )
        // Drop any currently in-flight prompt.
        if let cont = continuation {
            continuation = nil
            cont.resume(returning: .deny)
        }
        pending = req
    }

    // MARK: - Private

    private func beginPrompt(
        _ request: ApprovalRequest,
        continuation cont: CheckedContinuation<ApprovalDecision, Never>
    ) {
        // If a previous prompt is somehow still pending, deny it so we
        // never leak a continuation.
        if let stale = self.continuation {
            self.continuation = nil
            stale.resume(returning: .deny)
        }
        self.pending = request
        self.continuation = cont
    }
}
