import Foundation
import Combine

class SessionManager: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var pendingActions: [PendingAction] = []

    private let staleTimeout: TimeInterval = 30 * 60  // 30 minutes

    func handleEvent(_ event: BobberEvent) {
        if let index = sessions.firstIndex(where: { $0.id == event.sessionId }) {
            sessions[index].handleEvent(type: event.eventType)
            sessions[index].terminal = event.terminal ?? sessions[index].terminal
            sessions[index].pid = event.pid
            if let tool = event.details?.tool {
                sessions[index].lastTool = tool
                sessions[index].lastToolSummary = toolSummary(from: event.details)
            }
        } else {
            var session = Session(
                id: event.sessionId,
                projectName: event.projectName,
                projectPath: event.projectPath,
                sessionTitle: event.sessionTitle
            )
            session.handleEvent(type: event.eventType)
            session.terminal = event.terminal
            session.pid = event.pid
            sessions.append(session)
        }

        // Create pending action for blocking events
        switch event.eventType {
        case .permissionPrompt:
            let action = PendingAction(
                id: UUID().uuidString,
                sessionId: event.sessionId,
                type: .permission,
                timestamp: event.timestamp,
                tool: event.details?.tool,
                command: event.details?.command,
                description: event.details?.description,
                question: nil,
                options: event.details?.options
            )
            pendingActions.append(action)

        case .elicitationDialog:
            let action = PendingAction(
                id: UUID().uuidString,
                sessionId: event.sessionId,
                type: .decision,
                timestamp: event.timestamp,
                tool: nil,
                command: nil,
                description: nil,
                question: event.details?.question,
                options: event.details?.options
            )
            pendingActions.append(action)

        case .idlePrompt, .taskCompleted:
            let action = PendingAction(
                id: UUID().uuidString,
                sessionId: event.sessionId,
                type: .completion,
                timestamp: event.timestamp,
                tool: event.details?.tool,
                command: nil,
                description: event.details?.message,
                question: nil,
                options: nil
            )
            pendingActions.append(action)

        case .preToolUse, .userPromptSubmit, .sessionStart:
            // Clear pending actions for this session (user/agent resumed)
            pendingActions.removeAll { $0.sessionId == event.sessionId }

        default:
            break
        }
    }

    func resolveAction(_ actionId: String) {
        pendingActions.removeAll { $0.id == actionId }
    }

    func cleanupSessions() {
        let now = Date()
        for i in sessions.indices {
            guard sessions[i].state != .completed else { continue }

            // Stale timeout check (evaluated before PID liveness)
            if now.timeIntervalSince(sessions[i].lastEvent) > staleTimeout {
                sessions[i].state = .stale
                continue
            }

            // PID liveness check
            if let pid = sessions[i].pid, kill(pid, 0) != 0 {
                sessions[i].state = .completed
            }
        }
        // Remove sessions that have been completed for >5 minutes
        sessions.removeAll { session in
            session.state == .completed
                && now.timeIntervalSince(session.lastEvent) > 300
        }
    }

    private func toolSummary(from details: EventDetails?) -> String? {
        guard let details else { return nil }
        switch details.tool {
        case "Bash":
            return "$ \(details.command?.prefix(60) ?? "")"
        case "Edit", "Read", "Write":
            return details.command ?? details.description
        case "Grep", "Glob":
            if let desc = details.description {
                return String(desc.prefix(40))
            }
            return details.tool
        default:
            return details.tool
        }
    }
}
