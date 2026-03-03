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

    func testParseEventFileWithDetails() throws {
        let json = """
        {"version":1,"timestamp":"2026-03-02T10:30:00Z","pid":456,
         "sessionId":"s2","projectPath":"/tmp/test","projectName":"test",
         "eventType":"permission_prompt",
         "details":{"tool":"Bash","command":"pnpm test","description":"Run tests"}}
        """
        let file = tempDir.appendingPathComponent("1709-456.json")
        try json.write(to: file, atomically: true, encoding: .utf8)

        let event = try EventFileWatcher.parseEventFile(at: file)
        XCTAssertEqual(event.sessionId, "s2")
        XCTAssertEqual(event.eventType, .permissionPrompt)
        XCTAssertEqual(event.details?.tool, "Bash")
        XCTAssertEqual(event.details?.command, "pnpm test")
    }

    func testScanPicksUpNewFiles() throws {
        var receivedEvents: [BobberEvent] = []
        let watcher = EventFileWatcher(eventsDir: tempDir) { event in
            receivedEvents.append(event)
        }

        // Write an event file before starting
        let json = """
        {"version":1,"timestamp":"2026-03-02T10:30:00Z","pid":789,
         "sessionId":"s3","projectPath":"/tmp/test","projectName":"test",
         "eventType":"session_start"}
        """
        let file = tempDir.appendingPathComponent("1709-789.json")
        try json.write(to: file, atomically: true, encoding: .utf8)

        try watcher.start()

        // Give the watcher a moment to process
        let expectation = XCTestExpectation(description: "Event received")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        watcher.stop()

        XCTAssertEqual(receivedEvents.count, 1)
        XCTAssertEqual(receivedEvents.first?.sessionId, "s3")
    }

    func testDuplicateFilesNotProcessedTwice() throws {
        var receivedEvents: [BobberEvent] = []
        let watcher = EventFileWatcher(eventsDir: tempDir) { event in
            receivedEvents.append(event)
        }

        let json = """
        {"version":1,"timestamp":"2026-03-02T10:30:00Z","pid":100,
         "sessionId":"s4","projectPath":"/tmp/test","projectName":"test",
         "eventType":"session_start"}
        """
        let file = tempDir.appendingPathComponent("1709-100.json")
        try json.write(to: file, atomically: true, encoding: .utf8)

        try watcher.start()

        // Wait for initial scan
        let expectation = XCTestExpectation(description: "Initial scan")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        // Write the same filename again (simulates re-scan without deletion)
        // The watcher should not reprocess it since the name is already tracked
        watcher.stop()

        XCTAssertEqual(receivedEvents.count, 1)
    }

    func testMalformedFileIsSkipped() throws {
        var receivedEvents: [BobberEvent] = []
        let watcher = EventFileWatcher(eventsDir: tempDir) { event in
            receivedEvents.append(event)
        }

        // Write a malformed JSON file
        let badFile = tempDir.appendingPathComponent("bad.json")
        try "not valid json".write(to: badFile, atomically: true, encoding: .utf8)

        // Write a valid JSON file
        let json = """
        {"version":1,"timestamp":"2026-03-02T10:30:00Z","pid":200,
         "sessionId":"s5","projectPath":"/tmp/test","projectName":"test",
         "eventType":"session_start"}
        """
        let goodFile = tempDir.appendingPathComponent("good.json")
        try json.write(to: goodFile, atomically: true, encoding: .utf8)

        try watcher.start()

        let expectation = XCTestExpectation(description: "Scan completed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        watcher.stop()

        // Only the valid file should produce an event
        XCTAssertEqual(receivedEvents.count, 1)
        XCTAssertEqual(receivedEvents.first?.sessionId, "s5")
    }
}
