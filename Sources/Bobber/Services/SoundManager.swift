import Foundation

class SoundManager {
    var enabled: Bool = true
    var volume: Float = 0.7
    var cooldownSeconds: TimeInterval = 3
    private var lastPlayTime: Date?

    private let soundPaths: [ActionType: String] = [
        .permission: "/System/Library/Sounds/Sosumi.aiff",
        .decision: "/System/Library/Sounds/Ping.aiff",
        .completion: "/System/Library/Sounds/Glass.aiff",
    ]

    func play(for type: ActionType) {
        guard enabled, shouldPlay() else { return }
        guard let path = soundPaths[type] else { return }

        recordPlay()
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            process.arguments = ["-v", String(self.volume), path]
            try? process.run()
        }
    }

    func shouldPlay() -> Bool {
        guard let last = lastPlayTime else { return true }
        return Date().timeIntervalSince(last) >= cooldownSeconds
    }

    func recordPlay() {
        lastPlayTime = Date()
    }
}
