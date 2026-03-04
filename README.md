# Bobber

A native macOS floating companion for monitoring multiple [Claude Code](https://docs.anthropic.com/en/docs/claude-code) sessions at a glance.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License: MIT](https://img.shields.io/badge/License-MIT-green)

## What it does

Bobber sits as a floating panel on your desktop, showing all your active Claude Code sessions in real-time. It watches for events via a Claude Code plugin, displays session status, pending permissions, and lets you jump between terminal windows.

**Key features:**

- Floating always-on-top panel that doesn't steal focus
- Real-time session monitoring with status indicators (active / idle / blocked / completed)
- Priority system (Focus / Priority / Standard) for organizing sessions
- Permission request cards with approve/deny actions via Unix socket IPC
- Global hotkey (Option+B) to toggle the panel
- Menu bar icon with session count
- Jump-to-terminal for any session

## Install

```bash
# Clone and build
git clone https://github.com/winrey/bobber.git
cd bobber
swift build -c release

# Copy the built app
cp -r .build/release/Bobber /usr/local/bin/

# Install the Claude Code plugin
cp -r plugins/claude-bobber-plugin ~/.claude/plugins/
```

## Usage

```bash
# Run Bobber
swift run
# or after installing to PATH
Bobber
```

Then start any Claude Code session — Bobber will automatically detect and display it.

**Controls:**

- `Option+B` — Toggle panel visibility
- Click a session row — View session details
- Right-click a session — Set priority, rename, or hide
- Right-click a project header — Set default priority for all sessions in that project

## Architecture

```
Sources/Bobber/
├── Models/          # BobberEvent, Session, PendingAction, SessionPriority, BobberConfig
├── Services/        # SessionManager, EventFileWatcher, PermissionServer, HotkeyManager, ...
└── UI/              # FloatingPanel (NSPanel), PanelController, SessionRowView, ...
```

- **Event pipeline**: Claude Code plugin writes JSON events to `~/.bobber/events/` → FSEvents watcher picks them up → SessionManager updates state → SwiftUI views react
- **Permission IPC**: Unix domain socket at `/tmp/bobber.sock` — plugin sends permission requests, Bobber shows cards, user decides, response flows back
- **Zero dependencies**: Pure Swift + SwiftUI + AppKit, built with SPM

## Requirements

- macOS 13 (Ventura) or later
- Swift 5.9+
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI

## License

MIT
