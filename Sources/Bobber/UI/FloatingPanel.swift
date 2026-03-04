import AppKit
import SwiftUI

class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentView: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true

        let hostingView = ClickHostingView(rootView: contentView)
        self.contentView = hostingView
    }
}
