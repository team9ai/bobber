# Bobber Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a native macOS floating desktop companion that monitors multiple Claude Code sessions, surfaces pending actions (permissions, decisions, completions), and lets users act on them inline without switching windows.

**Architecture:** A menubar + floating panel macOS app (Swift/SwiftUI/AppKit) that receives events from Claude Code via hook scripts. Async events (status changes) are captured via JSON files in `~/.bobber/events/` watched by FSEvents. Sync events (permission requests) use Unix domain socket IPC with blocking recv(). The UI shows sessions and action cards in a non-activating NSPanel.

**Tech Stack:** Swift, SwiftUI, AppKit (NSPanel, NSStatusItem), Unix domain sockets (Darwin), FSEvents/DispatchSource, AppleScript (NSAppleScript), AVAudioPlayer, JSON (Codable), Claude Code Plugin System

---

## Phase 1: Project Scaffold & Core Infrastructure

### Task 1: Create Xcode Project Structure

**Files:**
- Create: `Bobber/BobberApp.swift` (App entry point)
- Create: `Bobber/Info.plist`
- Create: `Package.swift` (SPM-based build)

**Step 1: Initialize Swift Package with macOS app target**

```swift
// Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Bobber",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Bobber",
            path: "Sources/Bobber"
        )
    ]
)
```

**Step 2: Create minimal App entry point**

```swift
// Sources/Bobber/BobberApp.swift
import SwiftUI

@main
struct BobberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
```

**Step 3: Create AppDelegate with menubar icon and no dock icon**

```swift
// Sources/Bobber/AppDelegate.swift
import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panelController: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // No dock icon
        setupMenubarIcon()
    }

    private func setupMenubarIcon() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Bobber")
            button.action = #selector(togglePanel)
            button.target = self
        }
    }

    @objc private func togglePanel() {
        // Placeholder — will be implemented in Task 4
    }
}
```

**Step 4: Build and run to verify menubar icon appears**

Run: `swift build && swift run`
Expected: App launches with no dock icon, menubar icon visible

**Step 5: Commit**

```bash
git add Sources/ Package.swift
git commit -m "feat: scaffold Bobber macOS app with menubar icon"
```

---

### Task 2: Data Models

**Files:**
- Create: `Sources/Bobber/Models/BobberEvent.swift`
- Create: `Sources/Bobber/Models/Session.swift`
- Create: `Sources/Bobber/Models/PendingAction.swift`

**Step 1: Write tests for model decoding**

```swift
// Tests/BobberTests/ModelTests.swift
import XCTest
@testable import Bobber

final class ModelTests: XCTestCase {
    func testDecodePermissionEvent() throws {
        let json = """
        {
          "version": 1,
          "timestamp": "2026-03-02T10:30:00Z",
          "pid": 54321,
          "sessionId": "test-session-1",
          "projectPath": "/Users/test/Projects/taskcast",
          "projectName": "taskcast",
          "sessionTitle": "Fix auth",
          "eventType": "permission_prompt",
          "details": {
            "tool": "Bash",
            "command": "pnpm test",
            "description": "Run all tests"
          }
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder.bobber.decode(BobberEvent.self, from: json)
        XCTAssertEqual(event.sessionId, "test-session-1")
        XCTAssertEqual(event.eventType, .permissionPrompt)
        XCTAssertEqual(event.details?.tool, "Bash")
    }

    func testSessionStateTransitions() {
        var session = Session(id: "s1", projectName: "test", projectPath: "/tmp/test")
        XCTAssertEqual(session.state, .active)

        session.handleEvent(type: .permissionPrompt)
        XCTAssertEqual(session.state, .blocked)

        session.handleEvent(type: .preToolUse)
        XCTAssertEqual(session.state, .active)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | head -20`
Expected: Compilation errors — models don't exist yet

**Step 3: Implement data models**

```swift
// Sources/Bobber/Models/BobberEvent.swift
import Foundation

struct BobberEvent: Codable {
    let version: Int
    let timestamp: Date
    let pid: Int32
    let sessionId: String
    let projectPath: String
    let projectName: String
    let sessionTitle: String?
    let eventType: EventType
    let details: EventDetails?
    let terminal: TerminalInfo?

    enum EventType: String, Codable {
        case sessionStart = "session_start"
        case preToolUse = "pre_tool_use"
        case permissionPrompt = "permission_prompt"
        case elicitationDialog = "elicitation_dialog"
        case notification = "notification"
        case stop = "stop"
        case taskCompleted = "task_completed"
        case userPromptSubmit = "user_prompt_submit"
        case sessionEnd = "session_end"
        case idlePrompt = "idle_prompt"
    }
}

struct EventDetails: Codable {
    let tool: String?
    let command: String?
    let description: String?
    let question: String?
    let options: [EventOption]?
    let message: String?
}

struct EventOption: Codable, Identifiable {
    var id: String { key }
    let key: String
    let label: String
    let description: String?
}

struct TerminalInfo: Codable {
    let app: String?
    let bundleId: String?
    let windowId: String?
    let tabId: String?
    let pid: Int32?
    let ttyPath: String?
    let tmuxTarget: String?  // "session:window.pane"
}

extension JSONDecoder {
    static let bobber: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
```

```swift
// Sources/Bobber/Models/Session.swift
import Foundation

enum SessionState: String, Codable {
    case active, blocked, idle, completed, stale
}

struct Session: Identifiable {
    let id: String
    let projectName: String
    let projectPath: String
    var sessionTitle: String?
    var state: SessionState = .active
    var lastEvent: Date = Date()
    var lastTool: String?
    var lastToolSummary: String?
    var pendingAction: PendingAction?
    var terminal: TerminalInfo?
    var pid: Int32?

    mutating func handleEvent(type: BobberEvent.EventType) {
        lastEvent = Date()
        switch type {
        case .permissionPrompt, .elicitationDialog:
            state = .blocked
        case .preToolUse, .userPromptSubmit, .sessionStart:
            state = .active
            pendingAction = nil
        case .stop, .taskCompleted:
            state = .idle
        case .sessionEnd:
            state = .completed
        case .idlePrompt:
            state = .idle
        case .notification:
            break  // Don't change state on notifications
        }
    }
}
```

```swift
// Sources/Bobber/Models/PendingAction.swift
import Foundation

enum ActionType: String, Codable {
    case permission, decision, completion
}

struct PendingAction: Identifiable {
    let id: String
    let sessionId: String
    let type: ActionType
    let timestamp: Date
    let tool: String?
    let command: String?
    let description: String?
    let question: String?
    let options: [EventOption]?
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: All model tests pass

**Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add core data models (BobberEvent, Session, PendingAction)"
```

---

### Task 3: Session Manager (State Management)

**Files:**
- Create: `Sources/Bobber/Services/SessionManager.swift`
- Create: `Tests/BobberTests/SessionManagerTests.swift`

**Step 1: Write failing tests**

