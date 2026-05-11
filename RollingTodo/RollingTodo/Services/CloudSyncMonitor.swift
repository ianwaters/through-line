import CloudKit
import CoreData
import Foundation
import Security
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

    /// Set to true when `status` has been `.syncing` for longer than
    /// `stuckSyncThreshold` with no terminal event. `NSPersistentCloudKitContainer`
    /// is known to wedge on first launch after a schema change — the setup event
    /// opens, no import/export ever follows, and the user is stuck staring at a
    /// "Pulling the latest from iCloud" message. We can't unwedge cloudd from
    /// code, but we can at least *say so* and tell the user to restart the app.
    private(set) var stuckSyncing: Bool = false
    private var stuckSyncTask: Task<Void, Never>?
    private let stuckSyncThreshold: TimeInterval = 60

    /// Short, stable identifier for the iCloud account currently signed in —
    /// `…<last 6 chars>` of the user's CKRecord.ID. Same across all the user's
    /// devices, so they can confirm two test machines are syncing to the same
    /// Apple ID at a glance. Nil while unknown / no account.
    private(set) var syncID: String?

    /// The full user record name (not just the last 6 chars). For
    /// character-level cross-device comparison when the truncated `syncID`
    /// looks the same on two devices but you want to be certain.
    private(set) var fullSyncID: String?

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

    /// Container identifiers this binary is *entitled* to access — read from
    /// the embedded `com.apple.developer.icloud-container-identifiers`
    /// entitlement. If the configured container isn't in this list, the OS
    /// will silently reject record-level operations even though setup
    /// succeeds. This is the smoking gun for "Xcode build syncs, TestFlight
    /// build doesn't" scenarios where the App Store Connect provisioning
    /// profile is stale. macOS-only — the SecTask APIs aren't in the iOS
    /// Swift overlay, and on iOS the embedded.mobileprovision parse is more
    /// involved than it's worth here.
    let entitledContainerIdentifiers: [String] = {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return [] }
        let key = "com.apple.developer.icloud-container-identifiers" as CFString
        guard let value = SecTaskCopyValueForEntitlement(task, key, nil) else { return [] }
        return (value as? [String])?.sorted() ?? []
        #else
        return []
        #endif
    }()

    /// True when the configured CloudKit container is present in the
    /// binary's entitlement list. On iOS the entitlement read isn't
    /// available, so we conservatively return true (assume entitled) to
    /// avoid showing a false-alarm warning.
    var hasEntitlementForConfiguredContainer: Bool {
        #if os(macOS)
        return entitledContainerIdentifiers.contains(PersistenceController.cloudContainerID)
        #else
        return true
        #endif
    }

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
        /// Each entry is `"zoneName | ownerName"`. The owner name is what
        /// `CKCurrentUserDefaultName` resolves to on this device — if two
        /// devices' SwiftData zones have different owner names, they are
        /// looking at different data despite the same Apple ID display.
        let zones: [String]
        let subscriptionIDs: [String]
        /// Records visible on the server in the SwiftData mirror zone
        /// (`com.apple.coredata.cloudkit.zone`). `nil` if the zone is missing
        /// or the change fetch failed independently of zone enumeration.
        let serverRecordCount: Int?
        /// True when the change-fetch said `moreComing` — the count is the
        /// first page only. For diagnostics this is fine; we just want
        /// "non-zero" vs "zero".
        let serverRecordsTruncated: Bool
        /// True if a zone whose name matches the SwiftData mirror zone exists.
        let mirrorZonePresent: Bool
        /// Records visible via CKQuery against the SwiftData mirror zone for
        /// the four record types NSPersistentCloudKitContainer creates
        /// (CD_Folder, CD_Note, CD_TodoItem, CD_HomepageNote). This is a
        /// different code path from `recordZoneChanges` and is *less* prone
        /// to cloudd's local-cache bias. Divergence between this number and
        /// `serverRecordCount` is a strong signal that the device's CloudKit
        /// daemon has a stale local replica. `nil` if the cross-check failed
        /// or no record types matched (schema not deployed).
        let queryRecordCount: Int?
        /// Per-record-type query counts, for visibility when the totals
        /// disagree.
        let queryRecordCountsByType: [String: Int]
        /// Human-readable first CKQuery error captured during the cross-
        /// check. Surfaces when all four type probes fail so the user can
        /// see *why* (typically: record type not Queryable in production
        /// schema, or no records of that type yet).
        let queryFirstError: String?
        /// Sorted `"<recordType>/<recordName>"` strings for every record the
        /// device sees in the SwiftData zone via recordZoneChanges. Capped
        /// to keep the panel manageable. Use to compare which specific
        /// records each device sees.
        let serverRecordNames: [String]
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
    /// is *actually* talking to, read from runtime entitlements.
    ///
    /// Resolution rule (matches CloudKit's own):
    ///   1. If `com.apple.developer.icloud-container-environment` is set
    ///      explicitly, use that. (TestFlight/Distribution builds have this.)
    ///   2. Otherwise, fall back to `aps-environment` — `production` ⇒
    ///      Production, `development` ⇒ Development. (Xcode-built Release
    ///      with a Development signing profile lands here, which is why a
    ///      locally-archived Release talks to Development CloudKit even
    ///      though it's a Release build configuration.)
    ///
    /// Two Release builds with different signing profiles can therefore
    /// talk to different CloudKit environments. This was responsible for a
    /// long debugging detour where TestFlight and Xcode-built Release
    /// looked identical in the build settings but synced to two different
    /// stores.
    var cloudKitEnvironment: String {
        #if os(macOS)
        if let explicit = readEntitlement("com.apple.developer.icloud-container-environment") as? String {
            return explicit
        }
        if let arr = readEntitlement("com.apple.developer.icloud-container-environment") as? [String], let first = arr.first {
            return first
        }
        if let aps = readEntitlement("com.apple.developer.aps-environment") as? String {
            return aps.lowercased() == "production" ? "Production" : "Development"
        }
        #endif
        // iOS or unreadable: fall back to build-config heuristic.
        #if DEBUG
        return "Development"
        #else
        return "Production"
        #endif
    }

    #if os(macOS)
    private func readEntitlement(_ key: String) -> Any? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(task, key as CFString, nil)
    }
    #endif

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

            // Match by zone *name* — we want the actual server-side ownerName,
            // not the CKCurrentUserDefaultName placeholder. Two devices that
            // resolve the placeholder differently will see different real
            // owner names here, which is the smoking gun for "same Apple ID
            // displayed but actually different data".
            let mirrorZoneName = "com.apple.coredata.cloudkit.zone"
            let mirrorZone = zones.first(where: { $0.zoneID.zoneName == mirrorZoneName })
            var serverCount: Int? = nil
            var truncated = false
            var queryCount: Int? = nil
            var queryByType: [String: Int] = [:]
            var queryFirstError: String? = nil
            var serverNames: [String] = []
            if let mirrorZone {
                let token: CKServerChangeToken? = nil
                let result = try await db.recordZoneChanges(
                    inZoneWith: mirrorZone.zoneID,
                    since: token
                )
                serverCount = result.modificationResultsByID.count
                truncated = result.moreComing
                for (id, modResult) in result.modificationResultsByID {
                    switch modResult {
                    case .success(let mod):
                        serverNames.append("\(mod.record.recordType)/\(id.recordName)")
                    case .failure:
                        serverNames.append("?/\(id.recordName)")
                    }
                }
                serverNames.sort()
                if serverNames.count > 50 {
                    serverNames = Array(serverNames.prefix(50)) + ["…(\(serverNames.count - 50) more)"]
                }

                // Cross-check via CKQuery — different code path; if the local
                // cloudd daemon is serving recordZoneChanges from a stale
                // replica, this number can disagree.
                let recordTypes = ["CD_Folder", "CD_Note", "CD_TodoItem", "CD_HomepageNote"]
                var totalQueryCount = 0
                var anyTypeQueried = false
                var firstErrorMessage: String? = nil
                for type in recordTypes {
                    let q = CKQuery(recordType: type, predicate: NSPredicate(value: true))
                    do {
                        let r = try await db.records(
                            matching: q,
                            inZoneWith: mirrorZone.zoneID,
                            desiredKeys: [],
                            resultsLimit: 200
                        )
                        let n = r.matchResults.count
                        queryByType[type] = n
                        totalQueryCount += n
                        anyTypeQueried = true
                    } catch {
                        // Schema not deployed for this type, or another
                        // transient error — note it and move on. Capture the
                        // first error so the user can see *why*.
                        queryByType[type] = -1
                        if firstErrorMessage == nil {
                            firstErrorMessage = "\(type): \(humanReadable(error))"
                        }
                    }
                }
                if anyTypeQueried { queryCount = totalQueryCount }
                queryFirstError = firstErrorMessage
            }

            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            let zoneLines = zones
                .map { "\($0.zoneID.zoneName) | \($0.zoneID.ownerName)" }
                .sorted()
            let report = PingReport(
                durationMs: durationMs,
                zones: zoneLines,
                subscriptionIDs: subs.map { $0.subscriptionID }.sorted(),
                serverRecordCount: serverCount,
                serverRecordsTruncated: truncated,
                mirrorZonePresent: mirrorZone != nil,
                queryRecordCount: queryCount,
                queryRecordCountsByType: queryByType,
                queryFirstError: queryFirstError,
                serverRecordNames: serverNames
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
                if case .noAccount = status { setStatus(.ready) }
                if status == .unknown { setStatus(.ready) }
                await fetchSyncID(from: container)
            case .noAccount:
                setStatus(.noAccount(reason: "Sign in to iCloud in Settings to back up and sync your notes."))
                syncID = nil
                fullSyncID = nil
            case .restricted:
                setStatus(.noAccount(reason: "iCloud is restricted on this device. Notes won't sync until restrictions are lifted."))
                syncID = nil
                fullSyncID = nil
            case .temporarilyUnavailable:
                setStatus(.noAccount(reason: "iCloud is temporarily unavailable. We'll retry automatically."))
                syncID = nil
                fullSyncID = nil
            case .couldNotDetermine:
                setStatus(.noAccount(reason: "Couldn't reach iCloud. Check your network connection."))
                syncID = nil
                fullSyncID = nil
            @unknown default:
                setStatus(.noAccount(reason: "iCloud account state is unknown."))
                syncID = nil
                fullSyncID = nil
            }
        } catch {
            setStatus(.failed(message: humanReadable(error)))
            lastErrorDiagnostics = diagnosticsDump(error)
            syncID = nil
            fullSyncID = nil
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
            fullSyncID = name
        } catch {
            // Identity fetch is best-effort; sync can still work without it.
            syncID = nil
            fullSyncID = nil
        }
    }

    private func handleEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
        record(event: event)
        if event.endDate == nil {
            setStatus(.syncing)
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
            setStatus(.ready)
        } else {
            switch event.type {
            case .setup:  setupFailureCount += 1
            case .import: importFailureCount += 1
            case .export: exportFailureCount += 1
            @unknown default: break
            }
            setStatus(.failed(message: humanReadable(event.error)))
            lastErrorDiagnostics = diagnosticsDump(event.error)
            Self.logger.error("CloudKit sync failed: \(self.humanReadable(event.error), privacy: .public)")
        }
    }

    /// Centralised status mutation so the stall-detection task is always
    /// armed/disarmed in lockstep with the underlying state.
    private func setStatus(_ new: Status) {
        let wasSyncing = isSyncing(status)
        status = new
        let isSyncingNow = isSyncing(new)
        if isSyncingNow && !wasSyncing {
            startStuckSyncWatch()
        } else if !isSyncingNow {
            clearStuckSyncWatch()
        }
    }

    private func isSyncing(_ s: Status) -> Bool {
        if case .syncing = s { return true }
        return false
    }

    private func startStuckSyncWatch() {
        stuckSyncTask?.cancel()
        stuckSyncing = false
        stuckSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Int(self?.stuckSyncThreshold ?? 60)))
            guard let self else { return }
            if Task.isCancelled { return }
            // Still syncing after the threshold AND no terminal event has fired
            // since we started watching — call it stuck.
            if case .syncing = self.status {
                self.stuckSyncing = true
                Self.logger.error("CloudKit sync stuck for >\(Int(self.stuckSyncThreshold), privacy: .public)s with no terminal event")
            }
        }
    }

    private func clearStuckSyncWatch() {
        stuckSyncTask?.cancel()
        stuckSyncTask = nil
        if stuckSyncing { stuckSyncing = false }
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
            // Empty partialFailure with no child errors is almost always one
            // of these. Listed roughly by frequency on a Release/TestFlight
            // build talking to Production.
            return "Sync stalled and iCloud didn't say why. The most common cause when this hits a Release build is that the Production schema isn't deployed for this CloudKit container — until it is, exports of any record type silently fail. Check, in order:\n" +
                   "  • CloudKit Console → this container → Schema → Deploy Schema Changes… (Dev → Prod). New containers start with empty Production schema.\n" +
                   "  • iCloud Drive is on in System Settings → Apple ID → iCloud.\n" +
                   "  • RollingTodo is ticked in System Settings → Apple ID → iCloud → Apps Using iCloud.\n" +
                   "  • The network isn't behind a corporate proxy or VPN that blocks iCloud.\n" +
                   "  • The Mac's clock is correct (large skew breaks CloudKit).\n" +
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

    /// Full, copyable diagnostic dump — env, event totals, recent events,
    /// last ping report (if any), and last error chain (if any). Used by
    /// the always-available Copy Diagnostics button in Settings, so it
    /// works whether or not sync has errored.
    func composeFullDiagnostics() -> String {
        var lines: [String] = []
        lines.append(contentsOf: environmentLines())
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

        lines.append("")
        lines.append(contentsOf: pingReportLines())

        if let last = lastErrorDiagnostics {
            lines.append("")
            lines.append("=== Last error diagnostics ===")
            lines.append(last)
        }
        return lines.joined(separator: "\n")
    }

    private func pingReportLines() -> [String] {
        var lines: [String] = ["=== Last ping ==="]
        switch pingPhase {
        case .idle:
            lines.append("No ping run yet. Tap Test iCloud connection to populate.")
        case .running:
            lines.append("Ping in progress…")
        case .failed(let msg):
            lines.append("Ping failed: \(msg)")
        case .ok(let report):
            lines.append("Reached private database in \(report.durationMs)ms.")
            lines.append("Mirror zone present: \(report.mirrorZonePresent)")
            lines.append("Zones (\(report.zones.count)):")
            for z in report.zones { lines.append("  \(z)") }
            lines.append("Subscriptions (\(report.subscriptionIDs.count)):")
            if report.subscriptionIDs.isEmpty {
                lines.append("  (none)")
            } else {
                for s in report.subscriptionIDs { lines.append("  \(s)") }
            }
            lines.append("Server record count (zonechanges): \(report.serverRecordCount.map { "\($0)\(report.serverRecordsTruncated ? "+" : "")" } ?? "—")")
            lines.append("CKQuery total: \(report.queryRecordCount.map { "\($0)" } ?? "—")")
            for (k, v) in report.queryRecordCountsByType.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(k): \(v < 0 ? "err" : "\(v)")")
            }
            if let e = report.queryFirstError {
                lines.append("First CKQuery error: \(e)")
            }
            lines.append("Server records (this device's view, capped):")
            if report.serverRecordNames.isEmpty {
                lines.append("  (none)")
            } else {
                for name in report.serverRecordNames { lines.append("  \(name)") }
            }
        }
        return lines
    }

    private func environmentLines() -> [String] {
        var lines = ["=== Environment ==="]
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        lines.append("App build: \(v) (\(b))")
        lines.append("Container: \(PersistenceController.cloudContainerID)")
        lines.append("CloudKit env: \(cloudKitEnvironment)")
        if entitledContainerIdentifiers.isEmpty {
            lines.append("Entitled containers: (none) ⚠")
        } else {
            lines.append("Entitled containers: \(entitledContainerIdentifiers.joined(separator: ", "))")
        }
        let entitlementWarning = hasEntitlementForConfiguredContainer
            ? ""
            : " ⚠ — provisioning profile does not authorize this container; record-level CloudKit operations will silently fail"
        lines.append("Configured container is entitled: \(hasEntitlementForConfiguredContainer)\(entitlementWarning)")
        lines.append("Sync ID: \(syncID ?? "—")")
        lines.append("Full user record: \(fullSyncID ?? "—")")
        lines.append("Ubiquity identity present: \(hasUbiquityIdentity)")
        lines.append("Status: \(humanStatusForDump())")
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

    private func humanStatusForDump() -> String {
        switch status {
        case .unknown: "unknown"
        case .ready: "ready"
        case .syncing: "syncing"
        case .failed(let m): "failed: \(m)"
        case .noAccount(let r): "noAccount: \(r)"
        }
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
