import Foundation
import SwiftData

@MainActor
final class MaintenanceService {
    static let shared = MaintenanceService()

    private var lastRun: Date = .distantPast
    private let cooldown: TimeInterval = 60

    private init() {}

    func runIfDue(context: ModelContext) {
        guard Date.now.timeIntervalSince(lastRun) >= cooldown else { return }
        lastRun = .now
        run(context: context)
    }

    func run(context: ModelContext) {
        let defaults = UserDefaults.standard
        let autoReschedule = defaults.bool(forKey: "autoRescheduleOverdue")
        let autoArchive = defaults.bool(forKey: "autoArchiveEnabled")
        let ageRaw = defaults.string(forKey: "autoArchiveAge") ?? ArchiveAge.month.rawValue
        let age = ArchiveAge(rawValue: ageRaw) ?? .month

        if autoReschedule {
            rescheduleOverdue(context: context)
        }
        if autoArchive {
            archiveInactive(context: context, age: age)
        }
        try? context.save()
    }

    func rescheduleOverdue(context: ModelContext) {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: .now)
        let now = Date.now
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate {
            $0.archivedDate == nil && $0.todoEnabled && $0.dueDate != nil
        })
        guard let notes = try? context.fetch(descriptor) else { return }

        let cancelledRaw = Status.cancelled.rawValue
        let doneRaw = Status.done.rawValue

        for n in notes {
            guard let due = n.dueDate else { continue }
            guard cal.startOfDay(for: due) < startOfToday else { continue }
            guard n.statusRaw != cancelledRaw, n.statusRaw != doneRaw else { continue }
            // Skip snoozed notes — they're deferred, don't pull their dueDate
            // forward while they're hidden from view.
            if let until = n.snoozedUntil, until > now { continue }
            n.dueDate = startOfToday
        }
    }

    /// Auto-archives inactive *todo* notes only. Pure reference/markdown notes are never
    /// auto-archived — only notes the user has flagged as todos can age out.
    /// Snoozed notes are skipped — they're deferred, not stale.
    func archiveInactive(context: ModelContext, age: ArchiveAge) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -age.days, to: .now) else { return }
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate {
            $0.archivedDate == nil && $0.todoEnabled && $0.modifiedDate < cutoff
        })
        guard let notes = try? context.fetch(descriptor) else { return }
        let now = Date.now
        for n in notes {
            if let until = n.snoozedUntil, until > now { continue }
            n.archivedDate = now
        }
    }
}
