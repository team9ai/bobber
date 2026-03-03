import AppKit

class HotkeyManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    var onTogglePanel: (() -> Void)?
    var onJumpToSession: ((Int) -> Void)?
    var isPanelVisible: (() -> Bool)?

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyDown(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyDown(event)
            return event
        }
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        // Option+B -> toggle panel
        if event.modifierFlags.contains(.option)
            && event.charactersIgnoringModifiers == "b" {
            onTogglePanel?()
            return
        }

        // Only handle number keys and escape when panel is visible
        guard isPanelVisible?() == true else { return }

        // Number keys 1-9 (no modifier) -> jump to session
        if event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
           let char = event.charactersIgnoringModifiers,
           let digit = Int(char),
           digit >= 1 && digit <= 9 {
            onJumpToSession?(digit - 1)
        }

        // Escape -> hide panel
        if event.keyCode == 53 {
            onTogglePanel?()
        }
    }
}
