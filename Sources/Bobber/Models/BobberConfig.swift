import Foundation

struct BobberConfig: Codable {
    var sounds: SoundConfig = SoundConfig()
    var sessions: SessionConfig = SessionConfig()

    struct SoundConfig: Codable {
        var enabled: Bool = true
        var volume: Float = 0.7
        var cooldownSeconds: Double = 3
    }

    struct SessionConfig: Codable {
        var staleTimeoutMinutes: Int = 30
        var keepCompletedCount: Int = 10
    }

    static let configURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bobber/config.json")
    }()

    static func load() -> BobberConfig {
        guard let data = try? Data(contentsOf: configURL) else { return BobberConfig() }
        return (try? JSONDecoder().decode(BobberConfig.self, from: data)) ?? BobberConfig()
    }

    func save() {
        let dir = Self.configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(self) {
            try? data.write(to: Self.configURL)
        }
    }
}