```swift
// Tests/BobberTests/SessionManagerTests.swift
import XCTest
@testable import Bobber

final class SessionManagerTests: XCTestCase {
    func testNewEventCreatesSession() {
        let manager = SessionManager()
        let event = makeEvent(sessionId: "s1", type: .sessionStart, projectName: "test")

        manager.handleEvent(event)

        XCTAssertEqual(manager.sessions.count, 1)
        XCTAssertEqual(manager.sessions.first?.projectName, "test")
    }

    func testPermissionEventCreatesAction() {
        let manager = SessionManager()
        let event = makeEvent(
            sessionId: "s1",
            type: .permissionPrompt,
            projectName: "test",
            tool: "Bash",
            command: "pnpm test"
        )

        manager.handleEvent(event)

        XCTAssertEqual(manager.pendingActions.count, 1)
        XCTAssertEqual(manager.pendingActions.first?.type, .permission)
        XCTAssertEqual(manager.sessions.first?.state, .blocked)
    }

    func testToolUseEventClearsBlockedState() {
        let manager = SessionManager()
        manager.handleEvent(makeEvent(sessionId: "s1", type: .permissionPrompt, projectName: "test"))
        manager.handleEvent(makeEvent(sessionId: "s1", type: .preToolUse, projectName: "test"))

        XCTAssertEqual(manager.sessions.first?.state, .active)
    }

    func testStaleSessionDetection() {
        let manager = SessionManager()
        manager.handleEvent(makeEvent(sessionId: "s1", type: .sessionStart, projectName: "test"))
        // Simulate old timestamp
        manager.sessions[0].lastEvent = Date().addingTimeInterval(-31 * 60)

        manager.cleanupSessions()

        XCTAssertEqual(manager.sessions.first?.state, .stale)
    }

    // Helper
    private func makeEvent(
        sessionId: String,
        type: BobberEvent.EventType,
        projectName: String,
        tool: String? = nil,
        command: String? = nil
    ) -> BobberEvent {
        BobberEvent(
            version: 1,
            timestamp: Date(),
            pid: 12345,
            sessionId: sessionId,
            projectPath: "/tmp/\(projectName)",
            projectName: projectName,
            sessionTitle: nil,
            eventType: type,
            details: tool != nil ? EventDetails(
                tool: tool, command: command, description: nil,
                question: nil, options: nil, message: nil
            ) : nil,
            terminal: nil
        )
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | head -20`
Expected: FAIL — SessionManager doesn't exist

**Step 3: Implement SessionManager**

```swift
// Sources/Bobber/Services/SessionManager.swift
import Foundation
import Combine

@MainActor
class SessionManager: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var pendingActions: [PendingAction] = []

    private let staleTimeout: TimeInterval = 30 * 60  // 30 minutes

    func handleEvent(_ event: BobberEvent) {
        if let index = sessions.firstIndex(where: { $0.id == event.sessionId }) {
            sessions[index].handleEvent(type: event.eventType)
            sessions[index].terminal = event.terminal ?? sessions[index].terminal
            sessions[index].pid = event.pid
            if let tool = event.details?.tool {
                sessions[index].lastTool = tool
                sessions[index].lastToolSummary = toolSummary(from: event.details)
            }
        } else {
            var session = Session(
                id: event.sessionId,
                projectName: event.projectName,
                projectPath: event.projectPath,
                sessionTitle: event.sessionTitle
            )
            session.handleEvent(type: event.eventType)
            session.terminal = event.terminal
            session.pid = event.pid
            sessions.append(session)
        }

        // Create pending action for blocking events
        switch event.eventType {
        case .permissionPrompt:
            let action = PendingAction(
                id: UUID().uuidString,
                sessionId: event.sessionId,
                type: .permission,
                timestamp: event.timestamp,
                tool: event.details?.tool,
                command: event.details?.command,
                description: event.details?.description,
                question: nil,
                options: event.details?.options
            )
            pendingActions.append(action)

        case .elicitationDialog:
            let action = PendingAction(
                id: UUID().uuidString,
                sessionId: event.sessionId,
                type: .decision,
                timestamp: event.timestamp,
                tool: nil,
                command: nil,
                description: nil,
                question: event.details?.question,
                options: event.details?.options
            )
            pendingActions.append(action)

        case .idlePrompt, .taskCompleted:
            let action = PendingAction(
                id: UUID().uuidString,
                sessionId: event.sessionId,
                type: .completion,
                timestamp: event.timestamp,
                tool: event.details?.tool,
                command: nil,
                description: event.details?.message,
                question: nil,
                options: nil
            )
            pendingActions.append(action)

        case .preToolUse, .userPromptSubmit, .sessionStart:
            // Clear pending actions for this session (user/agent resumed)
            pendingActions.removeAll { $0.sessionId == event.sessionId }

        default:
            break
        }
    }

    func resolveAction(_ actionId: String) {
        pendingActions.removeAll { $0.id == actionId }
    }

    func cleanupSessions() {
        let now = Date()
        for i in sessions.indices {
            // PID liveness check
            if let pid = sessions[i].pid, kill(pid, 0) != 0 {
                sessions[i].state = .completed
                continue
            }
            // Stale timeout
            if now.timeIntervalSince(sessions[i].lastEvent) > staleTimeout
                && sessions[i].state != .completed {
                sessions[i].state = .stale
            }
        }
        // Remove sessions that have been completed for >5 minutes
        sessions.removeAll { session in
            session.state == .completed
            && now.timeIntervalSince(session.lastEvent) > 300
        }
    }

    private func toolSummary(from details: EventDetails?) -> String? {
        guard let details else { return nil }
        switch details.tool {
        case "Bash":
            return "$ \(details.command?.prefix(60) ?? "")"
        case "Edit", "Read", "Write":
            return details.command ?? details.description
        case "Grep", "Glob":
            return details.description?.prefix(40).map(String.init) ?? details.tool
        default:
            return details.tool
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: All tests pass

**Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add SessionManager with state management and cleanup"
```

---

## Phase 2: IPC Layer (Event Capture)

### Task 4: Event File Watcher (FSEvents)

**Files:**
- Create: `Sources/Bobber/Services/EventFileWatcher.swift`
- Create: `Tests/BobberTests/EventFileWatcherTests.swift`

**Step 1: Write failing test**

```swift
// Tests/BobberTests/EventFileWatcherTests.swift
import XCTest
@testable import Bobber

final class EventFileWatcherTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bobber-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testParseEventFile() throws {
        let json = """
        {"version":1,"timestamp":"2026-03-02T10:30:00Z","pid":123,
         "sessionId":"s1","projectPath":"/tmp/test","projectName":"test",
         "eventType":"session_start"}
        """
        let file = tempDir.appendingPathComponent("1709-123.json")
        try json.write(to: file, atomically: true, encoding: .utf8)

        let event = try EventFileWatcher.parseEventFile(at: file)
        XCTAssertEqual(event.sessionId, "s1")
        XCTAssertEqual(event.eventType, .sessionStart)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter EventFileWatcherTests`
