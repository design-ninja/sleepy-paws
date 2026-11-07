import SleepyPawsCore
import XCTest

final class PINDigitsTests: XCTestCase {
    func testTypingDeletingAndPasting() {
        var pin = PINDigits()
        pin.type("1")
        pin.type("a٢2")  // non-ASCII digits and letters are ignored
        XCTAssertEqual(pin.value, "12")
        XCTAssertFalse(pin.isComplete)
        pin.deleteLast()
        XCTAssertEqual(pin.value, "1")
        pin.type("2 3 4 5 6")  // paste stops at four digits
        XCTAssertEqual(pin.value, "1234")
        XCTAssertTrue(pin.isComplete)
        for _ in 0..<6 { pin.deleteLast() }
        XCTAssertEqual(pin.value, "")
        XCTAssertEqual(pin.count, 0)
    }

}
