# Session Detail View Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a clickable detail view for session cards showing full status info, recent activity timeline, and quick actions (jump to terminal, rename, hide, copy ID).

**Architecture:** @State-based navigation in PanelContentView — `selectedSessionId` controls whether we show the session list or a detail view. Each Session accumulates the last 3 events in-memory for the activity timeline. WindowJumper is passed through via a callback closure from AppDelegate.

**Tech Stack:** SwiftUI, AppKit (NSPasteboard, WindowJumper)

---

### Task 1: Add SessionEvent model and recentEvents to Session

**Files:**
- Modify: `Sources/Bobber/Models/Session.swift`

**Step 1: Add SessionEvent struct and recentEvents field**

Add above `Session` struct definition (after line 5):

```swift
struct SessionEvent: Codable {
    let timestamp: Date
    let type: BobberEvent.EventType
    let tool: String?
    let summary: String?
}
```

Add to `Session` struct (after `pid` field, line 18):

```swift
var recentEvents: [SessionEvent] = []
```

**Step 2: Exclude recentEvents from Codable persistence**

Since `recentEvents` rebuilds from live events and shouldn't bloat state.json, add custom CodingKeys to Session to exclude it:

```swift
enum CodingKeys: String, CodingKey {
    case id, projectName, projectPath, sessionTitle, state
    case lastEvent, lastTool, lastToolSummary, pendingAction, terminal, pid
}
```

**Step 3: Build to verify**

Run: `swift build`
Expected: Build succeeds with no errors.

**Step 4: Commit**

```
feat: add SessionEvent model and recentEvents to Session
```

---

### Task 2: Populate recentEvents in SessionManager.handleEvent

**Files:**
- Modify: `Sources/Bobber/Services/SessionManager.swift:71-105`

**Step 1: Create a SessionEvent and prepend to recentEvents**

In `handleEvent()`, after updating the session's tool info (around line 86 for existing sessions, line 104 for new sessions), add event recording logic.

For the **existing session** branch (after line 85, closing brace of the tool-update `if`):

```swift
let sessionEvent = SessionEvent(
    timestamp: event.timestamp,
    type: event.eventType,
    tool: event.details?.tool,
    summary: event.details?.description ?? event.details?.command
)
sessions[index].recentEvents.insert(sessionEvent, at: 0)
if sessions[index].recentEvents.count > 3 {
    sessions[index].recentEvents.removeLast()
}
```

For the **new session** branch (after line 103, before `sessions.append(session)`):

```swift
let sessionEvent = SessionEvent(
    timestamp: event.timestamp,
    type: event.eventType,
    tool: event.details?.tool,
    summary: event.details?.description ?? event.details?.command
)
session.recentEvents = [sessionEvent]
```

**Step 2: Build to verify**

Run: `swift build`
Expected: Build succeeds.

**Step 3: Commit**

```
feat: populate recentEvents in SessionManager.handleEvent
```

---

### Task 3: Thread WindowJumper callback through to PanelContentView

**Files:**
- Modify: `Sources/Bobber/UI/PanelContentView.swift:3-5`
- Modify: `Sources/Bobber/UI/PanelController.swift:9,22-25`
- Modify: `Sources/Bobber/AppDelegate.swift:52-57`

**Step 1: Add onJumpToSession callback to PanelContentView**

In `PanelContentView` (line 5, after `onPermissionDecision`):

```swift
var onJumpToSession: ((Session) -> Void)?
```

**Step 2: Add callback to PanelController and pass through**

In `PanelController` (line 7, after `onPermissionDecision`):

```swift
private let onJumpToSession: ((Session) -> Void)?
```

Update init (line 9):

```swift
init(sessionManager: SessionManager,
     onPermissionDecision: ((String, PermissionDecision) -> Void)? = nil,
     onJumpToSession: ((Session) -> Void)? = nil) {
    self.sessionManager = sessionManager
    self.onPermissionDecision = onPermissionDecision
    self.onJumpToSession = onJumpToSession
}
```

Update `show()` where PanelContentView is created (line 22):

```swift
let contentView = PanelContentView(
    sessionManager: sessionManager,
    onPermissionDecision: onPermissionDecision,
    onJumpToSession: onJumpToSession,
    onHide: { [weak self] in self?.hide() }
)
```

**Step 3: Pass WindowJumper from AppDelegate**

In `setupPanel()` (AppDelegate.swift line 52):

```swift
private func setupPanel() {
    panelController = PanelController(
        sessionManager: sessionManager,
        onPermissionDecision: { [weak self] sessionId, decision in
            self?.permissionServer?.respond(sessionId: sessionId, decision: decision)
        },
        onJumpToSession: { [weak self] session in
            self?.windowJumper.jumpToSession(session)
        }
    )
}
```

**Step 4: Build to verify**

Run: `swift build`
Expected: Build succeeds (onJumpToSession not used yet, but wired up).

**Step 5: Commit**

```
feat: thread WindowJumper callback through to PanelContentView
```

---

### Task 4: Add navigation state and wire SessionRowView tap

**Files:**
- Modify: `Sources/Bobber/UI/PanelContentView.swift:7,46-48`
- Modify: `Sources/Bobber/UI/SessionRowView.swift:3,55-56,67`

**Step 1: Add selectedSessionId state to PanelContentView**

Add after line 7 (`@State private var selectedTab`):

```swift
@State private var selectedSessionId: String?
```

**Step 2: Update sessions tab to conditionally show detail or list**

Replace the `case .sessions:` block (lines 47-48):

