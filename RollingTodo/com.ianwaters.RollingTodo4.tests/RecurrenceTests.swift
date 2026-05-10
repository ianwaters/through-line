import Testing
import Foundation
@testable import RollingTodo

@Suite("Recurrence.next")
struct RecurrenceTests {
    private let cal = TestSupport.utcCalendar

    @Test func noneReturnsNil() {
        let date = TestSupport.date(2026, 5, 10, calendar: cal)
        #expect(Recurrence.none.next(after: date, calendar: cal) == nil)
    }

    @Test func dailyAdvancesByOneDay() {
        let date = TestSupport.date(2026, 5, 10, calendar: cal)
        let next = Recurrence.daily.next(after: date, calendar: cal)
        #expect(next == TestSupport.date(2026, 5, 11, calendar: cal))
    }

    @Test func weeklyAdvancesBySevenDays() {
        let date = TestSupport.date(2026, 5, 10, calendar: cal)
        let next = Recurrence.weekly.next(after: date, calendar: cal)
        #expect(next == TestSupport.date(2026, 5, 17, calendar: cal))
    }

    @Test func monthlyAdvancesByOneMonth() {
        let date = TestSupport.date(2026, 5, 10, calendar: cal)
        let next = Recurrence.monthly.next(after: date, calendar: cal)
        #expect(next == TestSupport.date(2026, 6, 10, calendar: cal))
    }

    @Test func yearlyAdvancesByOneYear() {
        let date = TestSupport.date(2026, 5, 10, calendar: cal)
        let next = Recurrence.yearly.next(after: date, calendar: cal)
        #expect(next == TestSupport.date(2027, 5, 10, calendar: cal))
    }

    /// 2026-01-31 + 1 month must roll over to Feb 28 (Gregorian non-leap),
    /// not blow up or land on March. Calendar.date(byAdding:) handles this
    /// natively but the test pins the behaviour so a future helper change
    /// doesn't silently regress.
    @Test func monthlyHandlesEndOfMonthRollover() {
        let date = TestSupport.date(2026, 1, 31, calendar: cal)
        let next = Recurrence.monthly.next(after: date, calendar: cal)
        #expect(next == TestSupport.date(2026, 2, 28, calendar: cal))
    }

    /// Friday (2026-05-08) → Monday (2026-05-11), skipping Sat + Sun.
    @Test func weekdaysSkipsTheWeekend() {
        let friday = TestSupport.date(2026, 5, 8, calendar: cal)
        let next = Recurrence.weekdays.next(after: friday, calendar: cal)
        #expect(next == TestSupport.date(2026, 5, 11, calendar: cal))
    }

    /// Tuesday → Wednesday (no skipping needed).
    @Test func weekdaysOnMidweekAdvancesOneDay() {
        let tuesday = TestSupport.date(2026, 5, 12, calendar: cal)
        let next = Recurrence.weekdays.next(after: tuesday, calendar: cal)
        #expect(next == TestSupport.date(2026, 5, 13, calendar: cal))
    }

    /// Sunday (2026-05-10) → Monday (2026-05-11). Sunday is weekday 1, which
    /// the "skip weekend" guard rejects, so we should still land on Monday
    /// rather than getting stuck on Sunday.
    @Test func weekdaysFromSundayAdvancesToMonday() {
        let sunday = TestSupport.date(2026, 5, 10, calendar: cal)
        let next = Recurrence.weekdays.next(after: sunday, calendar: cal)
        #expect(next == TestSupport.date(2026, 5, 11, calendar: cal))
    }
}