Expected: FAIL — EventFileWatcher doesn't exist

**Step 3: Implement EventFileWatcher**

```swift
// Sources/Bobber/Services/EventFileWatcher.swift
import Foundation

class EventFileWatcher {
    private let eventsDir: URL
    private let onChange: (BobberEvent) -> Void
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var fallbackTimer: Timer?
    private var processedFiles: Set<String> = []

    init(eventsDir: URL = defaultEventsDir, onChange: @escaping (BobberEvent) -> Void) {
        self.eventsDir = eventsDir
        self.onChange = onChange
    }

    static var defaultEventsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bobber/events")
    }

    func start() throws {
        // Ensure directory exists
        try FileManager.default.createDirectory(at: eventsDir, withIntermediateDirectories: true)

        // Primary: DispatchSource file system watcher
        let fd = open(eventsDir.path, O_EVTONLY)
        guard fd >= 0 else { throw BobberError.cannotWatchDirectory(eventsDir.path) }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.scanForNewEvents() }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        self.dispatchSource = source

        // Fallback: 2-second polling timer
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.scanForNewEvents()
        }

        // Process any existing files
        scanForNewEvents()
    }

    func stop() {
        dispatchSource?.cancel()
        dispatchSource = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    private func scanForNewEvents() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: eventsDir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let jsonFiles = files.filter { $0.pathExtension == "json" }
            .sorted { ($0.lastPathComponent) < ($1.lastPathComponent) }

        for file in jsonFiles {
            let name = file.lastPathComponent
            guard !processedFiles.contains(name) else { continue }
            processedFiles.insert(name)

            do {
                let event = try Self.parseEventFile(at: file)
                onChange(event)
                // Delete processed file
                try? FileManager.default.removeItem(at: file)
            } catch {
                // Skip malformed files, remove after 1 minute
            }
        }
    }

    static func parseEventFile(at url: URL) throws -> BobberEvent {
        let data = try Data(contentsOf: url)
        return try JSONDecoder.bobber.decode(BobberEvent.self, from: data)
    }
}

enum BobberError: Error {
    case cannotWatchDirectory(String)
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter EventFileWatcherTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add EventFileWatcher with FSEvents + polling fallback"
```

---

### Task 5: Unix Socket Permission Server

**Files:**
- Create: `Sources/Bobber/Services/PermissionServer.swift`
- Create: `Tests/BobberTests/PermissionServerTests.swift`

**Step 1: Write failing test**

```swift
// Tests/BobberTests/PermissionServerTests.swift
import XCTest
@testable import Bobber

final class PermissionServerTests: XCTestCase {
    func testServerStartsAndAcceptsConnection() async throws {
        let socketPath = "/tmp/bobber-test-\(UUID().uuidString).sock"
        defer { unlink(socketPath) }

        let server = PermissionServer(socketPath: socketPath)
        try server.start()

        // Connect as a client
        let clientFd = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThan(clientFd, 0)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { cstr in
                _ = strcpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), cstr)
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(clientFd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(connectResult, 0, "Client should connect to server")

        Darwin.close(clientFd)
        server.stop()
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter PermissionServerTests`
Expected: FAIL — PermissionServer doesn't exist

**Step 3: Implement PermissionServer**

```swift
// Sources/Bobber/Services/PermissionServer.swift
import Foundation

class PermissionServer {
    let socketPath: String
    private var serverFd: Int32 = -1
    private var dispatchSource: DispatchSourceRead?
    private var pendingClients: [String: Int32] = [:]  // sessionId -> fd
    var onPermissionRequest: ((String, BobberEvent) -> Void)?  // (sessionId, event)

    init(socketPath: String = "/tmp/bobber.sock") {
        self.socketPath = socketPath
    }

    func start() throws {
        // Remove stale socket
        unlink(socketPath)

        serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else { throw BobberError.cannotCreateSocket }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { cstr in
                _ = strcpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), cstr)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(serverFd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { throw BobberError.cannotBindSocket }

        guard Darwin.listen(serverFd, 5) == 0 else { throw BobberError.cannotListenSocket }

        // Non-blocking accept via GCD
        let source = DispatchSource.makeReadSource(fileDescriptor: serverFd, queue: .main)
        source.setEventHandler { [weak self] in self?.acceptClient() }
        source.setCancelHandler { [weak self] in
            if let fd = self?.serverFd, fd >= 0 { Darwin.close(fd) }
        }
        source.resume()
        self.dispatchSource = source
    }

    func stop() {
        dispatchSource?.cancel()
        dispatchSource = nil
        for (_, fd) in pendingClients { Darwin.close(fd) }
        pendingClients.removeAll()
        unlink(socketPath)
    }

    func respond(sessionId: String, decision: PermissionDecision) {
        guard let fd = pendingClients.removeValue(forKey: sessionId) else { return }
        let json: String
        switch decision {
        case .allow:
            json = #"{"behavior":"allow"}"#
        case .allowForProject:
            json = #"{"behavior":"allow","remember":"project"}"#
        case .deny:
            json = #"{"behavior":"deny","message":"Denied from Bobber"}"#
        case .custom(let message):
            let escaped = message.replacingOccurrences(of: "\"", with: "\\\"")
            json = #"{"behavior":"deny","message":"\#(escaped)"}"#
        }
        let data = json.data(using: .utf8)!
        data.withUnsafeBytes { buffer in
            _ = Darwin.write(fd, buffer.baseAddress!, buffer.count)
        }
        Darwin.close(fd)
    }

    private func acceptClient() {
        let clientFd = Darwin.accept(serverFd, nil, nil)
        guard clientFd >= 0 else { return }

        // Read data from client on background queue
        DispatchQueue.global().async { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 65536)
            let bytesRead = Darwin.read(clientFd, &buffer, buffer.count)
            guard bytesRead > 0 else {
                Darwin.close(clientFd)
                return
            }

            let data = Data(bytes: buffer, count: bytesRead)
            guard let event = try? JSONDecoder.bobber.decode(BobberEvent.self, from: data) else {
                Darwin.close(clientFd)
                return
            }

            DispatchQueue.main.async {
                self?.pendingClients[event.sessionId] = clientFd
                self?.onPermissionRequest?(event.sessionId, event)
            }
        }
    }
}

enum PermissionDecision {
    case allow
    case allowForProject
    case deny
    case custom(String)
}

extension BobberError {
    static let cannotCreateSocket = BobberError.cannotWatchDirectory("socket creation failed")
    static let cannotBindSocket = BobberError.cannotWatchDirectory("socket bind failed")
    static let cannotListenSocket = BobberError.cannotWatchDirectory("socket listen failed")
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter PermissionServerTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add PermissionServer with Unix domain socket IPC"
```

---

## Phase 3: UI — Floating Panel

