import Foundation

enum ActionType: String, Codable {
    case permission, decision, completion
}

struct PendingAction: Identifiable {
    let id: String
    let sessionId: String
    let type: ActionType
    let timestamp: Date
    let tool: String?
    let command: String?
    let description: String?
    let question: String?
    let options: [EventOption]?
}
