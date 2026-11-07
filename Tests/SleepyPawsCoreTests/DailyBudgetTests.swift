import Foundation
import SleepyPawsCore
import XCTest

final class DailyBudgetTests: XCTestCase {
    private let midnight = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00 UTC
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testDefaultCountsDownAndLocksAtOneHour() {
        var budget = DailyBudget()
        budget.record(0, at: midnight, calendar: utc)
        XCTAssertEqual(budget.remaining, 3600)
        budget.record(3599.5, at: midnight + 3599.5, calendar: utc)
        XCTAssertEqual(budget.remaining, 0.5)
        budget.record(0.5, at: midnight + 3600, calendar: utc)
        XCTAssertTrue(budget.expired)
        budget.record(300, at: midnight + 3900, calendar: utc)
        budget.grantExtraTime()
        XCTAssertEqual(budget.remaining, 3600)
    }

    func testRestartPreservesSpentTimeAndMidnightClearsBonus() throws {
        var budget = DailyBudget()
        budget.setLimit(minutes: 1)
        budget.record(60, at: midnight + 3600, calendar: utc)
        budget.grantExtraTime()
        budget.record(30, at: midnight + 3630, calendar: utc)
        var reopened = try JSONDecoder().decode(DailyBudget.self, from: JSONEncoder().encode(budget))
        XCTAssertEqual(reopened.remaining, 30)
        reopened.record(2, at: midnight + 86_401, calendar: utc)
        XCTAssertEqual(reopened.remaining, 59)
    }

    func testChangingLimitAndSettingClockBackDoNotResetUsedTime() {
        var budget = DailyBudget()
        budget.record(480, at: midnight + 3600, calendar: utc)
        budget.setLimit(minutes: 5)
        XCTAssertTrue(budget.expired)
        budget.record(0, at: midnight - 86_400, calendar: utc)
        XCTAssertTrue(budget.expired)
        budget.grantExtraTime()
        XCTAssertEqual(budget.remaining, 300)
    }

    func testPINFormatVerificationAndRetryDelay() throws {
        XCTAssertThrowsError(try ParentPIN("１２３４"))
        XCTAssertThrowsError(try ParentPIN("02948"))
        XCTAssertThrowsError(try ParentPIN("029"))
        let pin = try ParentPIN("0294")
        XCTAssertTrue(try pin.matches("0294"))
        XCTAssertFalse(try pin.matches("0295"))
        var attempts = PINAttempts()
        for _ in 0..<4 { attempts.failed(at: midnight) }
        XCTAssertEqual(attempts.wait(at: midnight), 0)
        attempts.failed(at: midnight)
        let restored = try JSONDecoder().decode(PINAttempts.self, from: JSONEncoder().encode(attempts))
        XCTAssertEqual(restored.wait(at: midnight + 3), 27)
        XCTAssertEqual(restored.wait(at: midnight + 30), 0)
    }
}

final class StricterBudgetTests: XCTestCase {
    private let noon = Date(timeIntervalSince1970: 1_767_268_800) // 2026-01-01 12:00 UTC
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testLessRemainingAndLaterDayWin() {
        var used = DailyBudget()
        used.record(1200, at: noon, calendar: utc)
        var fresh = DailyBudget()
        fresh.record(0, at: noon, calendar: utc)
        XCTAssertEqual(DailyBudget.stricter(fresh, used).remaining, 2400)
        XCTAssertEqual(DailyBudget.stricter(used, fresh).remaining, 2400)

        var raised = used
        raised.setLimit(minutes: 720) // an edited copy with a higher limit loses
        XCTAssertEqual(DailyBudget.stricter(raised, used).remaining, 2400)

        var tomorrow = DailyBudget()
        tomorrow.record(60, at: noon + 86_400, calendar: utc)
        XCTAssertEqual(DailyBudget.stricter(used, tomorrow).remaining, 3540)
        XCTAssertEqual(DailyBudget.stricter(DailyBudget(), used).remaining, 2400) // never-used copy
    }
}

final class PauseTests: XCTestCase {
    private let noon = Date(timeIntervalSince1970: 1_767_268_800) // 2026-01-01 12:00 UTC
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testPauseStopsCountingLiftsTheBlockAndEndsAtMidnight() throws {
        var budget = DailyBudget()
        budget.setLimit(minutes: 1)
        budget.record(60, at: noon, calendar: utc)
        XCTAssertTrue(budget.blocks)
        budget.pause()
        XCTAssertFalse(budget.blocks)
        budget.resume()
        XCTAssertTrue(budget.blocks)

        var running = DailyBudget()
        running.record(10, at: noon, calendar: utc)
        running.pause()
        running.record(300, at: noon + 300, calendar: utc)
        XCTAssertEqual(running.remaining, 3590)
        let reopened = try JSONDecoder().decode(DailyBudget.self, from: JSONEncoder().encode(running))
        XCTAssertTrue(reopened.isPaused)
        running.record(5, at: noon + 86_400, calendar: utc)
        XCTAssertFalse(running.isPaused)
        XCTAssertEqual(running.remaining, 3595)
    }

    func testOldStateWithoutPauseDecodesAndHandAddedPauseLoses() throws {
        let old = #"{"minutes":1,"day":"2026-01-01","spent":60,"extra":0}"#
        let budget = try JSONDecoder().decode(DailyBudget.self, from: Data(old.utf8))
        XCTAssertTrue(budget.blocks)
        var edited = budget
        edited.pause()
        XCTAssertTrue(DailyBudget.stricter(edited, budget).blocks)
        XCTAssertTrue(DailyBudget.stricter(budget, edited).blocks)
    }
}

final class ExtraTimeTests: XCTestCase {
    func testAddingAChosenAmountAfterTheLimit() {
        var budget = DailyBudget()
        budget.setLimit(minutes: 60)
        let midnight = Date(timeIntervalSince1970: 1_767_225_600)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        budget.record(3600, at: midnight + 3600, calendar: utc)
        XCTAssertTrue(budget.expired)
        budget.grantExtraTime(minutes: 15)
        XCTAssertEqual(budget.remaining, 900)
        budget.record(900, at: midnight + 4500, calendar: utc)
        budget.grantExtraTime(minutes: 150)
        XCTAssertEqual(budget.remaining, 9000)
    }
}

final class RestartTests: XCTestCase {
    func testSavingALimitStartsTodaysCountdownOver() {
        var budget = DailyBudget()
        let noon = Date(timeIntervalSince1970: 1_767_268_800)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        budget.record(3600, at: noon, calendar: utc)
        XCTAssertTrue(budget.expired)
        budget.pause()
        budget.restart(minutes: 90)
        XCTAssertEqual(budget.remaining, 5400)
        XCTAssertFalse(budget.isPaused)
        budget.record(60, at: noon + 60, calendar: utc) // and counts on from there
        XCTAssertEqual(budget.remaining, 5340)
    }
}
