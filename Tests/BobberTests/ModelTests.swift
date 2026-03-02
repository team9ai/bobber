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
