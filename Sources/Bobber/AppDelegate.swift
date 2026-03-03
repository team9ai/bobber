import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panelController: PanelController?
    private var sessionManager: SessionManager!
    private var eventWatcher: EventFileWatcher?
    private var permissionServer: PermissionServer?
    private var hotkeyManager: HotkeyManager?
    private var iconManager: MenubarIconManager?
    private var soundManager: SoundManager!
    private var windowJumper: WindowJumper!
    private var cleanupTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[Bobber] applicationDidFinishLaunching called")
        NSApp.setActivationPolicy(.accessory)
        ensureDirectories()

        sessionManager = SessionManager()
        soundManager = SoundManager()
        windowJumper = WindowJumper()

        setupMenubarIcon()
        NSLog("[Bobber] menubar icon setup done, statusItem: \(String(describing: statusItem))")
        setupPanel()
        setupEventWatcher()
        setupPermissionServer()
        setupHotkey()
        setupCleanupTimer()

        // Auto-show panel on launch for debugging
        panelController?.show()
        NSLog("[Bobber] panel shown on launch")
    }

    private func setupMenubarIcon() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: "fish.fill", accessibilityDescription: "Bobber")
            image?.isTemplate = true
            button.image = image
            button.image?.size = NSSize(width: 18, height: 18)
            button.action = #selector(togglePanel)
            button.target = self
        }
        iconManager = MenubarIconManager(statusItem: statusItem!, sessionManager: sessionManager)
    }

    private func setupPanel() {
        panelController = PanelController(
            sessionManager: sessionManager,
            onPermissionDecision: { [weak self] sessionId, decision in
                self?.permissionServer?.respond(sessionId: sessionId, decision: decision)
            }
        )
    }

    private func setupEventWatcher() {
        eventWatcher = EventFileWatcher { [weak self] event in
            self?.sessionManager.handleEvent(event)
        }
        try? eventWatcher?.start()
    }

    private func setupPermissionServer() {
        permissionServer = PermissionServer()
        permissionServer?.onPermissionRequest = { [weak self] sessionId, event in
            guard let self else { return }
            self.sessionManager.handleEvent(event)
            self.soundManager.play(for: .permission)
            self.panelController?.show()
        }
        try? permissionServer?.start()
    }

    private func setupHotkey() {
        hotkeyManager = HotkeyManager()
        hotkeyManager?.onTogglePanel = { [weak self] in
            self?.panelController?.toggle()
        }
        hotkeyManager?.onJumpToSession = { [weak self] index in
            guard let self,
                  index < self.sessionManager.sessions.count else { return }
            let session = self.sessionManager.sessions[index]
            self.windowJumper.jumpToSession(session)
        }
        hotkeyManager?.start()
    }

    private func setupCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.sessionManager.cleanupSessions()
        }
    }

    private func ensureDirectories() {
        let bobberDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".bobber")
        let eventsDir = bobberDir.appendingPathComponent("events")
        try? FileManager.default.createDirectory(at: eventsDir, withIntermediateDirectories: true)

        let configURL = bobberDir.appendingPathComponent("config.json")
        if !FileManager.default.fileExists(atPath: configURL.path) {
            BobberConfig().save()
        }
    }

    @objc private func togglePanel() {
        panelController?.toggle()
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventWatcher?.stop()
        permissionServer?.stop()
        hotkeyManager?.stop()
        cleanupTimer?.invalidate()
    }
}
