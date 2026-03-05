import AppKit
import SwiftUI

class ClickHostingView<Content: View>: NSHostingView<Content> {

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { false }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = .clear
    }
}
