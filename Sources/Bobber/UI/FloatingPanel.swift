import AppKit
import SwiftUI

class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Activate app only on right-click so .contextMenu works with .nonactivatingPanel.
    // Left-click deliberately does NOT activate — the panel should not steal focus.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .rightMouseDown {
            NSApp.activate(ignoringOtherApps: true)
            makeKey()
        }
        super.sendEvent(event)
    }

    private(set) var idleAlpha: CGFloat = 0.65
    private(set) var hoverAlpha: CGFloat = 1.0
    private(set) var isHovering: Bool = false

    func updateOpacity(idle: CGFloat, hover: CGFloat) {
        idleAlpha = idle
        hoverAlpha = hover

        // Re-check actual hover: another window may be covering us
        let mouse = NSEvent.mouseLocation
        if frame.contains(mouse) {
            let top = NSWindow.windowNumber(at: mouse, belowWindowWithWindowNumber: 0)
            isHovering = (top == windowNumber)
        } else {
            isHovering = false
        }

        // Cancel any in-flight hover animation and apply immediately
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            self.animator().alphaValue = isHovering ? hoverAlpha : idleAlpha
        }
    }

    init(contentView: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.alphaValue = idleAlpha

        self.contentMinSize = NSSize(width: 280, height: 200)
        self.contentMaxSize = NSSize(width: 500, height: 800)

        let hostingView = HoverTrackingHostingView(rootView: contentView) { [weak self] hovering in
            self?.isHovering = hovering
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                self?.animator().alphaValue = hovering ? (self?.hoverAlpha ?? 1.0) : (self?.idleAlpha ?? 0.65)
            }
        }
        self.contentView = hostingView
    }
}

/// A hosting view that tracks mouse enter/exit for the entire panel area.
private class HoverTrackingHostingView<Content: View>: ClickHostingView<Content> {
    private let onHover: (Bool) -> Void

    init(rootView: Content, onHover: @escaping (Bool) -> Void) {
        self.onHover = onHover
        super.init(rootView: rootView)
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    @MainActor required init(rootView: Content) {
        self.onHover = { _ in }
        super.init(rootView: rootView)
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func mouseEntered(with event: NSEvent) {
        onHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover(false)
    }
}
