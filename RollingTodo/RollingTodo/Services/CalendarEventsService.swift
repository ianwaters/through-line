import EventKit
import SwiftUI

@MainActor
@Observable
final class CalendarEventsService {
    static let shared = CalendarEventsService()

    private let store = EKEventStore()
    private let cooldown: TimeInterval = 30
    private var lastRun: Date = .distantPast
    private var changeObserver: NSObjectProtocol?
    private var started: Bool = false

    private(set) var authStatus: EKAuthorizationStatus
    private(set) var events: [CalendarEventViewModel] = []
    private(set) var tomorrowEvents: [CalendarEventViewModel] = []
    private(set) var selectedCalendarIDs: Set<String>

    private let selectedIDsKey = "calendarEventsSelectedIDs"

    private init() {
        authStatus = EKEventStore.authorizationStatus(for: .event)
        let raw = UserDefaults.standard.string(forKey: selectedIDsKey) ?? ""
        selectedCalendarIDs = Set(raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty })
    }

    var isAuthorizedToRead: Bool {
        authStatus == .fullAccess
    }

    func start() {
        guard !started else { return }
        started = true
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.lastRun = .distantPast
                self.refresh()
            }
        }
        refresh()
    }

    /// Re-read TCC status from the OS. Catches grants/revokes made outside
    /// the app (System Settings → Privacy → Calendars), so the in-app UI
    /// doesn't sit on the cached state captured at singleton init.
    func refreshAuthStatus() {
        authStatus = EKEventStore.authorizationStatus(for: .event)
        if isAuthorizedToRead { refresh() }
    }

    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            authStatus = EKEventStore.authorizationStatus(for: .event)
            if granted { refresh() }
            return granted
        } catch {
            authStatus = EKEventStore.authorizationStatus(for: .event)
            return false
        }
    }

    func availableCalendars() -> [EKCalendar] {
        guard isAuthorizedToRead else { return [] }
        return store.calendars(for: .event).sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    func setSelected(_ calendarID: String, _ selected: Bool) {
        var current = selectedCalendarIDs
        if selected { current.insert(calendarID) } else { current.remove(calendarID) }
        selectedCalendarIDs = current
        let joined = current.sorted().joined(separator: "\n")
        UserDefaults.standard.set(joined, forKey: selectedIDsKey)
        refresh()
    }

    func event(withIdentifier id: String) -> EKEvent? {
        guard isAuthorizedToRead else { return nil }
        return store.event(withIdentifier: id)
    }

    func refreshIfDue() {
        guard Date.now.timeIntervalSince(lastRun) >= cooldown else { return }
        refresh()
    }

    func refresh() {
        lastRun = .now
        guard isAuthorizedToRead else {
            events = []
            tomorrowEvents = []
            return
        }
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: .now)
        guard let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday),
              let startOfDayAfter = cal.date(byAdding: .day, value: 2, to: startOfToday) else {
            events = []
            tomorrowEvents = []
            return
        }
        let selected = selectedCalendarIDs
        guard !selected.isEmpty else {
            events = []
            tomorrowEvents = []
            return
        }
        let calendars = store.calendars(for: .event)
            .filter { selected.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else {
            events = []
            tomorrowEvents = []
            return
        }
        // One EventKit fetch covers today + tomorrow; partition by start date.
        let predicate = store.predicateForEvents(
            withStart: startOfToday,
            end: startOfDayAfter,
            calendars: calendars
        )
        let now = Date.now
        let all = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .compactMap { CalendarEventViewModel(from: $0) }

        events = all.filter { event in
            // Today: keep if it hasn't ended yet (or is all-day) AND its start
            // is before tomorrow.
            event.startDate < startOfTomorrow && (event.endDate >= now || event.isAllDay)
        }
        tomorrowEvents = all.filter { event in
            event.startDate >= startOfTomorrow && event.startDate < startOfDayAfter
        }
    }
}

private extension CalendarEventViewModel {
    init?(from event: EKEvent) {
        guard let id = event.eventIdentifier, !id.isEmpty else { return nil }
        let cgColor = event.calendar.cgColor ?? CGColor(gray: 0.5, alpha: 1)
        let trimmedLocation = event.location?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            id: id,
            title: event.title ?? "Untitled",
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            calendarTitle: event.calendar.title,
            calendarColor: Color(cgColor: cgColor),
            location: (trimmedLocation?.isEmpty == false) ? trimmedLocation : nil
        )
    }
}
