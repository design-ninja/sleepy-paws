import SleepyPawsCore
import XCTest

final class DurationTextTests: XCTestCase {
    func testButtonLabels() {
        XCTAssertEqual(DurationText.minutes(1), "1 Minute")
        XCTAssertEqual(DurationText.minutes(30), "30 Minutes")
        XCTAssertEqual(DurationText.minutes(60), "1 Hour")
        XCTAssertEqual(DurationText.minutes(120), "2 Hours")
        XCTAssertEqual(DurationText.minutes(270), "4 h 30 min")
    }

    func testShortLabels() {
        XCTAssertEqual(DurationText.short(5), "5m")
        XCTAssertEqual(DurationText.short(60), "1h")
        XCTAssertEqual(DurationText.short(90), "1h 30m")
        XCTAssertEqual(DurationText.short(480), "8h")
    }

    func testCountdown() {
        XCTAssertEqual(DurationText.countdown(seconds: 59), "0:59")
        XCTAssertEqual(DurationText.countdown(seconds: 1799), "29:59")
        XCTAssertEqual(DurationText.countdown(seconds: 3600), "1:00:00")
        XCTAssertEqual(DurationText.countdown(seconds: 16_199), "4:29:59")
    }
}
