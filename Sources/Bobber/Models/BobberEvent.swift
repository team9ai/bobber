import Foundation

struct BobberEvent: Codable {
    let version: Int
    let timestamp: Date
    let pid: Int32
    let sessionId: String
    let projectPath: String
    let projectName: String
    let sessionTitle: String?
    let eventType: EventType
    let details: EventDetails?
    let terminal: TerminalInfo?

    enum EventType: String, Codable {
        case sessionStart = "session_start"
        case preToolUse = "pre_tool_use"
        case permissionPrompt = "permission_prompt"
        case elicitationDialog = "elicitation_dialog"
        case notification = "notification"
        case stop = "stop"
        case taskCompleted = "task_completed"
        case userPromptSubmit = "user_prompt_submit"
        case sessionEnd = "session_end"
        case idlePrompt = "idle_prompt"
    }
}

struct EventDetails: Codable {
    let tool: String?
    let command: String?
    let description: String?
    let question: String?
    let options: [EventOption]?
    let message: String?
}

struct EventOption: Codable, Identifiable {
    var id: String { key }
    let key: String
    let label: String
    let description: String?
}

struct TerminalInfo: Codable {
    let app: String?
    let bundleId: String?
    let windowId: String?
    let tabId: String?
    let pid: Int32?
    let ttyPath: String?
    let tmuxTarget: String?
}

extension JSONDecoder {
    static let bobber: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