### Task 6: FloatingPanel (NSPanel)

**Files:**
- Create: `Sources/Bobber/UI/FloatingPanel.swift`
- Create: `Sources/Bobber/UI/ClickHostingView.swift`

**Step 1: Implement FloatingPanel**

```swift
// Sources/Bobber/UI/FloatingPanel.swift
import AppKit
import SwiftUI

class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentView: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true

        // Glass effect background
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active

        let hostingView = ClickHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        visualEffect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])

        self.contentView = visualEffect
    }
}
```

```swift
// Sources/Bobber/UI/ClickHostingView.swift
import AppKit
import SwiftUI

class ClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
```

**Step 2: Build to verify compilation**

Run: `swift build`
Expected: Compiles without errors

**Step 3: Commit**

```bash
git add Sources/
git commit -m "feat: add FloatingPanel with glass effect and click-through"
```

---

### Task 7: PanelController (Show/Hide/Position)

**Files:**
- Create: `Sources/Bobber/UI/PanelController.swift`

**Step 1: Implement PanelController**

```swift
// Sources/Bobber/UI/PanelController.swift
import AppKit
import SwiftUI

class PanelController {
    private var panel: FloatingPanel?
    private let sessionManager: SessionManager

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            let contentView = PanelContentView(sessionManager: sessionManager)
            panel = FloatingPanel(contentView: contentView)
            restorePosition()
        }
        panel?.makeKeyAndOrderFront(nil)

        // Save position on move
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in self?.savePosition() }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func savePosition() {
        guard let frame = panel?.frame else { return }
        UserDefaults.standard.set(frame.origin.x, forKey: "bobber.panel.x")
        UserDefaults.standard.set(frame.origin.y, forKey: "bobber.panel.y")
    }

    private func restorePosition() {
        let x = UserDefaults.standard.double(forKey: "bobber.panel.x")
        let y = UserDefaults.standard.double(forKey: "bobber.panel.y")
        if x != 0 || y != 0 {
            panel?.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel?.center()
        }
    }
}
```

**Step 2: Build to verify compilation**

Run: `swift build`
Expected: Compiles (PanelContentView placeholder needed — created in next task)

**Step 3: Commit**

```bash
git add Sources/
git commit -m "feat: add PanelController with position persistence"
```

---

### Task 8: Sessions Tab UI

**Files:**
- Create: `Sources/Bobber/UI/PanelContentView.swift`
- Create: `Sources/Bobber/UI/SessionRowView.swift`

**Step 1: Implement PanelContentView with tab switching**

```swift
// Sources/Bobber/UI/PanelContentView.swift
import SwiftUI

struct PanelContentView: View {
    @ObservedObject var sessionManager: SessionManager
    @State private var selectedTab: PanelTab = .sessions

    enum PanelTab {
        case sessions, actions
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack {
                TabButton(title: "Sessions", isSelected: selectedTab == .sessions) {
                    selectedTab = .sessions
                }
                TabButton(
                    title: "Actions",
                    badge: sessionManager.pendingActions.count,
                    isSelected: selectedTab == .actions
                ) {
                    selectedTab = .actions
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Content
            switch selectedTab {
            case .sessions:
                SessionsListView(sessionManager: sessionManager)
            case .actions:
                ActionsListView(sessionManager: sessionManager)
            }
        }
        .frame(width: 340, minHeight: 200, maxHeight: 600)
    }
}

struct TabButton: View {
    let title: String
    var badge: Int = 0
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .fontWeight(isSelected ? .semibold : .regular)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.red))
                }
            }
            .foregroundColor(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
```

```swift
// Sources/Bobber/UI/SessionRowView.swift
import SwiftUI

struct SessionsListView: View {
    @ObservedObject var sessionManager: SessionManager

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(sessionManager.sessions) { session in
                    SessionRowView(session: session)
                }
            }
            .padding(8)
        }
    }
}

struct SessionRowView: View {
    let session: Session

    var body: some View {
        HStack(spacing: 10) {
            // Status dot
            Circle()
                .fill(session.state.color)
                .frame(width: 10, height: 10)

            // Project info
            VStack(alignment: .leading, spacing: 2) {
                Text(session.projectName)
                    .font(.system(.body, design: .rounded, weight: .medium))
                Text(session.statusDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Time since last event
            Text(session.lastEvent.relativeDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

extension SessionState {
    var color: Color {
        switch self {
        case .active: return .green
        case .blocked: return .red
        case .idle: return .yellow
        case .completed: return .gray
        case .stale: return .gray.opacity(0.5)
        }
    }
}

extension Session {
    var statusDescription: String {
        switch state {
        case .active:
            return lastToolSummary ?? "Working..."
        case .blocked:
            if let tool = pendingAction?.tool {
                return "⏳ Permission: \(tool)"
            }
            return "⏳ Waiting for input"
        case .idle:
            return "💤 Idle"
        case .completed:
            return "Done"
        case .stale:
            return "Stale"
        }
    }
}

extension Date {
    var relativeDescription: String {
        let interval = -self.timeIntervalSinceNow
        if interval < 5 { return "now" }
        if interval < 60 { return "\(Int(interval))s" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        return "\(Int(interval / 3600))h"
    }
}
```

**Step 2: Build and run to visually verify**

Run: `swift build && swift run`
Expected: Floating panel appears with Sessions tab (empty list if no events)

**Step 3: Commit**

```bash
git add Sources/
git commit -m "feat: add Sessions tab with session row cards"
```

---

### Task 9: Actions Tab UI (Permission, Decision, Completion Cards)

**Files:**
- Create: `Sources/Bobber/UI/ActionsListView.swift`
- Create: `Sources/Bobber/UI/PermissionCardView.swift`
- Create: `Sources/Bobber/UI/DecisionCardView.swift`
- Create: `Sources/Bobber/UI/CompletionCardView.swift`

**Step 1: Implement ActionsListView with card stack navigation**

