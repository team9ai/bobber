import AppKit

class WindowJumper {
    func jumpToSession(_ session: Session) {
        let terminal = session.terminal

        if let tmuxTarget = terminal?.tmuxTarget {
            jumpViaTmux(target: tmuxTarget)
            return
        }

        switch terminal?.app?.lowercased() {
        case "iterm2":
            jumpToITerm2(sessionId: terminal?.tabId ?? "")
        case "terminal", "terminal.app":
            jumpToTerminalApp(ttyPath: terminal?.ttyPath ?? "")
        case "vscode":
            jumpToVSCode(
                bundleId: terminal?.bundleId ?? "com.microsoft.VSCode",
                projectPath: session.projectPath
            )
        case "jetbrains":
            jumpToJetBrains(
                bundleId: terminal?.bundleId,
                projectPath: session.projectPath
            )
        case "ghostty":
            activateByBundleId("com.mitchellh.ghostty")
        case "kitty":
            activateByBundleId("net.kovidgoyal.kitty")
        default:
            // Unknown or missing terminal — try to detect from PID
            if let bundleId = terminal?.bundleId {
                activateByBundleId(bundleId)
            } else {
                jumpByPid(session: session)
            }
        }
    }

    /// Walk up the process tree from session PID to find the parent app
    private func jumpByPid(session: Session) {
        guard let pid = session.pid else { return }

        var currentPid = pid
        for _ in 0..<8 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-o", "ppid=,comm=", "-p", "\(currentPid)"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()

            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !output.isEmpty else { return }

            // Parse "ppid comm..." — ppid is first token
            let parts = output.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2, let ppid = Int32(parts[0].trimmingCharacters(in: .whitespaces)) else { return }
            let comm = String(parts[1])

            if comm.contains("VisualStudioCode") || comm.contains("Electron") {
                jumpToVSCode(bundleId: "com.microsoft.VSCode", projectPath: session.projectPath)
                return
            }
            if comm.contains("Cursor.app") {
                jumpToVSCode(bundleId: "com.todesktop.230313mzl4w4u92", projectPath: session.projectPath)
                return
            }
            if comm.lowercased().contains("idea") || comm.lowercased().contains("webstorm") ||
               comm.lowercased().contains("pycharm") || comm.lowercased().contains("goland") {
                jumpToJetBrains(bundleId: nil, projectPath: session.projectPath)
                return
            }
            if comm.contains("iTerm2") {
                activateByBundleId("com.googlecode.iterm2")
                return
            }
            if comm.contains("Terminal") && comm.contains("Apple") {
                activateByBundleId("com.apple.Terminal")
                return
            }
            if comm.contains("ghostty") {
                activateByBundleId("com.mitchellh.ghostty")
                return
            }
            if comm.contains("kitty") {
                activateByBundleId("net.kovidgoyal.kitty")
                return
            }

            if ppid <= 1 { return }
            currentPid = ppid
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

    private func jumpToVSCode(bundleId: String, projectPath: String) {
        // Map bundle ID to CLI command name
        let cli: String
        switch bundleId {
        case "com.todesktop.230313mzl4w4u92":
            cli = "cursor"
        case "com.microsoft.VSCodeInsiders":
            cli = "code-insiders"
        default:
            cli = "code"
        }

        // `code <folder>` focuses the existing window with that folder open
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [cli, projectPath]
        try? process.run()
    }

    private func jumpToJetBrains(bundleId: String?, projectPath: String) {
        if let bundleId = bundleId, !bundleId.isEmpty {
            // Use `open -b <bundleId> <path>` to activate the correct window
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-b", bundleId, projectPath]
            try? process.run()
        } else {
            // Fallback: try common JetBrains CLI tools
            let tools = ["idea", "webstorm", "pycharm", "goland", "clion", "rider", "rubymine", "phpstorm", "datagrip"]
            for tool in tools {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["which", tool]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                try? process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    let open = Process()
                    open.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    open.arguments = [tool, projectPath]
                    try? open.run()
                    return
                }
            }
        }
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
