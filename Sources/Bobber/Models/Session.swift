import Foundation

enum SessionState: String, Codable {
    case active, blocked, idle, completed, stale
}

struct SessionEvent: Codable {
    let timestamp: Date
    let type: BobberEvent.EventType
    let tool: String?
    let summary: String?
}

struct Session: Identifiable, Codable {
    let id: String
    let projectName: String
    let projectPath: String
    var sessionTitle: String?
    var state: SessionState = .active
    var lastEvent: Date = Date()
    var lastTool: String?
    var lastToolSummary: String?
    var pendingAction: PendingAction?
    var terminal: TerminalInfo?
    var pid: Int32?
    var recentEvents: [SessionEvent] = []

    enum CodingKeys: String, CodingKey {
        case id, projectName, projectPath, sessionTitle, state
        case lastEvent, lastTool, lastToolSummary, pendingAction, terminal, pid
    }

    mutating func handleEvent(type: BobberEvent.EventType) {
        lastEvent = Date()
        switch type {
        case .permissionPrompt, .elicitationDialog:
            state = .blocked
        case .preToolUse, .userPromptSubmit, .sessionStart:
            state = .active
            pendingAction = nil
        case .stop, .taskCompleted:
            state = .idle
        case .sessionEnd:
            state = .completed
        case .idlePrompt:
            state = .idle
        case .notification:
            break
        }
    }
}
