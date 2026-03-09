# Sound System: Configurable Sound Effects

## Problem

Sound only triggers for permission events via PermissionServer socket. Events arriving through EventFileWatcher (taskCompleted, stop, elicitationDialog) never play sound. Users cannot configure which sound plays for each event type.

## Design

### Data Model

Extend `SoundConfig` with per-event-type sound names:

```swift
struct SoundConfig: Codable {
    var enabled: Bool = true
    var volume: Float = 0.7
    var cooldownSeconds: Double = 3
    var permissionSound: String = "Sosumi"
    var completionSound: String = "Glass"
    var decisionSound: String = "Ping"
}
```

Sound names map to macOS system sounds at `/System/Library/Sounds/{name}.aiff`.

Available presets: Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink.

### SoundManager

Replace hardcoded `soundPaths: [ActionType: String]` with `soundNames: [ActionType: String]` dictionary. Values are sound names (not full paths), resolved to paths at play time. Dictionary synced from config via `applyConfig()`.

Add static list of available system sounds for the settings UI.

### Trigger Points

**Existing** (no change): PermissionServer `onPermissionRequest` callback plays `.permission`.

**New**: AppDelegate's `setupEventWatcher` onChange callback plays sounds based on event type:

| EventType | ActionType | Sound |
|---|---|---|
| permissionPrompt | .permission | (handled by PermissionServer, not here) |
| taskCompleted | .completion | Glass |
| idlePrompt | .completion | Glass |
| stop | .completion | Glass |
| elicitationDialog | .decision | Ping |
| Others | — | silent |

### Settings UI

Add "Sound Effects" section to SoundsSettingsView below existing controls:

- One `Picker` (dropdown) per event type: Permission, Completion, Decision
- Each picker lists all 14 system sounds
- Preview button next to each picker plays the selected sound
- Entire section disabled when sounds are disabled

## Files to Change

1. `Sources/Bobber/Models/BobberConfig.swift` — add sound name fields to SoundConfig
2. `Sources/Bobber/Services/SoundManager.swift` — soundNames dict, available sounds list
3. `Sources/Bobber/AppDelegate.swift` — add sound triggers in setupEventWatcher, sync new config fields in applyConfig
4. `Sources/Bobber/UI/Settings/SoundsSettingsView.swift` — add per-event sound pickers with preview