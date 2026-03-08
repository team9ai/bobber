import Foundation

struct BobberConfig: Codable {
    var sounds: SoundConfig = SoundConfig()
    var sessions: SessionConfig = SessionConfig()
    var appearance: AppearanceConfig = AppearanceConfig()
    var shortcuts: ShortcutsConfig = ShortcutsConfig()
    var general: GeneralConfig = GeneralConfig()

    struct SoundConfig: Codable {
        var enabled: Bool = true
        var volume: Float = 0.7
        var cooldownSeconds: Double = 3
    }

    struct SessionConfig: Codable {
        var staleTimeoutMinutes: Int = 30
        var keepCompletedCount: Int = 10
    }

    struct AppearanceConfig: Codable {
        var idleOpacity: Double = 0.65
        var hoverOpacity: Double = 1.0
    }

    struct ShortcutsConfig: Codable {
        var togglePanelKey: String = "b"
        var togglePanelModifiers: [String] = ["option"]
    }

    struct GeneralConfig: Codable {
        var claudeCLIPath: String? = nil
        var launchAtLogin: Bool = false
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sounds = try container.decodeIfPresent(SoundConfig.self, forKey: .sounds) ?? SoundConfig()
        sessions = try container.decodeIfPresent(SessionConfig.self, forKey: .sessions) ?? SessionConfig()
        appearance = try container.decodeIfPresent(AppearanceConfig.self, forKey: .appearance) ?? AppearanceConfig()
        shortcuts = try container.decodeIfPresent(ShortcutsConfig.self, forKey: .shortcuts) ?? ShortcutsConfig()
        general = try container.decodeIfPresent(GeneralConfig.self, forKey: .general) ?? GeneralConfig()
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
