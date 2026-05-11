import Foundation

struct SnoozeOption: Identifiable, Equatable {
    let id: String
    let title: String
    let date: Date

    static func == (lhs: SnoozeOption, rhs: SnoozeOption) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.date == rhs.date
    }
}

/// Time-aware snooze presets. Pure & deterministic given `now` + `calendar` so
/// it's trivially testable without UI. Hides options that would resolve to a
/// time in the past, plus the "this weekend" preset on Fri/Sat/Sun (Mon–Thu only).
enum SnoozePresets {
    static func options(for now: Date, calendar: Calendar = .current) -> [SnoozeOption] {
        var opts: [SnoozeOption] = []

        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now) // 1=Sun, 2=Mon, …, 7=Sat
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday

        // This evening (today 18:00) — only shown before 17:00.
        if hour < 17 {
            if let d = setHour(18, on: startOfToday, calendar: calendar), d > now {
                opts.append(SnoozeOption(id: "this-evening", title: "This evening", date: d))
            }
        }

        // Tomorrow morning (08:00).
        if let d = setHour(8, on: startOfTomorrow, calendar: calendar) {
            opts.append(SnoozeOption(id: "tomorrow-morning", title: "Tomorrow morning", date: d))
        }

        // Tomorrow evening (18:00).
        if let d = setHour(18, on: startOfTomorrow, calendar: calendar) {
            opts.append(SnoozeOption(id: "tomorrow-evening", title: "Tomorrow evening", date: d))
        }

        // This weekend (next Saturday 09:00) — only shown Mon–Thu.
        // weekday: Sun=1, Mon=2, Tue=3, Wed=4, Thu=5, Fri=6, Sat=7
        if (2...5).contains(weekday) {
            if let saturday = nextWeekday(7, on: startOfToday, calendar: calendar),
               let d = setHour(9, on: saturday, calendar: calendar) {
                opts.append(SnoozeOption(id: "this-weekend", title: "This weekend", date: d))
            }
        }

        // Next week (next Monday 09:00).
        if let monday = nextWeekday(2, on: startOfToday, calendar: calendar),
           let d = setHour(9, on: monday, calendar: calendar) {
            opts.append(SnoozeOption(id: "next-week", title: "Next week", date: d))
        }

        // Next month (1st of next month 09:00).
        if let firstOfNextMonth = firstOfNextMonth(from: now, calendar: calendar),
           let d = setHour(9, on: firstOfNextMonth, calendar: calendar) {
            opts.append(SnoozeOption(id: "next-month", title: "Next month", date: d))
        }

        return opts
    }

    private static func setHour(_ hour: Int, on day: Date, calendar: Calendar) -> Date? {
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        comps.hour = hour
        comps.minute = 0
        comps.second = 0
        return calendar.date(from: comps)
    }

    /// Next occurrence of `weekday` strictly *after* `from` (i.e., never returns `from` itself).
    private static func nextWeekday(_ weekday: Int, on from: Date, calendar: Calendar) -> Date? {
        let current = calendar.component(.weekday, from: from)
        var diff = weekday - current
        if diff <= 0 { diff += 7 }
        return calendar.date(byAdding: .day, value: diff, to: from)
    }

    private static func firstOfNextMonth(from date: Date, calendar: Calendar) -> Date? {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let firstOfThisMonth = calendar.date(from: comps) else { return nil }
        return calendar.date(byAdding: .month, value: 1, to: firstOfThisMonth)
    }
}
