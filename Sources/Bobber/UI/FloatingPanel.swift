import AppKit
import SwiftUI

class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Activate app on right-click so SwiftUI .contextMenu works with .nonactivatingPanel
    override func sendEvent(_ event: NSEvent) {
        if event.type == .rightMouseDown {
            NSApp.activate(ignoringOtherApps: true)
            makeKey()
        }
        super.sendEvent(event)
    }

    private static let idleAlpha: CGFloat = 0.65
    private static let hoverAlpha: CGFloat = 1.0

    init(contentView: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.titled, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.alphaValue = Self.idleAlpha

        // Hide titlebar chrome while keeping native resize
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true

        self.contentMinSize = NSSize(width: 280, height: 200)
        self.contentMaxSize = NSSize(width: 500, height: 800)

        let hostingView = HoverTrackingHostingView(rootView: contentView) { [weak self] hovering in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                self?.animator().alphaValue = hovering ? Self.hoverAlpha : Self.idleAlpha
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

    @MainActor required override init(rootView: Content) {
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
