import Testing
import Foundation
@testable import RollingTodo

@Suite("FocusPriorityFloor.passes")
struct FocusPriorityFloorTests {
    @Test(arguments: [
        (Priority.none, false),
        (.low, false),
        (.normal, false),
        (.high, true),
        (.urgent, true)
    ])
    func highOrUrgentFloor(_ priority: Priority, expected: Bool) {
        #expect(FocusPriorityFloor.highOrUrgent.passes(priority) == expected)
    }

    @Test(arguments: [
        (Priority.none, false),
        (.low, false),
        (.normal, false),
        (.high, false),
        (.urgent, true)
    ])
    func urgentFloor(_ priority: Priority, expected: Bool) {
        #expect(FocusPriorityFloor.urgent.passes(priority) == expected)
    }
}

@Suite("FocusDueWindow.includes")
struct FocusDueWindowTests {
    /// `includes` is "today-relative" — it compares the candidate against
    /// `Date.now`'s start-of-day, so the tests use system "now" rather than
    /// pinning to a specific date. Each window is checked at its boundary.
    private let cal = Calendar.current

    @Test func todayIncludesToday() {
        #expect(FocusDueWindow.today.includes(.now, calendar: cal))
    }

    @Test func todayIncludesYesterdayAsOverdue() {
        let yesterday = cal.date(byAdding: .day, value: -1, to: .now)!
        #expect(FocusDueWindow.today.includes(yesterday, calendar: cal))
    }

    @Test func todayExcludesTomorrow() {
        let tomorrow = cal.date(byAdding: .day, value: 1, to: .now)!
        #expect(!FocusDueWindow.today.includes(tomorrow, calendar: cal))
    }

    @Test func tomorrowIncludesTomorrow() {
        let tomorrow = cal.date(byAdding: .day, value: 1, to: .now)!
        #expect(FocusDueWindow.tomorrow.includes(tomorrow, calendar: cal))
    }

    @Test func tomorrowExcludesDayAfterTomorrow() {
        let dayAfter = cal.date(byAdding: .day, value: 2, to: .now)!
        #expect(!FocusDueWindow.tomorrow.includes(dayAfter, calendar: cal))
    }

    @Test func thisWeekIncludesSeventhDay() {
        let inSevenDays = cal.date(byAdding: .day, value: 7, to: .now)!
        #expect(FocusDueWindow.thisWeek.includes(inSevenDays, calendar: cal))
    }

    @Test func thisWeekExcludesEighthDay() {
        let inEightDays = cal.date(byAdding: .day, value: 8, to: .now)!
        #expect(!FocusDueWindow.thisWeek.includes(inEightDays, calendar: cal))
    }
}
