import SwiftUI

enum SessionPriority: Int, Codable, CaseIterable, Comparable {
    case focus = 0
    case priority = 1
    case standard = 2

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .focus: return "专注"
        case .priority: return "优先"
        case .standard: return "标准"
        }
    }

    var accentColor: Color {
        switch self {
        case .focus: return .orange
        case .priority: return .blue
        case .standard: return .secondary
        }
    }
}
