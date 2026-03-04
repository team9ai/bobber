import SwiftUI

struct PanelContentView: View {
    @ObservedObject var sessionManager: SessionManager
    var onPermissionDecision: ((String, PermissionDecision) -> Void)?
    var onJumpToSession: ((Session) -> Void)?
    var onHide: (() -> Void)?
    @State private var selectedTab: PanelTab = .sessions
    @State private var selectedSessionId: String?

    enum PanelTab {
        case sessions, actions
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Picker("", selection: $selectedTab) {
                    Text("Sessions").tag(PanelTab.sessions)
                    HStack(spacing: 4) {
                        Text("Actions")
                        if sessionManager.pendingActions.count > 0 {
                            Text("\(sessionManager.pendingActions.count)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(.red))
                        }
                    }.tag(PanelTab.actions)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                HStack {
                    CloseButton(action: { onHide?() })
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 10)

            Divider()

            switch selectedTab {
            case .sessions:
                if let sessionId = selectedSessionId,
                   let session = sessionManager.sessions.first(where: { $0.id == sessionId }) {
                    SessionDetailView(
                        session: session,
                        sessionManager: sessionManager,
                        onBack: { selectedSessionId = nil },
                        onJumpToSession: onJumpToSession
                    )
                } else {
                    SessionsListView(
                        sessionManager: sessionManager,
                        onSelectSession: { id in
                            sessionManager.acknowledgeSession(id)
                            selectedSessionId = id
                        }
                    )
                }
            case .actions:
                ActionsListView(
                    sessionManager: sessionManager,
                    onPermissionDecision: onPermissionDecision
                )
            }
        }
        .frame(minWidth: 340, maxWidth: 340, minHeight: 200, maxHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct CloseButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(isHovering ? Color.red : Color.primary.opacity(0.15))
                .frame(width: 12, height: 12)
                .overlay(
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(isHovering ? .white : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
