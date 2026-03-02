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