```swift
// Sources/Bobber/UI/ActionsListView.swift
import SwiftUI

struct ActionsListView: View {
    @ObservedObject var sessionManager: SessionManager
    @State private var currentIndex: Int = 0

    var body: some View {
        if sessionManager.pendingActions.isEmpty {
            VStack(spacing: 8) {
                Text("No pending actions")
                    .foregroundColor(.secondary)
                Text("All clear!")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                // Header with navigation
                HStack {
                    let action = sessionManager.pendingActions[safeIndex]
                    let session = sessionManager.sessions.first { $0.id == action.sessionId }
                    VStack(alignment: .leading) {
                        Text(session?.projectName ?? "Unknown")
                            .font(.headline)
                        if let title = session?.sessionTitle {
                            Text(title)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        Button("←") { navigate(-1) }
                            .buttonStyle(.plain)
                            .disabled(sessionManager.pendingActions.count <= 1)
                        Text("\(safeIndex + 1)/\(sessionManager.pendingActions.count)")
                            .font(.caption)
                            .monospacedDigit()
                        Button("→") { navigate(1) }
                            .buttonStyle(.plain)
                            .disabled(sessionManager.pendingActions.count <= 1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                // Card
                let action = sessionManager.pendingActions[safeIndex]
                switch action.type {
                case .permission:
                    PermissionCardView(action: action) { decision in
                        sessionManager.resolveAction(action.id)
                    }
                case .decision:
                    DecisionCardView(action: action) { choice in
                        sessionManager.resolveAction(action.id)
                    }
                case .completion:
                    CompletionCardView(action: action) {
                        sessionManager.resolveAction(action.id)
                    }
                }

                Spacer()
            }
        }
    }

    private var safeIndex: Int {
        min(currentIndex, max(0, sessionManager.pendingActions.count - 1))
    }

    private func navigate(_ delta: Int) {
        let count = sessionManager.pendingActions.count
        guard count > 0 else { return }
        currentIndex = (currentIndex + delta + count) % count
    }
}
```

**Step 2: Implement PermissionCardView**

```swift
// Sources/Bobber/UI/PermissionCardView.swift
import SwiftUI

struct PermissionCardView: View {
    let action: PendingAction
    let onDecision: (PermissionDecision) -> Void
    @State private var isEditing: Bool = false
    @State private var editedCommand: String = ""
    @State private var customMessage: String = ""
    @State private var showCustomInput: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Allow this \(action.tool ?? "tool") command?")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Command display / editor
            if let command = action.command {
                if isEditing {
                    TextEditor(text: $editedCommand)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 60, maxHeight: 100)
                        .cornerRadius(6)
                } else {
                    Text(command)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(6)
                }
            }

            if let desc = action.description {
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Edit command button
            Button(isEditing ? "Done editing" : "Edit command...") {
                if !isEditing { editedCommand = action.command ?? "" }
                isEditing.toggle()
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundColor(.blue)

            // Action buttons
            VStack(spacing: 6) {
                ActionButton(label: "Yes", icon: "checkmark.circle.fill", color: .green) {
                    onDecision(.allow)
                }
                ActionButton(label: "Yes, for this project", icon: "folder.fill", color: .blue) {
                    onDecision(.allowForProject)
                }
                ActionButton(label: "No", icon: "xmark.circle.fill", color: .red) {
                    onDecision(.deny)
                }
                if showCustomInput {
                    HStack {
                        TextField("Tell Claude what to do instead...", text: $customMessage)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                        Button("Send") {
                            onDecision(.custom(customMessage))
                        }
                        .disabled(customMessage.isEmpty)
                    }
                } else {
                    ActionButton(label: "Tell Claude instead...", icon: "text.bubble.fill", color: .orange) {
                        showCustomInput = true
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
        .padding(.horizontal, 12)
    }
}

struct ActionButton: View {
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(label)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}
```

**Step 3: Implement DecisionCardView**

```swift
// Sources/Bobber/UI/DecisionCardView.swift
import SwiftUI

struct DecisionCardView: View {
    let action: PendingAction
    let onChoice: (String) -> Void
    @State private var customText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let question = action.question {
                Text(question)
                    .font(.subheadline)
            }

            if let options = action.options {
                ForEach(options) { option in
                    Button(action: { onChoice(option.key) }) {
                        HStack {
                            Text(option.label)
                            Spacer()
                            if let desc = option.description {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.blue.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Custom "Other" input
            HStack {
                TextField("Other...", text: $customText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                Button("Send") {
                    onChoice(customText)
                }
                .disabled(customText.isEmpty)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
        .padding(.horizontal, 12)
    }
}
```

**Step 4: Implement CompletionCardView**

```swift
// Sources/Bobber/UI/CompletionCardView.swift
import SwiftUI

struct CompletionCardView: View {
    let action: PendingAction
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Task completed")
                    .font(.subheadline.bold())
            }

            if let desc = action.description {
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: onDismiss) {
                HStack {
                    Image(systemName: "eye.fill")
                    Text("Mark as read")
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
        .padding(.horizontal, 12)
    }
}
```

**Step 5: Build and run to visually verify**

Run: `swift build && swift run`
Expected: Actions tab shows "No pending actions" when empty, cards render correctly for each type

**Step 6: Commit**

```bash
git add Sources/
git commit -m "feat: add Actions tab with Permission, Decision, and Completion cards"
```

---

## Phase 4: Menubar Icon & Keyboard Gesture

### Task 10: Menubar Icon with Badge and Color States

**Files:**
- Modify: `Sources/Bobber/AppDelegate.swift`
- Create: `Sources/Bobber/UI/MenubarIconManager.swift`

**Step 1: Implement MenubarIconManager**

```swift
// Sources/Bobber/UI/MenubarIconManager.swift
import AppKit
import Combine

class MenubarIconManager {
    private let statusItem: NSStatusItem
    private let sessionManager: SessionManager
    private var cancellable: AnyCancellable?

    init(statusItem: NSStatusItem, sessionManager: SessionManager) {
        self.statusItem = statusItem
        self.sessionManager = sessionManager

        cancellable = sessionManager.$pendingActions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] actions in
                self?.updateIcon(pendingCount: actions.count)
            }
    }

    private func updateIcon(pendingCount: Int) {
        guard let button = statusItem.button else { return }

        let symbolName: String
        let tintColor: NSColor

        if pendingCount > 0 {
            symbolName = "circle.fill"
            tintColor = .systemRed
        } else if sessionManager.sessions.contains(where: { $0.state == .active }) {
            symbolName = "circle.fill"
            tintColor = .systemGreen
        } else {
            symbolName = "circle"
            tintColor = .secondaryLabelColor
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Bobber")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        button.image = image
        button.contentTintColor = tintColor

        // Badge count
        if pendingCount > 0 {
            button.title = " \(pendingCount)"
        } else {
            button.title = ""
        }
    }
}
```

**Step 2: Build to verify**

Run: `swift build`
Expected: Compiles without errors

**Step 3: Commit**

```bash
git add Sources/
git commit -m "feat: add menubar icon with badge count and color states"
```

---

### Task 11: Keyboard Gesture (Option+B)

**Files:**
- Create: `Sources/Bobber/Services/HotkeyManager.swift`

**Step 1: Implement HotkeyManager**

```swift
// Sources/Bobber/Services/HotkeyManager.swift
import AppKit

class HotkeyManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    var onTogglePanel: (() -> Void)?
    var onJumpToSession: ((Int) -> Void)?

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyDown(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyDown(event)
            return event
        }
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        // Option+B → toggle panel
        if event.modifierFlags.contains(.option)
            && event.charactersIgnoringModifiers == "b" {
            onTogglePanel?()
            return
        }

        // Number keys 1-9 (no modifier) → jump to session
        if event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
           let char = event.charactersIgnoringModifiers,
           let digit = Int(char),
           digit >= 1 && digit <= 9 {
            onJumpToSession?(digit - 1)
        }

        // Escape → hide panel
        if event.keyCode == 53 {  // Escape
            onTogglePanel?()
        }
    }
}
```

