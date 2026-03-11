import Foundation

enum PluginStatus: Equatable {
    case unknown
    case notInstalled
    case installed
    case installedDisabled
    case updateAvailable(local: String, remote: String)
    case cliNotFound
}

class ClaudeCLIManager: ObservableObject {
    @Published var cliPath: String?
    @Published var pluginStatus: PluginStatus = .unknown
    @Published var isRunningOperation: Bool = false
    @Published var operationLog: String = ""

    private static let githubRepo = "winrey/bobber"

    /// Known paths where Claude CLI might be installed
    private static func knownPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(home)/.npm/bin/claude",
            "\(home)/.claude/local/claude",
            "\(home)/.local/bin/claude",
            // nvm common paths
            "\(home)/.nvm/current/bin/claude",
            // volta
            "\(home)/.volta/bin/claude",
            // pnpm
            "\(home)/.local/share/pnpm/claude",
            "\(home)/Library/pnpm/claude",
            // bun
            "\(home)/.bun/bin/claude",
        ]
    }

    func autoDetect() {
        var log = "Auto-detecting Claude CLI...\n"

        // Try `which claude` using a login shell to get the user's full PATH
        if let path = runLoginShell("which claude"), !path.isEmpty {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            log += "Found via shell: \(trimmed)\n"
            cliPath = trimmed
            operationLog = log
            return
        }
        log += "Shell lookup failed, trying known paths...\n"

        // Fallback: try known paths
        for path in Self.knownPaths() {
            if FileManager.default.isExecutableFile(atPath: path) {
                log += "Found at: \(path)\n"
                cliPath = path
                operationLog = log
                return
            }
        }

        log += "Not found in any known location.\n"
        cliPath = nil
        operationLog = log
    }

    func setCustomPath(_ path: String) {
        cliPath = path
    }

    func checkPluginStatus() {
        guard cliPath != nil else {
            pluginStatus = .cliNotFound
            return
        }

        // Check installed_plugins.json
        let installedURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/plugins/installed_plugins.json")
        guard let data = try? Data(contentsOf: installedURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = json["plugins"] as? [String: Any] else {
            pluginStatus = .notInstalled
            return
        }

        // Look for bobber-claude in any marketplace
        let bobberKey = plugins.keys.first { $0.hasPrefix("bobber-claude@") }
        guard bobberKey != nil else {
            pluginStatus = .notInstalled
            return
        }

        // Check enabledPlugins in settings.json
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        if let settingsData = try? Data(contentsOf: settingsURL),
           let settings = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any],
           let enabled = settings["enabledPlugins"] as? [String: Bool] {
            let enabledKey = enabled.keys.first { $0.hasPrefix("bobber-claude@") }
            if let key = enabledKey, enabled[key] == false {
                pluginStatus = .installedDisabled
                return
            }
        }

        pluginStatus = .installed
    }

    func installPlugin(completion: @escaping (Bool) -> Void) {
        guard let cli = cliPath else {
            completion(false)
            return
        }
        isRunningOperation = true
        operationLog = ""

        Task.detached { [weak self] in
            // Step 1: Add marketplace
            let addResult = self?.runCLI(cli, args: ["plugin", "marketplace", "add", Self.githubRepo])
            await MainActor.run { [weak self] in
                self?.operationLog += "Adding marketplace...\n\(addResult ?? "")\n"
            }

            // Step 2: Install plugin
            let installResult = self?.runCLI(cli, args: ["plugin", "install", "bobber-claude@bobber"])
            await MainActor.run { [weak self] in
                self?.operationLog += "Installing plugin...\n\(installResult ?? "")\n"
                self?.isRunningOperation = false
                self?.checkPluginStatus()
                completion(self?.pluginStatus == .installed)
            }
        }
    }

    func uninstallPlugin(completion: @escaping (Bool) -> Void) {
        guard let cli = cliPath else {
            completion(false)
            return
        }
        isRunningOperation = true
        operationLog = ""

        Task.detached { [weak self] in
            let uninstallResult = self?.runCLI(cli, args: ["plugin", "uninstall", "bobber-claude@bobber"])
            await MainActor.run { [weak self] in
                self?.operationLog += "Uninstalling plugin...\n\(uninstallResult ?? "")\n"
            }

            let removeResult = self?.runCLI(cli, args: ["plugin", "marketplace", "remove", "bobber"])
            await MainActor.run { [weak self] in
                self?.operationLog += "Removing marketplace...\n\(removeResult ?? "")\n"
                self?.isRunningOperation = false
                self?.checkPluginStatus()
                completion(self?.pluginStatus == .notInstalled)
            }
        }
    }

    func enablePlugin(completion: @escaping (Bool) -> Void) {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            completion(false)
            return
        }
        var enabled = settings["enabledPlugins"] as? [String: Bool] ?? [:]
        if let key = enabled.keys.first(where: { $0.hasPrefix("bobber-claude@") }) {
            enabled[key] = true
        }
        settings["enabledPlugins"] = enabled
        if let newData = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? newData.write(to: settingsURL)
        }
        checkPluginStatus()
        completion(pluginStatus == .installed)
    }

    func reinstallPlugin(completion: @escaping (Bool) -> Void) {
        uninstallPlugin { [weak self] _ in
            self?.installPlugin(completion: completion)
        }
    }

    func updatePlugin(completion: @escaping (Bool) -> Void) {
        guard let cli = cliPath else {
            completion(false)
            return
        }
        isRunningOperation = true
        operationLog = ""

        Task.detached { [weak self] in
            let result = self?.runCLI(cli, args: ["plugin", "update", "bobber-claude@bobber"])
            await MainActor.run { [weak self] in
                self?.operationLog += "Updating plugin...\n\(result ?? "")\n"
                self?.isRunningOperation = false
                self?.checkPluginStatus()
                completion(self?.pluginStatus == .installed)
            }
        }
    }

    // MARK: - Private

    /// The user's default shell
    private var userShell: String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    /// Shell snippet that sources rc files (where nvm/volta/etc. set PATH).
    /// Login shell already sources .zprofile/.profile, but tools like nvm add
    /// their PATH setup to .zshrc/.bashrc which -lc doesn't source.
    private var rcSourceSnippet: String {
        let shell = userShell
        if shell.hasSuffix("zsh") {
            return "[ -f ~/.zshrc ] && source ~/.zshrc 2>/dev/null; "
        } else if shell.hasSuffix("bash") {
            return "[ -f ~/.bashrc ] && source ~/.bashrc 2>/dev/null; "
        }
        return ""
    }

    /// Run a command through the user's login shell with full PATH
    private func runLoginShell(_ command: String) -> String? {
        let fullCommand = rcSourceSnippet + command
        guard let output = runShell(userShell, args: ["-lc", fullCommand]) else { return nil }
        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        return lines.last
    }

    private func runShell(_ path: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            // Read before waitUntilExit to avoid pipe buffer deadlock
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Run the claude CLI through login shell so node/etc. are in PATH.
    /// Direct execution fails because claude's shebang (#!/usr/bin/env node)
    /// can't find node in the minimal macOS app bundle PATH.
    private func runCLI(_ cli: String, args: [String]) -> String? {
        let escapedArgs = ([cli] + args).map { shellEscape($0) }.joined(separator: " ")
        let fullCommand = rcSourceSnippet + escapedArgs
        return runShell(userShell, args: ["-lc", fullCommand])
    }

    private func shellEscape(_ arg: String) -> String {
        "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