```swift
case .sessions:
    if let sessionId = selectedSessionId,
       let session = sessionManager.sessions.first(where: { $0.id == sessionId }) {
        SessionDetailView(
            session: session,
            sessionManager: sessionManager,
            onBack: { selectedSessionId = nil },
            onJumpToSession: onJumpToSession
        )
    } else {
        SessionsListView(
            sessionManager: sessionManager,
            onSelectSession: { selectedSessionId = $0 }
        )
    }
```

**Step 3: Add onSelectSession callback to SessionsListView**

In `SessionsListView` (SessionRowView.swift line 4, after `sessionManager`):

```swift
var onSelectSession: ((String) -> Void)?
```

Wrap `SessionRowView` in a `Button` (lines 55-56):

```swift
ForEach(group.sessions) { session in
    Button {
        onSelectSession?(session.id)
    } label: {
        SessionRowView(session: session, sessionManager: sessionManager)
    }
    .buttonStyle(.plain)
}
```

**Step 4: Build to verify**

Run: `swift build`
Expected: Build fails — SessionDetailView doesn't exist yet. That's expected, proceed to Task 5.

**Step 5: Commit**

```
feat: add navigation state and session tap wiring
```

---

### Task 5: Create SessionDetailView

**Files:**
- Create: `Sources/Bobber/UI/SessionDetailView.swift`

**Step 1: Create the complete SessionDetailView**

Create `Sources/Bobber/UI/SessionDetailView.swift`:

```swift
import SwiftUI
import AppKit

struct SessionDetailView: View {
    let session: Session
    @ObservedObject var sessionManager: SessionManager
    let onBack: () -> Void
    var onJumpToSession: ((Session) -> Void)?

    @State private var selectedTab: DetailTab = .status
    @State private var showRenameAlert = false
    @State private var nicknameInput = ""

    enum DetailTab {
        case status, activity
    }

    private var displayName: String {
        sessionManager.sessionNicknames[session.id] ?? session.displayTitle
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: back + title
            HStack {
                Button {
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(displayName)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .lineLimit(1)

                Spacer()

                // Invisible spacer to balance back button width
                Color.clear.frame(width: 44, height: 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("Status").tag(DetailTab.status)
                Text("Activity").tag(DetailTab.activity)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // Content
            switch selectedTab {
            case .status:
                statusTab
            case .activity:
                activityTab
            }
        }
    }

    // MARK: - Status Tab

    private var statusTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // State
                HStack(spacing: 8) {
                    Circle()
                        .fill(session.state.color)
                        .frame(width: 10, height: 10)
                    Text(session.state.label)
                        .font(.system(.body, weight: .medium))
                }

                Divider()

                // Info rows
                infoRow("Project", session.projectName)
                infoRow("Path", session.projectPath)
                if let app = session.terminal?.app {
                    infoRow("Terminal", app)
                }
                if let pid = session.pid {
                    infoRow("PID", "\(pid)")
                }
                infoRow("Last event", session.lastEvent.relativeDescription + " ago")
                if let tool = session.lastTool {
                    infoRow("Last tool", tool)
                }

                Divider()

                // Quick actions
                Text("Quick Actions")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                HStack(spacing: 8) {
                    actionButton("Terminal", icon: "terminal") {
                        onJumpToSession?(session)
                    }
                    actionButton("Rename", icon: "pencil") {
                        nicknameInput = sessionManager.sessionNicknames[session.id] ?? ""
                        showRenameAlert = true
                    }
                    actionButton("Hide", icon: "eye.slash") {
                        sessionManager.hideSession(session.id)
                        onBack()
                    }
                    actionButton("Copy ID", icon: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(session.id, forType: .string)
                    }
                }
            }
            .padding(12)
        }
        .alert("Rename Session", isPresented: $showRenameAlert) {
            TextField("Nickname", text: $nicknameInput)
            Button("OK") {
                sessionManager.renameSession(session.id, nickname: nicknameInput)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a nickname for this session")
        }
    }

    // MARK: - Activity Tab

    private var activityTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if session.recentEvents.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No recent events")
                            .foregroundColor(.secondary)
                        Text("Events will appear here\nas the session runs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    ForEach(Array(session.recentEvents.enumerated()), id: \.offset) { index, event in
                        HStack(alignment: .top, spacing: 10) {
                            // Timeline dot + line
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(Color.primary.opacity(0.3))
                                    .frame(width: 8, height: 8)
                                if index < session.recentEvents.count - 1 {
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.1))
                                        .frame(width: 1)
                                        .frame(maxHeight: .infinity)
                                }
                            }

                            // Event content
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(event.type.rawValue.replacingOccurrences(of: "_", with: " "))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(event.timestamp.relativeDescription)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                if let tool = event.tool {
                                    Text(tool)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                if let summary = event.summary, !summary.isEmpty {
                                    Text(summary)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                        .padding(.vertical, 8)

                        if index < session.recentEvents.count - 1 {
                            Divider().padding(.leading, 18)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - Helpers

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}
```

**Step 2: Build to verify**

Run: `swift build`
Expected: Build succeeds. All pieces connected.

**Step 3: Commit**

```
feat: add SessionDetailView with status and activity tabs
```

---

### Task 6: Verify and clean up

**Step 1: Build clean**

Run: `swift build`
Expected: Build succeeds with no warnings.

**Step 2: Run the app and test**

Run: `swift run`

Verify:
- Session list renders as before
- Clicking a session card navigates to detail view
- Back button returns to list
- Status tab shows session info and quick actions
- Activity tab shows recent events (or empty state)
- Jump to Terminal, Rename, Hide, Copy ID all work
- Context menu on session rows still works

**Step 3: Final commit if any fixups needed**