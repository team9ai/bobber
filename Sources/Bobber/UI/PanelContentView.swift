import SwiftUI

struct PanelContentView: View {
    @ObservedObject var sessionManager: SessionManager
    var onPermissionDecision: ((String, PermissionDecision) -> Void)?
    @State private var selectedTab: PanelTab = .sessions

    enum PanelTab {
        case sessions, actions
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TabButton(title: "Sessions", isSelected: selectedTab == .sessions) {
                    selectedTab = .sessions
                }
                TabButton(
                    title: "Actions",
                    badge: sessionManager.pendingActions.count,
                    isSelected: selectedTab == .actions
                ) {
                    selectedTab = .actions
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            switch selectedTab {
            case .sessions:
                SessionsListView(sessionManager: sessionManager)
            case .actions:
                ActionsListView(
                    sessionManager: sessionManager,
                    onPermissionDecision: onPermissionDecision
                )
            }
        }
        .frame(minWidth: 340, maxWidth: 340, minHeight: 200, maxHeight: 600)
    }
}

struct TabButton: View {
    let title: String
    var badge: Int = 0
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .fontWeight(isSelected ? .semibold : .regular)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.red))
                }
            }
            .foregroundColor(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
