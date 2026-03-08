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
        case .focus: return "Focus"
        case .priority: return "Priority"
        case .standard: return "Standard"
        }
    }

    var badge: String {
        switch self {
        case .focus: return "!!!"
        case .priority: return "!!"
        case .standard: return "!"
        }
    }

    var icon: String {
        switch self {
        case .focus: return "flame.fill"
        case .priority: return "arrow.up"
        case .standard: return "minus"
        }
    }

    var accentColor: Color {
        switch self {
        case .focus: return .orange
        case .priority: return .blue
        case .standard: return .gray
        }
    }
}
