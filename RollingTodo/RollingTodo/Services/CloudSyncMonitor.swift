import CloudKit
import CoreData
import Foundation
import os

#if os(macOS)
import AppKit
#else
import UIKit
#endif

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

    /// Drives the Re-check button label so users get feedback even when the
    /// underlying status doesn't change. `.settled` auto-resets to `.idle`
    /// after a short window via `recheckResetTask`.
    enum RecheckPhase: Equatable {
        case idle
        case checking
        case settled(unchanged: Bool)
    }

    private(set) var status: Status = .unknown
    private(set) var lastSuccessfulSyncAt: Date?

    /// Short, stable identifier for the iCloud account currently signed in —
    /// `…<last 6 chars>` of the user's CKRecord.ID. Same across all the user's
    /// devices, so they can confirm two test machines are syncing to the same
    /// Apple ID at a glance. Nil while unknown / no account.
    private(set) var syncID: String?

    /// Raw, copyable error dump for support / self-diagnosis. Populated on every
    /// `.failed` transition. Includes domain, code, userInfo digest, and the
    /// first few child errors of any partial-failure.
    private(set) var lastErrorDiagnostics: String?

    private(set) var recheckPhase: RecheckPhase = .idle
    private var recheckResetTask: Task<Void, Never>?

    /// Ring buffer of the last 10 NSPersistentCloudKitContainer events. Useful
    /// when partialFailure errors land with empty userInfo — knowing whether
    /// imports/exports/setups succeeded around the failure is the only clue.
    private var recentEvents: [EventRecord] = []
    private let recentEventsLimit = 10

    private struct EventRecord {
        let timestamp: Date
        let line: String
    }

    private static let logger = Logger(subsystem: "com.ianwaters.RollingTodo4", category: "cloudsync")

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

    /// Re-queries the user's iCloud account. Drives the Re-check button — the
    /// `recheckPhase` flips to `.checking` for at least 250ms so the spinner is
    /// always visible, then to `.settled(unchanged:)` for 1.5s before resetting.
    func refreshAccountStatus() async {
        recheckResetTask?.cancel()
        let priorStatus = status
        recheckPhase = .checking
        let startedAt = Date()

        await performAccountRefresh()

        // Hold the spinner long enough to register visually.
        let elapsed = Date().timeIntervalSince(startedAt)
        let minSpinnerDuration: TimeInterval = 0.25
        if elapsed < minSpinnerDuration {
            try? await Task.sleep(for: .milliseconds(Int((minSpinnerDuration - elapsed) * 1000)))
        }

        recheckPhase = .settled(unchanged: priorStatus == status)
        recheckResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            if Task.isCancelled { return }
            self?.recheckPhase = .idle
        }
    }

    private func performAccountRefresh() async {
        do {
            let container = CKContainer(identifier: PersistenceController.cloudContainerID)
            let accountStatus = try await container.accountStatus()
            switch accountStatus {
            case .available:
                // Don't downgrade .ready/.syncing — we already have evidence sync is working.
                if case .noAccount = status { status = .ready }
                if status == .unknown { status = .ready }
                await fetchSyncID(from: container)
            case .noAccount:
                status = .noAccount(reason: "Sign in to iCloud in Settings to back up and sync your notes.")
                syncID = nil
            case .restricted:
                status = .noAccount(reason: "iCloud is restricted on this device. Notes won't sync until restrictions are lifted.")
                syncID = nil
            case .temporarilyUnavailable:
                status = .noAccount(reason: "iCloud is temporarily unavailable. We'll retry automatically.")
                syncID = nil
            case .couldNotDetermine:
                status = .noAccount(reason: "Couldn't reach iCloud. Check your network connection.")
                syncID = nil
            @unknown default:
                status = .noAccount(reason: "iCloud account state is unknown.")
                syncID = nil
            }
        } catch {
            status = .failed(message: humanReadable(error))
            lastErrorDiagnostics = diagnosticsDump(error)
            syncID = nil
        }
    }

    private func fetchSyncID(from container: CKContainer) async {
        do {
            let recordID = try await container.userRecordID()
            let name = recordID.recordName
            // CKRecord.ID names are typically a long hyphenated string. Last 6
            // chars give a stable, low-collision fingerprint.
            let tail = String(name.suffix(6))
            syncID = "…\(tail)"
        } catch {
            // Identity fetch is best-effort; sync can still work without it.
            syncID = nil
        }
    }

    private func handleEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
        record(event: event)
        if event.endDate == nil {
            status = .syncing
            return
        }
        if event.succeeded {
            lastSuccessfulSyncAt = event.endDate
            status = .ready
        } else {
            status = .failed(message: humanReadable(event.error))
            lastErrorDiagnostics = diagnosticsDump(event.error)
            Self.logger.error("CloudKit sync failed: \(self.humanReadable(event.error), privacy: .public)")
        }
    }

    private func record(event: NSPersistentCloudKitContainer.Event) {
        let typeText: String = switch event.type {
        case .setup:  "setup"
        case .import: "import"
        case .export: "export"
        @unknown default: "event(\(event.type.rawValue))"
        }
        let outcome: String
        if event.endDate == nil {
            outcome = "started"
        } else if event.succeeded {
            outcome = "ok"
        } else {
            let nsErr = (event.error as NSError?)
            outcome = "FAILED \(nsErr?.domain ?? "?") \(nsErr?.code ?? 0)"
        }
        let line = "[\(typeText)] \(outcome)"
        recentEvents.append(EventRecord(timestamp: event.endDate ?? .now, line: line))
        if recentEvents.count > recentEventsLimit {
            recentEvents.removeFirst(recentEvents.count - recentEventsLimit)
        }
        Self.logger.info("event \(line, privacy: .public)")
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
            case .partialFailure:
                return partialFailureMessage(ck)
            case .serverRejectedRequest:
                return "iCloud rejected the sync request. Try again in a moment; if it persists, sign out and back into iCloud."
            case .batchRequestFailed:
                return "A batch of changes was rejected because one item failed. Other items will retry."
            case .constraintViolation:
                return "A record clashed with one already on iCloud. The local change won't upload until it's resolved."
            case .incompatibleVersion:
                return "This version of RollingTodo is incompatible with the data on iCloud. Update the app on all devices."
            case .changeTokenExpired:
                return "iCloud asked us to resync from scratch. Recent edits will re-upload automatically."
            case .zoneBusy, .requestRateLimited:
                return "iCloud is throttling sync. We'll back off and retry."
            case .assetFileNotFound, .assetFileModified:
                return "An attachment couldn't be uploaded because the file changed or moved. The note will retry."
            case .referenceViolation:
                return "A note references something that's no longer on iCloud. The link will be cleared on the next sync."
            case .managedAccountRestricted:
                return "Your managed iCloud account doesn't allow this app to sync. Contact your administrator."
            case .serverRecordChanged:
                return "Another device edited the same note. iCloud will reconcile both copies on the next sync."
            case .unknownItem:
                return "iCloud couldn't find a record we expected. It may have been deleted from another device."
            default:
                return "Sync failed: \(ck.localizedDescription) (CKError \(ck.code.rawValue))."
            }
        }
        return error.localizedDescription
    }

    /// Walks `partialErrorsByItemID` and surfaces up to 3 child failures so
    /// users see the actual cause instead of a bare "CKErrorDomain error 2".
    private func partialFailureMessage(_ ck: CKError) -> String {
        let children = ck.partialErrorsByItemID ?? [:]
        if children.isEmpty {
            // Empty partialFailure on macOS is almost always one of:
            //  • Network reachability — VPN / corporate firewall blocks iCloud
            //  • iCloud Drive disabled in System Settings (CloudKit needs it)
            //  • Schema mismatch between Debug builds and the live container
            //  • Stale local zone after a sign-out/sign-in
            return "Sync stalled and iCloud didn't say why. On this machine, check: \n" +
                   "  • iCloud Drive is on in System Settings → Apple ID → iCloud\n" +
                   "  • RollingTodo is ticked in System Settings → Apple ID → iCloud → Apps Using iCloud\n" +
                   "  • The network isn't behind a corporate proxy or VPN that blocks iCloud\n" +
                   "  • The Mac's clock is correct (large skew breaks CloudKit)\n" +
                   "Copy the full diagnostics for the recent event timeline."
        }
        let preview = children.prefix(3).map { (id, err) -> String in
            let idText = "\(id)"
            let trimmedID = idText.count > 24 ? "\(idText.prefix(20))…" : idText
            return "  • \(trimmedID): \(humanReadable(err))"
        }.joined(separator: "\n")
        let extra = children.count > 3 ? "\n  …and \(children.count - 3) more." : ""
        return "Some records couldn't sync:\n\(preview)\(extra)"
    }

    /// Verbose dump for the "Copy diagnostics" button. Multi-line, no PII —
    /// CKErrors don't include identifying content beyond opaque record IDs.
    private func diagnosticsDump(_ error: Error?) -> String {
        var lines: [String] = []
        lines.append(contentsOf: environmentLines())
        lines.append("")

        if let error {
            lines.append("=== Error chain ===")
            lines.append(contentsOf: errorChainLines(error))
        } else {
            lines.append("=== Error ===")
            lines.append("No error attached.")
        }

        lines.append("")
        lines.append("=== Recent events (last \(recentEvents.count)) ===")
        if recentEvents.isEmpty {
            lines.append("No events recorded yet.")
        } else {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            for entry in recentEvents.suffix(recentEventsLimit) {
                lines.append("\(formatter.string(from: entry.timestamp)) \(entry.line)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func environmentLines() -> [String] {
        var lines = ["=== Environment ==="]
        lines.append("Container: \(PersistenceController.cloudContainerID)")
        lines.append("Sync ID: \(syncID ?? "—")")
        lines.append("Captured at: \(Date.now.formatted(.iso8601))")
        #if DEBUG
        lines.append("Build: Debug (CloudKit development environment)")
        #else
        lines.append("Build: Release (CloudKit production environment)")
        #endif
        #if os(macOS)
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        lines.append("OS: macOS \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)")
        lines.append("Host: \(ProcessInfo.processInfo.hostName)")
        #else
        let osVersion = UIDevice.current.systemVersion
        lines.append("OS: \(UIDevice.current.systemName) \(osVersion)")
        lines.append("Device: \(UIDevice.current.model)")
        #endif
        return lines
    }

    /// Walks `NSUnderlyingErrorKey` and `partialErrorsByItemID` so the dump
    /// shows the *actual* cause, not just the top-level wrapper. Indented per
    /// depth so the chain is easy to read.
    private func errorChainLines(_ error: Error, depth: Int = 0, maxDepth: Int = 6) -> [String] {
        guard depth < maxDepth else { return [String(repeating: "  ", count: depth) + "(chain truncated)"] }
        let pad = String(repeating: "  ", count: depth)
        var lines: [String] = []
        let ns = error as NSError
        lines.append("\(pad)Domain: \(ns.domain)")
        lines.append("\(pad)Code: \(ns.code)")
        lines.append("\(pad)Description: \(ns.localizedDescription)")
        if let reason = ns.localizedFailureReason {
            lines.append("\(pad)Reason: \(reason)")
        }
        if let suggestion = ns.localizedRecoverySuggestion {
            lines.append("\(pad)Suggestion: \(suggestion)")
        }
        // Filter out keys we walk separately (errors).
        let printable = ns.userInfo.filter { _, value in
            !(value is Error) && !(value is [AnyHashable: Error]) && !(value is [Error])
        }
        if !printable.isEmpty {
            lines.append("\(pad)UserInfo:")
            for (key, value) in printable {
                lines.append("\(pad)  \(key): \(value)")
            }
        }

        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            lines.append("\(pad)Underlying:")
            lines.append(contentsOf: errorChainLines(underlying, depth: depth + 1, maxDepth: maxDepth))
        }
        if #available(macOS 11.3, iOS 14.5, *),
           let multiple = ns.userInfo[NSMultipleUnderlyingErrorsKey] as? [Error] {
            lines.append("\(pad)Underlying (\(multiple.count)):")
            for sub in multiple.prefix(3) {
                lines.append(contentsOf: errorChainLines(sub, depth: depth + 1, maxDepth: maxDepth))
            }
            if multiple.count > 3 {
                lines.append("\(pad)  …and \(multiple.count - 3) more.")
            }
        }
        if let ck = error as? CKError, let children = ck.partialErrorsByItemID, !children.isEmpty {
            lines.append("\(pad)Partial errors (\(children.count)):")
            for (id, err) in children.prefix(5) {
                lines.append("\(pad)  \(id):")
                lines.append(contentsOf: errorChainLines(err, depth: depth + 2, maxDepth: maxDepth))
            }
            if children.count > 5 {
                lines.append("\(pad)  …and \(children.count - 5) more.")
            }
        }
        return lines
    }
}
