import SwiftUI

struct SessionsListView: View {
    @ObservedObject var sessionManager: SessionManager

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(sessionManager.sessions) { session in
                    SessionRowView(session: session)
                }
            }
            .padding(8)
        }
    }
}

struct SessionRowView: View {
    let session: Session

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(session.state.color)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.projectName)
                    .font(.system(.body, design: .rounded, weight: .medium))
                Text(session.statusDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(session.lastEvent.relativeDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

extension SessionState {
    var color: Color {
        switch self {
        case .active: return .green
        case .blocked: return .red
        case .idle: return .yellow
        case .completed: return .gray
        case .stale: return .gray.opacity(0.5)
        }
    }
}

extension Session {
    var statusDescription: String {
        switch state {
        case .active:
            return lastToolSummary ?? "Working..."
        case .blocked:
            if let tool = pendingAction?.tool {
                return "Pending permission: \(tool)"
            }
            return "Waiting for input"
        case .idle:
            return "Idle"
        case .completed:
            return "Done"
        case .stale:
            return "Stale"
        }
    }
}

extension Date {
    var relativeDescription: String {
        let interval = -self.timeIntervalSinceNow
        if interval < 5 { return "now" }
        if interval < 60 { return "\(Int(interval))s" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        return "\(Int(interval / 3600))h"
    }
}
