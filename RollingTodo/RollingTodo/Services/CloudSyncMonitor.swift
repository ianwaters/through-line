import CloudKit
import CoreData
import Foundation
import os

#if os(macOS)
import AppKit
#else
import UIKit
import UserNotifications
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

    /// Per-event-type telemetry. The most useful single signal when sync looks
    /// "fine" but isn't moving data: if `lastImportSucceededAt` and
    /// `lastExportSucceededAt` are both nil after the app has been open for a
    /// while, the container has never actually completed a sync — different
    /// problem than "sync failed".
    private(set) var lastSetupSucceededAt: Date?
    private(set) var lastImportSucceededAt: Date?
    private(set) var lastExportSucceededAt: Date?
    private(set) var setupSuccessCount: Int = 0
    private(set) var importSuccessCount: Int = 0
    private(set) var exportSuccessCount: Int = 0
    private(set) var setupFailureCount: Int = 0
    private(set) var importFailureCount: Int = 0
    private(set) var exportFailureCount: Int = 0

    /// True if the iCloud account is signed in at the OS level. Cheaper than a
    /// CKContainer round-trip; nil when iCloud is signed out entirely.
    private(set) var hasUbiquityIdentity: Bool = false

    #if os(iOS)
    private(set) var pushAuthStatus: String = "Unknown"
    #endif

    enum PingPhase: Equatable {
        case idle
        case running
        case ok(report: PingReport)
        case failed(message: String)
    }

    struct PingReport: Equatable {
        let durationMs: Int
        let zoneNames: [String]
        let subscriptionIDs: [String]
        /// Records visible on the server in the SwiftData mirror zone
        /// (`com.apple.coredata.cloudkit.zone`). `nil` if the zone is missing
        /// or the change fetch failed independently of zone enumeration.
        let serverRecordCount: Int?
        /// True when the change-fetch said `moreComing` — the count is the
        /// first page only. For diagnostics this is fine; we just want
        /// "non-zero" vs "zero".
        let serverRecordsTruncated: Bool
    }

    /// Result of the synthetic CloudKit ping — bypasses SwiftData entirely.
    /// If sync events never fire but ping succeeds, the persistent container
    /// hasn't been kicked into life. If ping fails, raw CloudKit access is
    /// broken on this device (network, account, or container permissions).
    private(set) var pingPhase: PingPhase = .idle
    private var pingResetTask: Task<Void, Never>?

    /// Ring buffer of the last 10 NSPersistentCloudKitContainer events. Useful
    /// when partialFailure errors land with empty userInfo — knowing whether
    /// imports/exports/setups succeeded around the failure is the only clue.
    private(set) var recentEvents: [EventRecord] = []
    private let recentEventsLimit = 10

    struct EventRecord: Identifiable {
        let id = UUID()
        let timestamp: Date
        let type: String
        let outcome: String
        var line: String { "[\(type)] \(outcome)" }
    }

    /// "Production" or "Development" — which CloudKit environment the binary
    /// is talking to. Driven by build configuration: Release ships against
    /// Production, Debug against Development. Confirms at a glance that two
    /// supposedly-identical Release builds aren't accidentally pointing at
    /// different stores.
    var cloudKitEnvironment: String {
        #if DEBUG
        return "Development"
        #else
        return "Production"
        #endif
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
        #if os(iOS)
        Task { @MainActor [weak self] in
            await self?.refreshPushAuthStatus()
        }
        #endif
    }

    #if os(iOS)
    private func refreshPushAuthStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: pushAuthStatus = "Not requested"
        case .denied:        pushAuthStatus = "Denied"
        case .authorized:    pushAuthStatus = "Authorized"
        case .provisional:   pushAuthStatus = "Provisional"
        case .ephemeral:     pushAuthStatus = "Ephemeral"
        @unknown default:    pushAuthStatus = "Unknown"
        }
    }
    #endif

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

    /// Synthetic CloudKit probe — bypasses SwiftData and talks straight to
    /// CKContainer. Reports zones, subscriptions, and server-side record count
    /// in the SwiftData mirror zone. Used to distinguish three silent-stall
    /// failure modes that all look the same to NSPersistentCloudKitContainer:
    ///   • zero subscriptions → no silent-push path; device never gets
    ///     notified of remote changes
    ///   • subscriptions present but local count << server count → push or
    ///     import is broken; data is there but the device can't pull it
    ///   • server count == local count → sync genuinely up to date
    func pingCloudKit() async {
        pingResetTask?.cancel()
        pingPhase = .running
        let startedAt = Date()
        do {
            let container = CKContainer(identifier: PersistenceController.cloudContainerID)
            let db = container.privateCloudDatabase

            let zones = try await db.allRecordZones()
            let subs = try await db.allSubscriptions()

            let cdZoneID = CKRecordZone.ID(
                zoneName: "com.apple.coredata.cloudkit.zone",
                ownerName: CKCurrentUserDefaultName
            )
            var serverCount: Int? = nil
            var truncated = false
            if zones.contains(where: { $0.zoneID == cdZoneID }) {
                let token: CKServerChangeToken? = nil
                let result = try await db.recordZoneChanges(
                    inZoneWith: cdZoneID,
                    since: token
                )
                serverCount = result.modificationResultsByID.count
                truncated = result.moreComing
            }

            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            let report = PingReport(
                durationMs: durationMs,
                zoneNames: zones.map { $0.zoneID.zoneName }.sorted(),
                subscriptionIDs: subs.map { $0.subscriptionID }.sorted(),
                serverRecordCount: serverCount,
                serverRecordsTruncated: truncated
            )
            pingPhase = .ok(report: report)
            Self.logger.info(
                "ping ok: zones=\(zones.count, privacy: .public) subs=\(subs.count, privacy: .public) serverRecs=\(serverCount ?? -1, privacy: .public) in \(durationMs, privacy: .public)ms"
            )
        } catch {
            pingPhase = .failed(message: humanReadable(error))
            lastErrorDiagnostics = diagnosticsDump(error)
            Self.logger.error("ping failed: \(self.humanReadable(error), privacy: .public)")
        }
        // Hold the result on screen until dismissed — too much info to skim
        // away after a few seconds.
        pingResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(60))
            if Task.isCancelled { return }
            self?.pingPhase = .idle
        }
    }

    private func performAccountRefresh() async {
        hasUbiquityIdentity = FileManager.default.ubiquityIdentityToken != nil
        #if os(iOS)
        await refreshPushAuthStatus()
        #endif
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
            switch event.type {
            case .setup:
                lastSetupSucceededAt = event.endDate
                setupSuccessCount += 1
            case .import:
                lastImportSucceededAt = event.endDate
                importSuccessCount += 1
            case .export:
                lastExportSucceededAt = event.endDate
                exportSuccessCount += 1
            @unknown default:
                break
            }
            status = .ready
        } else {
            switch event.type {
            case .setup:  setupFailureCount += 1
            case .import: importFailureCount += 1
            case .export: exportFailureCount += 1
            @unknown default: break
            }
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
        let entry = EventRecord(timestamp: event.endDate ?? .now, type: typeText, outcome: outcome)
        recentEvents.append(entry)
        if recentEvents.count > recentEventsLimit {
            recentEvents.removeFirst(recentEvents.count - recentEventsLimit)
        }
        Self.logger.info("event \(entry.line, privacy: .public)")
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
        lines.append("CloudKit env: \(cloudKitEnvironment)")
        lines.append("Sync ID: \(syncID ?? "—")")
        lines.append("Ubiquity identity present: \(hasUbiquityIdentity)")
        lines.append("Captured at: \(Date.now.formatted(.iso8601))")
        #if DEBUG
        lines.append("Build: Debug")
        #else
        lines.append("Build: Release")
        #endif
        #if os(macOS)
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        lines.append("OS: macOS \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)")
        lines.append("Host: \(ProcessInfo.processInfo.hostName)")
        #else
        let osVersion = UIDevice.current.systemVersion
        lines.append("OS: \(UIDevice.current.systemName) \(osVersion)")
        lines.append("Device: \(UIDevice.current.model)")
        lines.append("Push authorization: \(pushAuthStatus)")
        #endif
        lines.append("")
        lines.append("=== Event totals ===")
        lines.append("setup  ok:\(setupSuccessCount) fail:\(setupFailureCount) last-ok:\(formatDate(lastSetupSucceededAt))")
        lines.append("import ok:\(importSuccessCount) fail:\(importFailureCount) last-ok:\(formatDate(lastImportSucceededAt))")
        lines.append("export ok:\(exportSuccessCount) fail:\(exportFailureCount) last-ok:\(formatDate(lastExportSucceededAt))")
        return lines
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "never" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
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
