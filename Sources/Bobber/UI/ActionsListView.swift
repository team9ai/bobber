import SwiftUI

struct ActionsListView: View {
    @ObservedObject var sessionManager: SessionManager
    var onPermissionDecision: ((String, PermissionDecision) -> Void)?
    @State private var currentIndex: Int = 0

    var body: some View {
        if sessionManager.pendingActions.isEmpty {
            VStack(spacing: 8) {
                Text("No pending actions")
                    .foregroundColor(.secondary)
                Text("All clear!")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                HStack {
                    let action = sessionManager.pendingActions[safeIndex]
                    let session = sessionManager.sessions.first { $0.id == action.sessionId }
                    VStack(alignment: .leading) {
                        Text(session?.projectName ?? "Unknown")
                            .font(.headline)
                        if let title = session?.sessionTitle {
                            Text(title)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        Button(action: { navigate(-1) }) {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.plain)
                        .disabled(sessionManager.pendingActions.count <= 1)
                        Text("\(safeIndex + 1)/\(sessionManager.pendingActions.count)")
                            .font(.caption)
                            .monospacedDigit()
                        Button(action: { navigate(1) }) {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.plain)
                        .disabled(sessionManager.pendingActions.count <= 1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                let action = sessionManager.pendingActions[safeIndex]
                switch action.type {
                case .permission:
                    PermissionCardView(action: action) { decision in
                        onPermissionDecision?(action.sessionId, decision)
                        sessionManager.resolveAction(action.id)
                    }
                case .decision:
                    DecisionCardView(action: action) { choice in
                        // For elicitation dialogs, send the choice as a custom message
                        onPermissionDecision?(action.sessionId, .custom(choice))
                        sessionManager.resolveAction(action.id)
                    }
                case .completion:
                    CompletionCardView(action: action) {
                        sessionManager.resolveAction(action.id)
                    }
                }

                Spacer()
            }
        }
    }

    private var safeIndex: Int {
        min(currentIndex, max(0, sessionManager.pendingActions.count - 1))
    }

    private func navigate(_ delta: Int) {
        let count = sessionManager.pendingActions.count
        guard count > 0 else { return }
        currentIndex = (currentIndex + delta + count) % count
    }
}
