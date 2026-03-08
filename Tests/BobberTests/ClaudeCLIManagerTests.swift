import XCTest
@testable import Bobber

final class ClaudeCLIManagerTests: XCTestCase {
    func testAutoDetectFindsClaudeInPath() {
        let manager = ClaudeCLIManager()
        // Should at least attempt detection without crashing
        manager.autoDetect()
        // Path is either found or nil — no crash
    }

    func testSetCustomPath() {
        let manager = ClaudeCLIManager()
        manager.setCustomPath("/usr/local/bin/claude")
        XCTAssertEqual(manager.cliPath, "/usr/local/bin/claude")
    }

    func testPluginStatusDefaultsToUnknown() {
        let manager = ClaudeCLIManager()
        XCTAssertEqual(manager.pluginStatus, .unknown)
    }
}
