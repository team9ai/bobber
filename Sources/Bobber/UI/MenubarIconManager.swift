import AppKit
import Combine

class MenubarIconManager {
    private let statusItem: NSStatusItem
    private let sessionManager: SessionManager
    private var cancellable: AnyCancellable?

    init(statusItem: NSStatusItem, sessionManager: SessionManager) {
        self.statusItem = statusItem
        self.sessionManager = sessionManager

        cancellable = sessionManager.$pendingActions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] actions in
                self?.updateIcon(pendingCount: actions.count)
            }
    }

    private func updateIcon(pendingCount: Int) {
        guard let button = statusItem.button else { return }

        let symbolName: String
        let tintColor: NSColor

        if pendingCount > 0 {
            symbolName = "circle.fill"
            tintColor = .systemRed
        } else if sessionManager.sessions.contains(where: { $0.state == .active }) {
            symbolName = "circle.fill"
            tintColor = .systemGreen
        } else {
            symbolName = "circle"
            tintColor = .secondaryLabelColor
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Bobber")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        button.image = image
        button.contentTintColor = tintColor

        if pendingCount > 0 {
            button.title = " \(pendingCount)"
        } else {
            button.title = ""
        }
    }
}
