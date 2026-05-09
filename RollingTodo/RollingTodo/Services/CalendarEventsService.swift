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

    private let selectedIDsKey = "calendarEventsSelectedIDs"

    private init() {
        authStatus = EKEventStore.authorizationStatus(for: .event)
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

    var selectedCalendarIDs: Set<String> {
        let raw = UserDefaults.standard.string(forKey: selectedIDsKey) ?? ""
        return Set(raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty })
    }

    func setSelected(_ calendarID: String, _ selected: Bool) {
        var current = selectedCalendarIDs
        if selected { current.insert(calendarID) } else { current.remove(calendarID) }
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
            return
        }
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else {
            events = []
            return
        }
        let selected = selectedCalendarIDs
        guard !selected.isEmpty else {
            events = []
            return
        }
        let calendars = store.calendars(for: .event)
            .filter { selected.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else {
            events = []
            return
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let now = Date.now
        events = store.events(matching: predicate)
            .filter { $0.endDate >= now || $0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .compactMap { CalendarEventViewModel(from: $0) }
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
