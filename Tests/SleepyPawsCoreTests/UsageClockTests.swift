import SleepyPawsCore
import XCTest

final class UsageClockTests: XCTestCase {
    func testPausedTimeDoesNotCatchUpOnResume() {
        var clock = UsageClock()
        XCTAssertEqual(clock.sample(at: 50, counts: true), 0)
        XCTAssertEqual(clock.sample(at: 51, counts: true), 1)
        XCTAssertEqual(clock.sample(at: 52, counts: false), 0)
        XCTAssertEqual(clock.sample(at: 300, counts: false), 0)
        XCTAssertEqual(clock.sample(at: 500, counts: true), 0)
        XCTAssertEqual(clock.sample(at: 501, counts: true), 1)
    }
}
