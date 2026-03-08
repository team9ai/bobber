import Foundation
import Combine

class SessionManager: ObservableObject {
    @Published var sessions: [Session] = [] { didSet { saveState() } }
    @Published var pendingActions: [PendingAction] = [] { didSet { saveState() } }
    @Published var hiddenSessionIds: Set<String> = [] { didSet { saveState() } }
    @Published var sessionNicknames: [String: String] = [:] { didSet { saveState() } }
    @Published var acknowledgedSessionIds: Set<String> = [] { didSet { saveState() } }
    @Published var projectPriorityDefaults: [String: SessionPriority] = [:] { didSet { saveState() } }

    private let staleTimeout: TimeInterval = 30 * 60  // 30 minutes
    private static let blockingTools: Set<String> = [
        "AskUserQuestion", "EnterPlanMode", "AskFollowupQuestion"
    ]

    private static var stateURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bobber/state.json")
    }

    init() {
        loadState()
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: Self.stateURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(PersistedState.self, from: data) else { return }
        sessions = state.sessions
        pendingActions = state.pendingActions
        hiddenSessionIds = state.hiddenSessionIds
        sessionNicknames = state.sessionNicknames
        acknowledgedSessionIds = state.acknowledgedSessionIds
        projectPriorityDefaults = state.projectPriorityDefaults
        // Fix up sessions with blocking tools that were persisted as active
        for i in sessions.indices {
            if sessions[i].state == .active,
               let tool = sessions[i].lastTool,
               Self.blockingTools.contains(tool) {
                sessions[i].state = .blocked
            }
        }
        NSLog("[Bobber] SessionManager: restored \(sessions.count) sessions, \(pendingActions.count) actions from disk")
    }

    private func saveState() {
        let state = PersistedState(sessions: sessions, pendingActions: pendingActions, hiddenSessionIds: hiddenSessionIds, sessionNicknames: sessionNicknames, acknowledgedSessionIds: acknowledgedSessionIds, projectPriorityDefaults: projectPriorityDefaults)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: Self.stateURL, options: .atomic)
    }

    private struct PersistedState: Codable {
        let sessions: [Session]
        let pendingActions: [PendingAction]
        var hiddenSessionIds: Set<String> = []
        var sessionNicknames: [String: String] = [:]
        var acknowledgedSessionIds: Set<String> = []
        var projectPriorityDefaults: [String: SessionPriority] = [:]
    }

    func hideSession(_ sessionId: String) {
        hiddenSessionIds.insert(sessionId)
    }

    func renameSession(_ sessionId: String, nickname: String) {
        if nickname.trimmingCharacters(in: .whitespaces).isEmpty {
            sessionNicknames.removeValue(forKey: sessionId)
        } else {
            sessionNicknames[sessionId] = nickname
        }
    }

    func acknowledgeSession(_ sessionId: String) {
        acknowledgedSessionIds.insert(sessionId)
        pendingActions.removeAll { $0.sessionId == sessionId && $0.type == .completion }
    }

    func setSessionPriority(_ sessionId: String, priority: SessionPriority) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].priority = priority
    }

    func setProjectPriority(projectPath: String, priority: SessionPriority) {
        projectPriorityDefaults[projectPath] = priority
        for i in sessions.indices where sessions[i].projectPath == projectPath {
            sessions[i].priority = priority
        }
    }

    func handleEvent(_ event: BobberEvent) {
        NSLog("[Bobber] SessionManager: handling \(event.eventType.rawValue) for \(event.sessionId), tool=\(event.details?.tool ?? "nil"), current sessions: \(sessions.count)")
        // Unhide and un-acknowledge session when new event arrives
        hiddenSessionIds.remove(event.sessionId)
        acknowledgedSessionIds.remove(event.sessionId)
        if let index = sessions.firstIndex(where: { $0.id == event.sessionId }) {
            sessions[index].handleEvent(type: event.eventType)
            sessions[index].terminal = event.terminal ?? sessions[index].terminal
            sessions[index].pid = event.pid
            if let title = event.sessionTitle, !title.isEmpty {
                sessions[index].sessionTitle = title
            }
            if let tool = event.details?.tool, !tool.isEmpty {
                sessions[index].lastTool = tool
                sessions[index].lastToolSummary = event.details?.description
                // Blocking tools → mark session as blocked
                if Self.blockingTools.contains(tool) {
                    sessions[index].state = .blocked
                }
            }
            let sessionEvent = SessionEvent(
                timestamp: event.timestamp,
                type: event.eventType,
                tool: event.details?.tool,
                summary: event.details?.description ?? event.details?.command
            )
            sessions[index].recentEvents.insert(sessionEvent, at: 0)
            if sessions[index].recentEvents.count > 3 {
                sessions[index].recentEvents.removeLast()
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
            if let tool = event.details?.tool, !tool.isEmpty {
                session.lastTool = tool
                session.lastToolSummary = event.details?.description
                if Self.blockingTools.contains(tool) {
                    session.state = .blocked
                }
            }
            session.priority = projectPriorityDefaults[event.projectPath] ?? .standard
            let sessionEvent = SessionEvent(
                timestamp: event.timestamp,
                type: event.eventType,
                tool: event.details?.tool,
                summary: event.details?.description ?? event.details?.command
            )
            session.recentEvents = [sessionEvent]
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

        case .preToolUse:
            // Only clear completion actions on preToolUse, NOT permissions/decisions.
            // PreToolUse fires before PermissionRequest for the same tool, but arrives
            // later via file watcher (1-2s delay) vs socket (instant), so it would
            // wipe out permission actions that were just created.
            pendingActions.removeAll { $0.sessionId == event.sessionId && $0.type == .completion }

        case .userPromptSubmit, .sessionStart:
            // User genuinely resumed — clear all pending actions
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
                sessions[i].completedAt = sessions[i].completedAt ?? now
                continue
            }

            // PID liveness check
            if let pid = sessions[i].pid, kill(pid, 0) != 0 {
                NSLog("[Bobber] SessionManager: PID \(pid) dead, marking \(sessions[i].id) completed")
                sessions[i].state = .completed
                sessions[i].completedAt = now
            }
        }
        // Auto-hide completed/stale sessions after 5 seconds
        for i in sessions.indices where sessions[i].state == .completed || sessions[i].state == .stale {
            if let completedAt = sessions[i].completedAt,
               now.timeIntervalSince(completedAt) > 5,
               !hiddenSessionIds.contains(sessions[i].id) {
                NSLog("[Bobber] SessionManager: auto-hiding completed session \(sessions[i].id)")
                hiddenSessionIds.insert(sessions[i].id)
            }
        }
        // Remove sessions that have been completed for >5 minutes
        sessions.removeAll { session in
            session.state == .completed
                && now.timeIntervalSince(session.completedAt ?? session.lastEvent) > 300
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
