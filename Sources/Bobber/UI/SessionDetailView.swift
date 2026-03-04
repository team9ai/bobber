import SwiftUI
import AppKit

struct SessionDetailView: View {
    let session: Session
    @ObservedObject var sessionManager: SessionManager
    let onBack: () -> Void
    var onJumpToSession: ((Session) -> Void)?

    @State private var selectedTab: DetailTab = .status
    @State private var showRenameAlert = false
    @State private var nicknameInput = ""

    enum DetailTab {
        case status, activity
    }

    private var displayName: String {
        sessionManager.sessionNicknames[session.id] ?? session.displayTitle
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: back + title
            HStack {
                Button {
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(displayName)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .lineLimit(1)

                Spacer()

                // Invisible spacer to balance back button width
                Color.clear.frame(width: 44, height: 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("Status").tag(DetailTab.status)
                Text("Activity").tag(DetailTab.activity)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // Content
            switch selectedTab {
            case .status:
                statusTab
            case .activity:
                activityTab
            }
        }
    }

    // MARK: - Status Tab

    private var statusTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // State
                HStack(spacing: 8) {
                    Circle()
                        .fill(session.state.color)
                        .frame(width: 10, height: 10)
                    Text(session.state.label)
                        .font(.system(.body, weight: .medium))
                }

                Divider()

                // Info rows
                infoRow("Project", session.projectName)
                infoRow("Path", session.projectPath)
                if let app = session.terminal?.app {
                    infoRow("Terminal", app)
                }
                if let pid = session.pid {
                    infoRow("PID", "\(pid)")
                }
                infoRow("Last event", session.lastEvent.relativeDescription + " ago")
                if let tool = session.lastTool {
                    infoRow("Last tool", tool)
                }

                Divider()

                // Quick actions
                Text("Quick Actions")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                HStack(spacing: 8) {
                    actionButton("Terminal", icon: "terminal") {
                        onJumpToSession?(session)
                    }
                    actionButton("Rename", icon: "pencil") {
                        nicknameInput = sessionManager.sessionNicknames[session.id] ?? ""
                        showRenameAlert = true
                    }
                    actionButton("Hide", icon: "eye.slash") {
                        sessionManager.hideSession(session.id)
                        onBack()
                    }
                    actionButton("Copy ID", icon: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(session.id, forType: .string)
                    }
                }
            }
            .padding(12)
        }
        .alert("Rename Session", isPresented: $showRenameAlert) {
            TextField("Nickname", text: $nicknameInput)
            Button("OK") {
                sessionManager.renameSession(session.id, nickname: nicknameInput)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a nickname for this session")
        }
    }

    // MARK: - Activity Tab

    private var activityTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if session.recentEvents.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No recent events")
                            .foregroundColor(.secondary)
                        Text("Events will appear here\nas the session runs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    ForEach(Array(session.recentEvents.enumerated()), id: \.offset) { index, event in
                        HStack(alignment: .top, spacing: 10) {
                            // Timeline dot + line
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(Color.primary.opacity(0.3))
                                    .frame(width: 8, height: 8)
                                if index < session.recentEvents.count - 1 {
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.1))
                                        .frame(width: 1)
                                        .frame(maxHeight: .infinity)
                                }
                            }

                            // Event content
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(event.type.rawValue.replacingOccurrences(of: "_", with: " "))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(event.timestamp.relativeDescription)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                if let tool = event.tool {
                                    Text(tool)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                if let summary = event.summary, !summary.isEmpty {
                                    Text(summary)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                        .padding(.vertical, 8)

                        if index < session.recentEvents.count - 1 {
                            Divider().padding(.leading, 18)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - Helpers

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}
