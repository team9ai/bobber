import AppKit

// Use pure AppKit entry point instead of SwiftUI App protocol
// SwiftUI's Settings-only scene doesn't reliably trigger app lifecycle in SPM builds
@main
enum BobberApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