**Step 2: Build to verify**

Run: `swift build`
Expected: Compiles without errors

**Step 3: Commit**

```bash
git add Sources/
git commit -m "feat: add keyboard gesture support (Option+B toggle, 1-9 jump)"
```

---

## Phase 5: Sound System

### Task 12: Sound Alerts

**Files:**
- Create: `Sources/Bobber/Services/SoundManager.swift`

**Step 1: Write failing test**

```swift
// Tests/BobberTests/SoundManagerTests.swift
import XCTest
@testable import Bobber

final class SoundManagerTests: XCTestCase {
    func testCooldownPreventsRapidSounds() {
        let manager = SoundManager()
        manager.enabled = true
        manager.cooldownSeconds = 3

        XCTAssertTrue(manager.shouldPlay())
        manager.recordPlay()
        XCTAssertFalse(manager.shouldPlay())
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter SoundManagerTests`
Expected: FAIL

**Step 3: Implement SoundManager**

```swift
// Sources/Bobber/Services/SoundManager.swift
import Foundation
import AVFoundation

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
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter SoundManagerTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add SoundManager with cooldown and per-event sounds"
```

---

## Phase 6: Window Jumping

### Task 13: Terminal Detection & Window Jumping

**Files:**
- Create: `Sources/Bobber/Services/WindowJumper.swift`

**Step 1: Implement WindowJumper**

```swift
// Sources/Bobber/Services/WindowJumper.swift
import AppKit

class WindowJumper {
    func jumpToSession(_ session: Session) {
        guard let terminal = session.terminal else { return }

        // tmux takes priority
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
            // VS Code, JetBrains, or unknown — activate by bundle ID
            if let bundleId = terminal.bundleId {
                activateByBundleId(bundleId)
            }
        }
    }

    private func jumpToITerm2(sessionId: String) {
        let script = """
        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if unique id of s is "\(sessionId)" then
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
                    if tty of t is "\(ttyPath)" then
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
```

**Step 2: Build to verify**

Run: `swift build`
Expected: Compiles without errors

**Step 3: Commit**

```bash
git add Sources/
git commit -m "feat: add WindowJumper with iTerm2, Terminal.app, tmux, and generic support"
```

---

## Phase 7: Claude Code Plugin (Hook Scripts)

### Task 14: Plugin Structure & Event Hook Script

**Files:**
- Create: `plugins/claude-bobber-plugin/.claude-plugin/plugin.json`
- Create: `plugins/claude-bobber-plugin/hooks/hooks.json`
- Create: `plugins/claude-bobber-plugin/scripts/bobber-event.sh`

**Step 1: Create plugin.json**

```json
{
  "name": "bobber-claude",
  "version": "1.0.0",
  "description": "Session monitoring hooks for Bobber",
  "author": { "name": "Bobber" },
  "license": "MIT",
  "keywords": ["bobber", "monitoring", "hooks", "session"]
}
```

**Step 2: Create hooks.json**

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/bobber-event.sh\" SessionStart" }] }
    ],
    "PreToolUse": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/bobber-event.sh\" PreToolUse" }] }
    ],
    "PermissionRequest": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/bobber-permission.sh\"" }] }
    ],
    "Notification": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/bobber-event.sh\" Notification" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/bobber-event.sh\" Stop" }] }
    ],
    "TaskCompleted": [
      { "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/bobber-event.sh\" TaskCompleted" }] }
    ],
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/bobber-event.sh\" UserPromptSubmit" }] }
    ],
    "SessionEnd": [
      { "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/bobber-event.sh\" SessionEnd" }] }
    ]
  }
}
```

**Step 3: Create bobber-event.sh**

```bash
#!/usr/bin/env bash
# bobber-event.sh — Async event capture for Bobber
# Receives JSON from Claude Code on stdin, writes to ~/.bobber/events/
set -euo pipefail

EVENT_TYPE="${1:-unknown}"
EVENTS_DIR="${HOME}/.bobber/events"
SOCKET_PATH="/tmp/bobber.sock"

# Ensure events directory exists
mkdir -p "$EVENTS_DIR"

# Read hook data from stdin
INPUT=$(cat)

# Detect terminal
detect_terminal() {
    # iTerm2 fast path
    if [ -n "${ITERM_SESSION_ID:-}" ]; then
        echo "iterm2" "${ITERM_SESSION_ID}"
        return
    fi

    # Walk process tree
    local pid=$$
    for _ in 1 2 3 4 5; do
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        [ -z "$pid" ] || [ "$pid" = "1" ] && break
        local comm
        comm=$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' ')
        case "$comm" in
            *iTerm2*)    echo "iterm2" ""; return ;;
            *Terminal*)  echo "terminal" "$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')"; return ;;
            *ghostty*)   echo "ghostty" ""; return ;;
            *kitty*)     echo "kitty" ""; return ;;
            *Electron*)  echo "vscode" ""; return ;;
            *idea*|*webstorm*|*pycharm*) echo "jetbrains" ""; return ;;
        esac
    done

    # tmux detection
    if [ -n "${TMUX:-}" ]; then
        local ppid_tty
        ppid_tty=$(ps -p "$PPID" -o tty= 2>/dev/null | tr -d ' ')
        local tmux_target
        tmux_target=$(tmux list-panes -a -F '#{pane_tty} #{session_name}:#{window_index}.#{pane_index}' 2>/dev/null \
            | grep "$ppid_tty" | head -1 | awk '{print $2}')
        if [ -n "$tmux_target" ]; then
            echo "tmux" "$tmux_target"
            return
        fi
    fi

    echo "unknown" ""
}

# Extract tool summary
tool_summary() {
    local tool_name
    tool_name=$(echo "$INPUT" | jq -r '.tool_name // .tool // empty' 2>/dev/null)
    local tool_input
    tool_input=$(echo "$INPUT" | jq -r '.tool_input // empty' 2>/dev/null)

    case "$tool_name" in
        Bash)    echo "$ $(echo "$tool_input" | jq -r '.command // ""' 2>/dev/null | head -c 60)" ;;
        Edit)    echo "$(echo "$tool_input" | jq -r '.file_path // ""' 2>/dev/null)" ;;
        Write)   echo "$(echo "$tool_input" | jq -r '.file_path // ""' 2>/dev/null)" ;;
        Read)    echo "$(echo "$tool_input" | jq -r '.file_path // ""' 2>/dev/null)" ;;
        Grep)    echo "grep: $(echo "$tool_input" | jq -r '.pattern // ""' 2>/dev/null | head -c 40)" ;;
        Glob)    echo "glob: $(echo "$tool_input" | jq -r '.pattern // ""' 2>/dev/null | head -c 40)" ;;
        *)       echo "$tool_name" ;;
    esac
}

