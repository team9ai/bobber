import AppKit
import SwiftUI

class PanelController {
    private var _panel: FloatingPanel?
    private let sessionManager: SessionManager
    private let onPermissionDecision: ((String, PermissionDecision) -> Void)?
    private let onJumpToSession: ((Session) -> Void)?
    private let onSettings: (() -> Void)?

    var floatingPanel: FloatingPanel? { _panel }

    init(sessionManager: SessionManager,
         onPermissionDecision: ((String, PermissionDecision) -> Void)? = nil,
         onJumpToSession: ((Session) -> Void)? = nil,
         onSettings: (() -> Void)? = nil) {
        self.sessionManager = sessionManager
        self.onPermissionDecision = onPermissionDecision
        self.onJumpToSession = onJumpToSession
        self.onSettings = onSettings
    }

    var isVisible: Bool { _panel?.isVisible ?? false }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        if _panel == nil {
            let contentView = PanelContentView(
                sessionManager: sessionManager,
                onPermissionDecision: onPermissionDecision,
                onJumpToSession: onJumpToSession,
                onHide: { [weak self] in self?.hide() },
                onSettings: onSettings
            )
            _panel = FloatingPanel(contentView: contentView)
            restorePosition()

            NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: _panel,
                queue: .main
            ) { [weak self] _ in self?.savePosition() }
        }
        _panel?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        _panel?.orderOut(nil)
    }

    private func savePosition() {
        guard let frame = _panel?.frame else { return }
        UserDefaults.standard.set(frame.origin.x, forKey: "bobber.panel.x")
        UserDefaults.standard.set(frame.origin.y, forKey: "bobber.panel.y")
    }

    private func restorePosition() {
        let x = UserDefaults.standard.double(forKey: "bobber.panel.x")
        let y = UserDefaults.standard.double(forKey: "bobber.panel.y")
        if x != 0 || y != 0 {
            _panel?.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            _panel?.center()
        }
    }
}
