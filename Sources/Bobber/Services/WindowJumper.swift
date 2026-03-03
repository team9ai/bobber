import AppKit

class WindowJumper {
    func jumpToSession(_ session: Session) {
        guard let terminal = session.terminal else { return }

        if let tmuxTarget = terminal.tmuxTarget {
            jumpViaTmux(target: tmuxTarget)
            return
        }

        switch terminal.app?.lowercased() {
        case "iterm2":
            jumpToITerm2(sessionId: terminal.tabId ?? "")
        case "terminal", "terminal.app":
            jumpToTerminalApp(ttyPath: terminal.ttyPath ?? "")
        case "ghostty":
            activateByBundleId("com.mitchellh.ghostty")
        case "kitty":
            activateByBundleId("net.kovidgoyal.kitty")
        default:
            if let bundleId = terminal.bundleId {
                activateByBundleId(bundleId)
            }
        }
    }

    private func sanitizeForAppleScript(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func jumpToITerm2(sessionId: String) {
        let script = """
        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if unique id of s is "\(sanitizeForAppleScript(sessionId))" then
                            select t
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
        runAppleScript(script)
    }

    private func jumpToTerminalApp(ttyPath: String) {
        let script = """
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(sanitizeForAppleScript(ttyPath))" then
                        set selected tab of w to t
                        set index of w to 1
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
        runAppleScript(script)
    }

    private func jumpViaTmux(target: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tmux", "select-window", "-t", target]
        try? process.run()
        process.waitUntilExit()
    }

    private func activateByBundleId(_ bundleId: String) {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleId }?
            .activate()
    }

    private func runAppleScript(_ source: String) {
        if let script = NSAppleScript(source: source) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
        }
    }
}
