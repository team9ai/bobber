import AppKit
import Combine

class MenubarIconManager {
    private let statusItem: NSStatusItem
    private let sessionManager: SessionManager
    private var cancellable: AnyCancellable?

    init(statusItem: NSStatusItem, sessionManager: SessionManager) {
        self.statusItem = statusItem
        self.sessionManager = sessionManager

        // Set initial icon as template (renders white in dark mode, black in light mode)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "fish.fill", accessibilityDescription: "Bobber")
            image?.isTemplate = true
            button.image = image
            button.image?.size = NSSize(width: 18, height: 18)
        }

        cancellable = sessionManager.$pendingActions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] actions in
                self?.updateBadge(pendingCount: actions.count)
            }
    }

    private func updateBadge(pendingCount: Int) {
        guard let button = statusItem.button else { return }

        if pendingCount > 0 {
            button.title = " \(pendingCount)"
        } else {
            button.title = ""
        }
    }
}
