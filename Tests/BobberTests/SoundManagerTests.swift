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
