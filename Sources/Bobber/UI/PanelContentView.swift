import SwiftUI

struct PanelContentView: View {
    @ObservedObject var sessionManager: SessionManager
    var onPermissionDecision: ((String, PermissionDecision) -> Void)?
    var onJumpToSession: ((Session) -> Void)?
    var onHide: (() -> Void)?
    var onSettings: (() -> Void)?
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
                    Button(action: { onSettings?() }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
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
                        },
                        onJumpToSession: onJumpToSession
                    )
                }
            case .actions:
                ActionsListView(
                    sessionManager: sessionManager,
                    onPermissionDecision: onPermissionDecision
                )
            }
        }
        .frame(minWidth: 280, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct CloseButton: View {
    let action: () -> Void
    @State private var isHovering = false
    @State private var isWindowKey = false

    private var fillColor: Color {
        if isHovering { return Color(nsColor: NSColor(red: 1.0, green: 0.38, blue: 0.34, alpha: 1.0)) }
        if isWindowKey { return Color(nsColor: NSColor(red: 1.0, green: 0.38, blue: 0.34, alpha: 1.0)) }
        return Color.gray.opacity(0.3)
    }

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(fillColor)
                .frame(width: 12, height: 12)
                .overlay(
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(isHovering ? Color(nsColor: NSColor(red: 0.45, green: 0.08, blue: 0.06, alpha: 1.0)) : .clear)
                )
        }
        .buttonStyle(.plain)
        .background(ActiveHoverTracker(onHover: { isHovering = $0 }))
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            isWindowKey = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            isWindowKey = false
        }
    }
}

/// NSTrackingArea-based hover that works on .nonactivatingPanel (uses .activeAlways)
struct ActiveHoverTracker: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> HoverTrackingNSView {
        HoverTrackingNSView(onHover: onHover)
    }

    func updateNSView(_ nsView: HoverTrackingNSView, context: Context) {}

    class HoverTrackingNSView: NSView {
        let onHover: (Bool) -> Void

        init(onHover: @escaping (Bool) -> Void) {
            self.onHover = onHover
            super.init(frame: .zero)
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func mouseEntered(with event: NSEvent) { onHover(true) }
        override func mouseExited(with event: NSEvent) { onHover(false) }
    }
}
