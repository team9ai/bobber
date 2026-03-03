import AppKit
import SwiftUI

class PanelController {
    private var panel: FloatingPanel?
    private let sessionManager: SessionManager
    private let onPermissionDecision: ((String, PermissionDecision) -> Void)?

    init(sessionManager: SessionManager, onPermissionDecision: ((String, PermissionDecision) -> Void)? = nil) {
        self.sessionManager = sessionManager
        self.onPermissionDecision = onPermissionDecision
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        if panel == nil {
            let contentView = PanelContentView(
                sessionManager: sessionManager,
                onPermissionDecision: onPermissionDecision
            )
            panel = FloatingPanel(contentView: contentView)
            restorePosition()

            NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in self?.savePosition() }
        }
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func savePosition() {
        guard let frame = panel?.frame else { return }
        UserDefaults.standard.set(frame.origin.x, forKey: "bobber.panel.x")
        UserDefaults.standard.set(frame.origin.y, forKey: "bobber.panel.y")
    }

    private func restorePosition() {
        let x = UserDefaults.standard.double(forKey: "bobber.panel.x")
        let y = UserDefaults.standard.double(forKey: "bobber.panel.y")
        if x != 0 || y != 0 {
            panel?.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel?.center()
        }
    }
}