# Build event JSON
read -r TERM_APP TERM_ID <<< "$(detect_terminal)"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID="${CLAUDE_SESSION_ID:-$$-$(basename "${PWD}")}"
PROJECT_PATH="${PWD}"
PROJECT_NAME="$(basename "${PWD}")"

# Map hook event types to Bobber event types
case "$EVENT_TYPE" in
    SessionStart)      BOBBER_TYPE="session_start" ;;
    PreToolUse)        BOBBER_TYPE="pre_tool_use" ;;
    Notification)      BOBBER_TYPE="notification" ;;
    Stop)              BOBBER_TYPE="stop" ;;
    TaskCompleted)     BOBBER_TYPE="task_completed" ;;
    UserPromptSubmit)  BOBBER_TYPE="user_prompt_submit" ;;
    SessionEnd)        BOBBER_TYPE="session_end" ;;
    *)                 BOBBER_TYPE="$EVENT_TYPE" ;;
esac

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // .tool // empty' 2>/dev/null)
SUMMARY=$(tool_summary)

EVENT_JSON=$(jq -n \
    --arg version "1" \
    --arg timestamp "$TIMESTAMP" \
    --arg pid "$$" \
    --arg sessionId "$SESSION_ID" \
    --arg projectPath "$PROJECT_PATH" \
    --arg projectName "$PROJECT_NAME" \
    --arg eventType "$BOBBER_TYPE" \
    --arg tool "$TOOL_NAME" \
    --arg summary "$SUMMARY" \
    --arg termApp "$TERM_APP" \
    --arg termId "$TERM_ID" \
    '{
        version: ($version | tonumber),
        timestamp: $timestamp,
        pid: ($pid | tonumber),
        sessionId: $sessionId,
        projectPath: $projectPath,
        projectName: $projectName,
        eventType: $eventType,
        details: { tool: $tool, description: $summary },
        terminal: { app: $termApp, tabId: $termId }
    }')

# Atomic write to events directory
TEMP=$(mktemp "${EVENTS_DIR}/.tmp.XXXXXX")
trap 'rm -f "$TEMP"' EXIT
echo "$EVENT_JSON" > "$TEMP"
mv "$TEMP" "${EVENTS_DIR}/${TIMESTAMP//[:-]/}-$$.json"

# Signal Bobber daemon if socket exists
if [ -S "$SOCKET_PATH" ]; then
    echo "ping" | nc -U "$SOCKET_PATH" -w 1 2>/dev/null || true
