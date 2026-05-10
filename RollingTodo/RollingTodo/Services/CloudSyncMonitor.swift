import CloudKit
import CoreData
import Foundation

/// Observes CloudKit sync events and account state for the SwiftData container,
/// surfacing them as a humanised status the Settings pane can render. SwiftData
/// wraps `NSPersistentCloudKitContainer` internally, so the standard
/// `eventChangedNotification` mechanism still applies.
@MainActor
@Observable
final class CloudSyncMonitor {
    static let shared = CloudSyncMonitor()

    enum Status: Equatable {
        case unknown
        case ready
        case syncing
        case failed(message: String)
        case noAccount(reason: String)
    }

    private(set) var status: Status = .unknown
    private(set) var lastSuccessfulSyncAt: Date?

    var statusTitle: String {
        switch status {
        case .unknown:    "iCloud Sync"
        case .ready:      "iCloud Sync ready"
        case .syncing:    "iCloud Sync running…"
        case .failed:     "iCloud Sync issue"
        case .noAccount:  "iCloud not available"
        }
    }

    var statusNote: String {
        switch status {
        case .unknown:
            return "Checking your iCloud account…"
        case .ready:
            if let date = lastSuccessfulSyncAt {
                return "Last synced \(date.formatted(.relative(presentation: .named)))."
            }
            return "Notes sync to your other devices automatically."
        case .syncing:
            return "Pulling the latest from iCloud…"
        case .failed(let message):
            return message
        case .noAccount(let reason):
            return reason
        }
    }

    /// Drives the status dot in Settings. Sage when sync is working or in
    /// progress; amber for any failure or missing-account condition.
    var isHealthy: Bool {
        switch status {
        case .ready, .syncing: true
        case .unknown, .failed, .noAccount: false
        }
    }

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                self?.handleEvent(note)
            }
        }
        Task { @MainActor [weak self] in
            await self?.refreshAccountStatus()
        }
    }

    /// Re-queries the user's iCloud account. Called on init and from the
    /// "Re-check" button in Settings.
    func refreshAccountStatus() async {
        do {
            let container = CKContainer(identifier: PersistenceController.cloudContainerID)
            let accountStatus = try await container.accountStatus()
            switch accountStatus {
            case .available:
                // Don't downgrade .ready/.syncing — we already have evidence sync is working.
                if case .noAccount = status { status = .ready }
                if status == .unknown { status = .ready }
            case .noAccount:
                status = .noAccount(reason: "Sign in to iCloud in Settings to back up and sync your notes.")
            case .restricted:
                status = .noAccount(reason: "iCloud is restricted on this device. Notes won't sync until restrictions are lifted.")
            case .temporarilyUnavailable:
                status = .noAccount(reason: "iCloud is temporarily unavailable. We'll retry automatically.")
            case .couldNotDetermine:
                status = .noAccount(reason: "Couldn't reach iCloud. Check your network connection.")
            @unknown default:
                status = .noAccount(reason: "iCloud account state is unknown.")
            }
        } catch {
            status = .failed(message: humanReadable(error))
        }
    }

    private func handleEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
        if event.endDate == nil {
            status = .syncing
            return
        }
        if event.succeeded {
            lastSuccessfulSyncAt = event.endDate
            status = .ready
        } else {
            status = .failed(message: humanReadable(event.error))
        }
    }

    private func humanReadable(_ error: Error?) -> String {
        guard let error else { return "Sync failed for an unknown reason." }
        if let ck = error as? CKError {
            switch ck.code {
            case .quotaExceeded:
                return "Your iCloud storage is full. Free up space or upgrade your plan to keep syncing."
            case .networkUnavailable, .networkFailure:
                return "Sync paused — your network is offline. We'll retry when it returns."
            case .notAuthenticated:
                return "Sign in to iCloud in Settings to sync your notes."
            case .accountTemporarilyUnavailable:
                return "iCloud is temporarily unavailable. We'll retry automatically."
            case .serverResponseLost, .serviceUnavailable:
                return "iCloud is having a wobble. We'll retry automatically."
            case .zoneNotFound, .userDeletedZone:
                return "iCloud needs to rebuild your private database. Recent edits may re-upload."
            default:
                return ck.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
