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

    private static let searchPaths = [
        "/usr/local/bin/claude",
        "/opt/homebrew/bin/claude",
    ]

    private static let githubRepo = "anthropics/bobber"  // TODO: replace with actual repo

    func autoDetect() {
        // Try `which claude` first
        if let path = runShell("/usr/bin/which", args: ["claude"]), !path.isEmpty {
            cliPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }
        // Try known paths
        for path in Self.searchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                cliPath = path
                return
            }
        }
        // Try ~/.npm/bin/claude
        let npmPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".npm/bin/claude").path
        if FileManager.default.isExecutableFile(atPath: npmPath) {
            cliPath = npmPath
            return
        }
        // Try ~/.claude/local/claude
        let localPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/local/claude").path
        if FileManager.default.isExecutableFile(atPath: localPath) {
            cliPath = localPath
            return
        }
        cliPath = nil
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
            await MainActor.run {
                self?.operationLog += "Adding marketplace...\n\(addResult ?? "")\n"
            }

            // Step 2: Install plugin
            let installResult = self?.runCLI(cli, args: ["plugin", "install", "bobber-claude@bobber"])
            await MainActor.run {
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
            await MainActor.run {
                self?.operationLog += "Uninstalling plugin...\n\(uninstallResult ?? "")\n"
            }

            let removeResult = self?.runCLI(cli, args: ["plugin", "marketplace", "remove", "bobber"])
            await MainActor.run {
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
            await MainActor.run {
                self?.operationLog += "Updating plugin...\n\(result ?? "")\n"
                self?.isRunningOperation = false
                self?.checkPluginStatus()
                completion(self?.pluginStatus == .installed)
            }
        }
    }

    // MARK: - Private

    private func runShell(_ path: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func runCLI(_ cli: String, args: [String]) -> String? {
        return runShell(cli, args: args)
    }
}