fi
```

**Step 4: Make script executable and test**

Run: `chmod +x plugins/claude-bobber-plugin/scripts/bobber-event.sh`
Run: `echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | plugins/claude-bobber-plugin/scripts/bobber-event.sh PreToolUse && ls ~/.bobber/events/*.json | head -1 && cat $(ls -t ~/.bobber/events/*.json | head -1)`
Expected: Event JSON file created in ~/.bobber/events/

**Step 5: Commit**

```bash
git add plugins/
git commit -m "feat: add Claude Code plugin with async event hook script"
```

---

### Task 15: Permission Hook Script (Blocking Socket IPC)

**Files:**
- Create: `plugins/claude-bobber-plugin/scripts/bobber-permission.sh`

**Step 1: Create bobber-permission.sh**

```bash
#!/usr/bin/env bash
# bobber-permission.sh — Sync permission handler for Bobber
# Connects to Bobber daemon via Unix socket, blocks until user decides.
# If Bobber is not running, exits cleanly (falls back to Claude's native dialog).
set -euo pipefail

SOCKET_PATH="/tmp/bobber.sock"

# If Bobber isn't running, exit cleanly → Claude shows its native dialog
if [ ! -S "$SOCKET_PATH" ]; then
    exit 0
fi

# Read permission request from stdin
INPUT=$(cat)

# Detect terminal (same logic as bobber-event.sh)
detect_terminal() {
    if [ -n "${ITERM_SESSION_ID:-}" ]; then
        echo "iterm2" "${ITERM_SESSION_ID}"
        return
    fi
    local pid=$$
    for _ in 1 2 3 4 5; do
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        [ -z "$pid" ] || [ "$pid" = "1" ] && break
        local comm
        comm=$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' ')
        case "$comm" in
            *iTerm2*)    echo "iterm2" ""; return ;;
            *Terminal*)  echo "terminal" "$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')"; return ;;
            *ghostty*)   echo "ghostty" ""; return ;;
            *kitty*)     echo "kitty" ""; return ;;
            *Electron*)  echo "vscode" ""; return ;;
            *idea*|*webstorm*|*pycharm*) echo "jetbrains" ""; return ;;
        esac
    done
    if [ -n "${TMUX:-}" ]; then
        local ppid_tty
        ppid_tty=$(ps -p "$PPID" -o tty= 2>/dev/null | tr -d ' ')
        local tmux_target
        tmux_target=$(tmux list-panes -a -F '#{pane_tty} #{session_name}:#{window_index}.#{pane_index}' 2>/dev/null \
            | grep "$ppid_tty" | head -1 | awk '{print $2}')
        if [ -n "$tmux_target" ]; then
            echo "tmux" "$tmux_target"
            return
        fi
    fi
    echo "unknown" ""
}

read -r TERM_APP TERM_ID <<< "$(detect_terminal)"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID="${CLAUDE_SESSION_ID:-$$-$(basename "${PWD}")}"

# Build permission request JSON
REQUEST_JSON=$(echo "$INPUT" | jq \
    --arg timestamp "$TIMESTAMP" \
    --arg pid "$$" \
    --arg sessionId "$SESSION_ID" \
    --arg projectPath "$PWD" \
    --arg projectName "$(basename "$PWD")" \
    --arg eventType "permission_prompt" \
    --arg termApp "$TERM_APP" \
    --arg termId "$TERM_ID" \
    '{
        version: 1,
        timestamp: $timestamp,
        pid: ($pid | tonumber),
        sessionId: $sessionId,
        projectPath: $projectPath,
        projectName: $projectName,
        eventType: $eventType,
        details: {
            tool: (.tool_name // .tool // "unknown"),
            command: ((.tool_input // {}) | .command // null),
            description: (.description // null)
        },
        terminal: { app: $termApp, tabId: $termId }
    }')

# Connect to Bobber daemon and block for response
# Use Python for proper socket handling (nc doesn't handle bidirectional well)
RESPONSE=$(python3 -c "
import socket, json, sys

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(300)  # 5 minute timeout
try:
    sock.connect('$SOCKET_PATH')
    sock.sendall('''$REQUEST_JSON'''.encode())
    response = sock.recv(4096).decode()
    print(response)
except (socket.timeout, ConnectionRefusedError, FileNotFoundError):
    sys.exit(0)  # Fallback to Claude's native dialog
finally:
    sock.close()
" 2>/dev/null)

# Output response to stdout (Claude Code reads this)
if [ -n "$RESPONSE" ]; then
    echo "$RESPONSE"
fi
```

**Step 2: Make script executable**

Run: `chmod +x plugins/claude-bobber-plugin/scripts/bobber-permission.sh`

**Step 3: Commit**

```bash
git add plugins/
git commit -m "feat: add blocking permission hook script with socket IPC"
```

---

## Phase 8: Wiring Everything Together

### Task 16: Wire AppDelegate to All Services

**Files:**
- Modify: `Sources/Bobber/AppDelegate.swift`

**Step 1: Update AppDelegate to connect all services**

```swift
// Sources/Bobber/AppDelegate.swift (full replacement)
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
        NSApp.setActivationPolicy(.accessory)

        sessionManager = SessionManager()
        soundManager = SoundManager()
        windowJumper = WindowJumper()

        setupMenubarIcon()
        setupPanel()
        setupEventWatcher()
        setupPermissionServer()
        setupHotkey()
        setupCleanupTimer()
    }

    private func setupMenubarIcon() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Bobber")
            button.action = #selector(togglePanel)
            button.target = self
        }
        iconManager = MenubarIconManager(statusItem: statusItem!, sessionManager: sessionManager)
    }

    private func setupPanel() {
        panelController = PanelController(sessionManager: sessionManager)
    }

    private func setupEventWatcher() {
        eventWatcher = EventFileWatcher { [weak self] event in
            Task { @MainActor in
                self?.sessionManager.handleEvent(event)
            }
        }
        try? eventWatcher?.start()
    }

    private func setupPermissionServer() {
        permissionServer = PermissionServer()
        permissionServer?.onPermissionRequest = { [weak self] sessionId, event in
            guard let self else { return }
            self.sessionManager.handleEvent(event)
            self.soundManager.play(for: .permission)
            // Auto-show panel on permission request
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
            Task { @MainActor in
                self?.sessionManager.cleanupSessions()
            }
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
```

**Step 2: Build and run full app**

Run: `swift build && swift run`
Expected: App starts, menubar icon appears, Option+B toggles panel, events directory watched

**Step 3: Commit**

```bash
git add Sources/
git commit -m "feat: wire AppDelegate to all services (events, permissions, hotkey, sound)"
```

---

### Task 17: Connect Permission Actions to Socket Responses

**Files:**
- Modify: `Sources/Bobber/UI/ActionsListView.swift`
- Modify: `Sources/Bobber/UI/PanelContentView.swift`

**Step 1: Add permission response callback through the view hierarchy**

Pass `permissionServer.respond()` from PanelContentView → ActionsListView → PermissionCardView so that clicking Approve/Deny sends the response back through the Unix socket to the blocking hook script.

Key change: Add an `onPermissionDecision: (String, PermissionDecision) -> Void` callback that propagates from PanelContentView down to PermissionCardView. When a button is clicked, call `permissionServer.respond(sessionId:decision:)`.

**Step 2: Build and verify**

Run: `swift build`
Expected: Compiles without errors

**Step 3: Commit**

```bash
git add Sources/
git commit -m "feat: connect permission card actions to socket responses"
```

---

## Phase 9: Configuration & Polish

### Task 18: Configuration System

**Files:**
- Create: `Sources/Bobber/Models/BobberConfig.swift`

**Step 1: Implement config loading/saving**

```swift
// Sources/Bobber/Models/BobberConfig.swift
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
```

**Step 2: Build to verify**

Run: `swift build`
Expected: Compiles without errors

**Step 3: Commit**

```bash
git add Sources/
git commit -m "feat: add BobberConfig with JSON persistence"
```

---

### Task 19: Ensure ~/.bobber/ Directory Setup on Launch

**Files:**
- Modify: `Sources/Bobber/AppDelegate.swift`

**Step 1: Add directory creation at launch**

Add a method `ensureDirectories()` called from `applicationDidFinishLaunching` that creates:
- `~/.bobber/`
- `~/.bobber/events/`
- `~/.bobber/config.json` (if doesn't exist, write defaults)

**Step 2: Build and verify**

Run: `swift build && swift run`
Expected: Directories created on first launch

**Step 3: Commit**

```bash
git add Sources/
git commit -m "feat: ensure ~/.bobber/ directory structure on launch"
```

---

## Phase 10: End-to-End Testing

### Task 20: Manual Integration Test

**Step 1: Build and launch Bobber**

Run: `swift build -c release && .build/release/Bobber`

**Step 2: Simulate an event**

Write a test event file manually:
```bash
mkdir -p ~/.bobber/events
cat > /tmp/test-event.json << 'EOF'
{
  "version": 1,
  "timestamp": "2026-03-02T12:00:00Z",
  "pid": 99999,
  "sessionId": "test-session",
  "projectPath": "/tmp/test-project",
  "projectName": "test-project",
  "eventType": "session_start",
  "details": { "tool": null },
  "terminal": { "app": "terminal" }
}
EOF
mv /tmp/test-event.json ~/.bobber/events/test-event.json
```

Expected: Session appears in floating panel Sessions tab

**Step 3: Simulate a permission request**

```bash
echo '{"version":1,"timestamp":"2026-03-02T12:01:00Z","pid":99999,"sessionId":"test-session","projectPath":"/tmp/test","projectName":"test","eventType":"permission_prompt","details":{"tool":"Bash","command":"rm -rf /","description":"Delete everything"}}' | python3 -c "
import socket, json, sys
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(30)
sock.connect('/tmp/bobber.sock')
sock.sendall(sys.stdin.read().encode())
print('Waiting for response...')
resp = sock.recv(4096).decode()
print(f'Got: {resp}')
sock.close()
"
```

Expected: Permission card appears in Actions tab, clicking Approve sends response back to the test script

**Step 4: Verify keyboard gesture**

Press Option+B → panel should toggle

**Step 5: Verify sound**

When permission card appears, should hear system sound

**Step 6: Commit final state**

```bash
git add -A
git commit -m "feat: Bobber v0.1 — complete MVP"
```

---

## Task Summary

| Phase | Tasks | Description |
|-------|-------|-------------|
| 1. Scaffold | 1-3 | Project setup, data models, session manager |
| 2. IPC | 4-5 | File watcher (FSEvents), Unix socket permission server |
| 3. UI Panel | 6-9 | Floating panel, sessions tab, action cards |
| 4. Menubar & Keys | 10-11 | Menubar icon badges, Option+B hotkey |
| 5. Sound | 12 | Sound alerts with cooldown |
| 6. Window Jump | 13 | Terminal detection & AppleScript window focus |
| 7. Plugin | 14-15 | Claude Code plugin with hook scripts |
| 8. Wiring | 16-17 | Connect all services in AppDelegate |
| 9. Config | 18-19 | Config system, directory setup |
| 10. E2E Test | 20 | Manual integration test |

**Total: 20 tasks across 10 phases**
