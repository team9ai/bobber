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

    func testSessionPriorityOrdering() {
        XCTAssertTrue(SessionPriority.focus < SessionPriority.priority)
        XCTAssertTrue(SessionPriority.priority < SessionPriority.standard)
        XCTAssertEqual(SessionPriority.allCases.count, 3)
    }

    func testSessionPriorityDefaultIsStandard() {
        let session = Session(id: "s1", projectName: "test", projectPath: "/tmp/test")
        XCTAssertEqual(session.priority, .standard)
    }

    func testSessionDecodesWithoutPriorityField() throws {
        let json = """
        {
            "id": "s1",
            "projectName": "test",
            "projectPath": "/tmp/test",
            "state": "active",
            "lastEvent": "2026-03-04T10:00:00Z"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(Session.self, from: json)
        XCTAssertEqual(session.priority, .standard)
    }

    func testSessionDecodesWithPriorityField() throws {
        let json = """
        {
            "id": "s1",
            "projectName": "test",
            "projectPath": "/tmp/test",
            "state": "active",
            "lastEvent": "2026-03-04T10:00:00Z",
            "priority": 0
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(Session.self, from: json)
        XCTAssertEqual(session.priority, .focus)
    }

    func testBobberConfigDecodesWithNewSections() throws {
        let json = """
        {
            "sounds": { "enabled": true, "volume": 0.7, "cooldownSeconds": 3 },
            "sessions": { "staleTimeoutMinutes": 30, "keepCompletedCount": 10 },
            "appearance": { "idleOpacity": 0.5, "hoverOpacity": 0.9 },
            "shortcuts": { "togglePanelKey": "b", "togglePanelModifiers": ["option"] },
            "general": { "launchAtLogin": false }
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(BobberConfig.self, from: json)
        XCTAssertEqual(config.appearance.idleOpacity, 0.5)
        XCTAssertEqual(config.appearance.hoverOpacity, 0.9)
        XCTAssertEqual(config.shortcuts.togglePanelKey, "b")
        XCTAssertEqual(config.shortcuts.togglePanelModifiers, ["option"])
        XCTAssertEqual(config.general.launchAtLogin, false)
        XCTAssertNil(config.general.claudeCLIPath)
    }

    func testBobberConfigDecodesWithoutNewSections() throws {
        let json = """
        {
            "sounds": { "enabled": true, "volume": 0.7, "cooldownSeconds": 3 },
            "sessions": { "staleTimeoutMinutes": 30, "keepCompletedCount": 10 }
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(BobberConfig.self, from: json)
        XCTAssertEqual(config.appearance.idleOpacity, 0.65)
        XCTAssertEqual(config.appearance.hoverOpacity, 1.0)
        XCTAssertEqual(config.shortcuts.togglePanelKey, "b")
        XCTAssertEqual(config.general.launchAtLogin, false)
    }
}
