import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import EventKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("showHomepageNote") private var showHomepageNote: Bool = true
    @AppStorage("autoRescheduleOverdue") private var autoRescheduleOverdue: Bool = false
    @AppStorage("dueTodayIsUrgent") private var dueTodayIsUrgent: Bool = false
    @AppStorage("autoArchiveEnabled") private var autoArchiveEnabled: Bool = false
    @AppStorage("autoArchiveAge") private var autoArchiveAge: ArchiveAge = .month
    @AppStorage("focusDueWindow") private var focusDueWindow: FocusDueWindow = .thisWeek
    @AppStorage("focusPriorityFloor") private var focusPriorityFloor: FocusPriorityFloor = .highOrUrgent
    @AppStorage("calendarEventsEnabled") private var calendarEventsEnabled: Bool = false
    @AppStorage("hideAccountIdentifier") private var hideAccountIdentifier: Bool = false

    @State private var calendarService = CalendarEventsService.shared
    @State private var intelligence = IntelligenceService.shared
    @State private var cloudSync = CloudSyncMonitor.shared

    @State private var exportDocument: ExportDocument?
    @State private var showExporter: Bool = false
    @State private var building: Bool = false
    @State private var exportError: String?
    @State private var diagnosticsCopied: Bool = false
    @State private var showDiagnostics: Bool = false

    var body: some View {
        Form {
            Section {
                Toggle("Show notes section on home screen", isOn: $showHomepageNote)
            } header: {
                Text("Home Screen").eyebrowStyle(tint: Color.inkMuted)
            }

            Section {
                Toggle("Items due today are urgent (sorting)", isOn: $dueTodayIsUrgent)
                Toggle("Auto-reschedule overdue todos to today", isOn: $autoRescheduleOverdue)
            } header: {
                Text("Todo Behaviour").eyebrowStyle(tint: Color.inkMuted)
            }

            calendarEventsSection

            intelligenceStatusSection

            cloudSyncStatusSection

            Section {
                Picker("Due within", selection: $focusDueWindow) {
                    ForEach(FocusDueWindow.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Or priority", selection: $focusPriorityFloor) {
                    ForEach(FocusPriorityFloor.allCases) { Text($0.displayName).tag($0) }
                }
                Text("When Focus is on, the note list hides anything that isn't due within your window or above your priority floor. Pinned notes always pass; done and cancelled todos never do.")
                    .font(.editorialItalic(12))
                    .foregroundStyle(Color.inkSoft)
            } header: {
                Text("Focus Mode").eyebrowStyle(tint: Color.inkMuted)
            }

            Section {
                Toggle("Auto-archive inactive todo notes", isOn: $autoArchiveEnabled)
                Picker("Untouched for", selection: $autoArchiveAge) {
                    ForEach(ArchiveAge.allCases) { age in
                        Text(age.displayName).tag(age)
                    }
                }
                .disabled(!autoArchiveEnabled)
                Text("Only notes with Todo enabled are auto-archived. Reference notes and other plain markdown notes are never touched.")
                    .font(.editorialItalic(12))
                    .foregroundStyle(Color.inkSoft)
            } header: {
                Text("Auto-Archive Inactive Todos").eyebrowStyle(tint: Color.inkMuted)
            }

            Section {
                Button(action: buildAndExport) {
                    HStack {
                        Label(building ? "Preparing export…" : "Export all notes…",
                              systemImage: "square.and.arrow.up")
                        Spacer()
                        if building { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(building)
                if let exportError {
                    Text(exportError)
                        .font(.caption)
                        .foregroundStyle(Color.editorialRed)
                }
                Text("Exports every note as a markdown file with YAML front-matter for metadata. One zip you can drop anywhere.")
                    .font(.editorialItalic(12))
                    .foregroundStyle(Color.inkSoft)
            } header: {
                Text("Backup").eyebrowStyle(tint: Color.inkMuted)
            }

            Section {
                Text("Auto-archive and overdue rescheduling run when the app comes to the foreground.")
                    .font(.editorialItalic(12))
                    .foregroundStyle(Color.inkSoft)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 480)
        #endif
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .zip,
            defaultFilename: ExportService.suggestedFilename()
        ) { result in
            if case .failure(let err) = result {
                exportError = err.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var calendarEventsSection: some View {
        Section {
            Toggle("Show today's events on Home", isOn: $calendarEventsEnabled)
                .onChange(of: calendarEventsEnabled) { _, newValue in
                    if newValue, calendarService.authStatus == .notDetermined {
                        Task { _ = await calendarService.requestAccess() }
                    }
                    if newValue { calendarService.refresh() }
                }

            if calendarEventsEnabled {
                switch calendarService.authStatus {
                case .notDetermined:
                    Button("Grant Calendar access") {
                        Task { _ = await calendarService.requestAccess() }
                    }
                case .denied, .restricted, .writeOnly:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Calendar access is denied for RollingTodo.")
                            .font(.editorialItalic(12))
                            .foregroundStyle(Color.inkSoft)
                        Button("Open System Settings") { openPrivacySettings() }
                    }
                case .fullAccess:
                    let calendars = calendarService.availableCalendars()
                    if calendars.isEmpty {
                        Text("No calendars found on this device.")
                            .font(.editorialItalic(12))
                            .foregroundStyle(Color.inkSoft)
                    } else {
                        ForEach(calendars, id: \.calendarIdentifier) { cal in
                            Toggle(isOn: calendarToggleBinding(for: cal)) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(cgColor: cal.cgColor ?? CGColor(gray: 0.5, alpha: 1)))
                                        .frame(width: 8, height: 8)
                                    Text(cal.title)
                                }
                            }
                        }
                    }
                @unknown default:
                    EmptyView()
                }
            }

            Text("Asks for Calendar permission. Calendar selection stays on this device; the on/off toggle syncs across your devices.")
                .font(.editorialItalic(12))
                .foregroundStyle(Color.inkSoft)
        } header: {
            Text("Calendar Events").eyebrowStyle(tint: Color.inkMuted)
        }
    }

    private func calendarToggleBinding(for cal: EKCalendar) -> Binding<Bool> {
        Binding(
            get: { calendarService.selectedCalendarIDs.contains(cal.calendarIdentifier) },
            set: { calendarService.setSelected(cal.calendarIdentifier, $0) }
        )
    }

    @ViewBuilder
    private var intelligenceStatusSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(intelligence.isAvailable ? Color.editorialSage : Color.editorialAmber)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 4) {
                    Text(intelligence.isAvailable ? "Apple Intelligence ready" : "Apple Intelligence unavailable")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    if let note = intelligence.availabilityNote {
                        Text(note)
                            .font(.editorialItalic(12))
                            .foregroundStyle(Color.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Smart title, daily summary, and AI note generation are enabled.")
                            .font(.editorialItalic(12))
                            .foregroundStyle(Color.inkSoft)
                    }
                }

                Spacer(minLength: 0)
            }

            recheckButton(
                phase: intelligence.recheckPhase,
                idleLabel: "Re-check",
                action: { Task { await intelligence.recheckAvailability() } }
            )
        } header: {
            Text("Apple Intelligence").eyebrowStyle(tint: Color.inkMuted)
        }
    }

    @ViewBuilder
    private var cloudSyncStatusSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(cloudSync.isHealthy ? Color.editorialSage : Color.editorialAmber)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 4) {
                    Text(cloudSync.statusTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    Text(cloudSync.statusNote)
                        .font(.editorialItalic(12))
                        .foregroundStyle(Color.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if let id = cloudSync.syncID {
                HStack(spacing: 10) {
                    Text("Sync ID")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.inkMuted)
                    Text(hideAccountIdentifier ? "•••••••" : id)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.ink)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }

            Toggle("Hide identifier", isOn: $hideAccountIdentifier)
                .font(.system(size: 12))

            recheckButton(
                phase: cloudSync.recheckPhase,
                idleLabel: "Re-check",
                action: { Task { await cloudSync.refreshAccountStatus() } }
            )

            DisclosureGroup(isExpanded: $showDiagnostics) {
                cloudDiagnosticsBody
            } label: {
                Text("Diagnostics")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.inkMuted)
            }

            if cloudSync.lastErrorDiagnostics != nil {
                Button(action: copyDiagnostics) {
                    Text(diagnosticsCopied ? "Copied" : "Copy diagnostics")
                }
                .font(.system(size: 12))
                .disabled(diagnosticsCopied)
            }
        } header: {
            Text("iCloud Sync").eyebrowStyle(tint: Color.inkMuted)
        }
    }

    @ViewBuilder
    private var cloudDiagnosticsBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: copyFullDiagnostics) {
                    Text(diagnosticsCopied ? "Copied" : "Copy full diagnostics")
                }
                .font(.system(size: 12))
                .disabled(diagnosticsCopied)
                Spacer(minLength: 0)
            }
            diagnosticRow("App build", value: appBuildString, monospaced: true)
            diagnosticRow("CloudKit env", value: cloudSync.cloudKitEnvironment,
                          tint: cloudSync.cloudKitEnvironment == "Production" ? Color.editorialSage : Color.editorialAmber)
            diagnosticRow("Container", value: PersistenceController.cloudContainerID, monospaced: true)
            diagnosticRow(
                "Entitled containers",
                value: cloudSync.entitledContainerIdentifiers.isEmpty
                    ? "(none)"
                    : cloudSync.entitledContainerIdentifiers.joined(separator: ", "),
                tint: cloudSync.hasEntitlementForConfiguredContainer ? Color.editorialSage : Color.editorialRed,
                monospaced: true
            )
            if !cloudSync.hasEntitlementForConfiguredContainer {
                Text("This binary's entitlement does not authorize the configured CloudKit container. Record-level operations will silently fail. Cause: provisioning profile is stale (typical when changing container IDs and uploading to TestFlight without refreshing the profile in Xcode → Settings → Accounts → Download Manual Profiles, then re-archiving).")
                    .font(.editorialItalic(11))
                    .foregroundStyle(Color.editorialRed)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let full = cloudSync.fullSyncID {
                diagnosticRow("Full user record", value: hideAccountIdentifier ? "•••••••" : full, monospaced: true)
            }
            diagnosticRow("Ubiquity identity", value: cloudSync.hasUbiquityIdentity ? "Present" : "Missing",
                          tint: cloudSync.hasUbiquityIdentity ? Color.editorialSage : Color.editorialAmber)
            #if os(iOS)
            diagnosticRow("Push authorization", value: cloudSync.pushAuthStatus,
                          tint: cloudSync.pushAuthStatus == "Authorized" ? Color.editorialSage : Color.editorialAmber)
            #endif

            Divider().padding(.vertical, 2)

            eventCountRow("Setup",  ok: cloudSync.setupSuccessCount,  fail: cloudSync.setupFailureCount,  lastOK: cloudSync.lastSetupSucceededAt)
            eventCountRow("Import", ok: cloudSync.importSuccessCount, fail: cloudSync.importFailureCount, lastOK: cloudSync.lastImportSucceededAt)
            eventCountRow("Export", ok: cloudSync.exportSuccessCount, fail: cloudSync.exportFailureCount, lastOK: cloudSync.lastExportSucceededAt)

            if !cloudSync.recentEvents.isEmpty {
                Divider().padding(.vertical, 2)
                Text("Recent events")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.inkMuted)
                ForEach(cloudSync.recentEvents.reversed()) { evt in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(evt.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.inkMuted)
                        Text("[\(evt.type)] \(evt.outcome)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(evt.outcome.hasPrefix("FAILED") ? Color.editorialRed : Color.ink)
                    }
                }
            } else {
                Text("No CloudKit events recorded since launch. If this stays empty for more than a minute after the app is opened, the persistent container hasn't initialized — typically iCloud Drive is off, the app isn't ticked under Apps Using iCloud, or a network policy is blocking CloudKit.")
                    .font(.editorialItalic(11))
                    .foregroundStyle(Color.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().padding(.vertical, 2)

            HStack(spacing: 8) {
                Button(action: { Task { await cloudSync.pingCloudKit() } }) {
                    HStack(spacing: 6) {
                        if case .running = cloudSync.pingPhase {
                            ProgressView().controlSize(.small)
                        }
                        Text(pingButtonLabel)
                    }
                }
                .font(.system(size: 12))
                .disabled(pingButtonDisabled)
                Spacer(minLength: 0)
            }
            pingResultView
        }
        .padding(.top, 4)
    }

    private var pingButtonLabel: String {
        switch cloudSync.pingPhase {
        case .running: "Testing iCloud connection…"
        default:       "Test iCloud connection"
        }
    }

    private var pingButtonDisabled: Bool {
        if case .running = cloudSync.pingPhase { return true }
        return false
    }

    private var pingDetailTint: Color {
        switch cloudSync.pingPhase {
        case .ok: Color.editorialSage
        case .failed: Color.editorialRed
        default: Color.inkSoft
        }
    }

    /// Sum across all four CloudKit-mirrored entity types so the count is
    /// directly comparable to `recordZoneChanges` server-side count, which
    /// counts every CKRecord regardless of type.
    private func localTotalRecordCount() -> Int {
        let folders   = (try? context.fetchCount(FetchDescriptor<Folder>())) ?? -1
        let notes     = (try? context.fetchCount(FetchDescriptor<Note>())) ?? -1
        let todos     = (try? context.fetchCount(FetchDescriptor<TodoItem>())) ?? -1
        let homepages = (try? context.fetchCount(FetchDescriptor<HomepageNote>())) ?? -1
        if folders < 0 || notes < 0 || todos < 0 || homepages < 0 { return -1 }
        return folders + notes + todos + homepages
    }

    private var appBuildString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    private func recordsDetail(local: Int, server: Int) -> String {
        if local < 0 { return "Couldn't read local store." }
        if local == server { return "Local store matches the server." }
        if local < server {
            let gap = server - local
            return "Server holds \(gap) more record\(gap == 1 ? "" : "s") than this device has imported. The device is failing on the import side, not because the data is missing on iCloud."
        }
        let gap = local - server
        return "Local store has \(gap) more record\(gap == 1 ? "" : "s") than the server can see. Either an export is pending or schema is mismatched."
    }

    @ViewBuilder
    private var pingResultView: some View {
        switch cloudSync.pingPhase {
        case .idle, .running:
            EmptyView()
        case .failed(let msg):
            Text("Ping failed: \(msg)")
                .font(.editorialItalic(11))
                .foregroundStyle(Color.editorialRed)
                .fixedSize(horizontal: false, vertical: true)
        case .ok(let report):
            let local = localTotalRecordCount()
            let server = report.serverRecordCount
            VStack(alignment: .leading, spacing: 6) {
                Text("Reached private database in \(report.durationMs)ms.")
                    .font(.editorialItalic(11))
                    .foregroundStyle(Color.editorialSage)

                pingMetricRow(
                    label: "Zones",
                    value: "\(report.zones.count)",
                    detail: report.zones.isEmpty ? "(none)" : report.zones.joined(separator: "\n"),
                    isHealthy: report.mirrorZonePresent
                )
                pingMetricRow(
                    label: "Subscriptions",
                    value: "\(report.subscriptionIDs.count)",
                    detail: report.subscriptionIDs.isEmpty
                        ? "None — without a subscription this device cannot receive silent push and will never auto-import remote changes. Sign out / in of iCloud or reinstall."
                        : report.subscriptionIDs.joined(separator: "\n"),
                    isHealthy: !report.subscriptionIDs.isEmpty
                )
                if let server {
                    pingMetricRow(
                        label: "Records",
                        value: "server \(server)\(report.serverRecordsTruncated ? "+" : "")  •  local \(local >= 0 ? "\(local)" : "?")",
                        detail: recordsDetail(local: local, server: server),
                        isHealthy: local == server
                    )
                } else {
                    pingMetricRow(
                        label: "Records",
                        value: "—",
                        detail: "SwiftData zone (com.apple.coredata.cloudkit.zone) is not present on the server. The container has not run a successful initial sync from this account.",
                        isHealthy: false
                    )
                }

                // Always render this row when the zone exists — it's the
                // most informative line in the report. If the cross-check
                // failed, the row says so explicitly rather than vanishing.
                if report.mirrorZonePresent {
                    let descriptor = queryCrossCheckDescriptor(report: report)
                    pingMetricRow(
                        label: "Query cross-check",
                        value: descriptor.value,
                        detail: descriptor.detail,
                        isHealthy: descriptor.healthy
                    )
                }

                if !report.serverRecordNames.isEmpty {
                    Divider().padding(.vertical, 2)
                    Text("Server records (this device's view)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.inkMuted)
                    Text(report.serverRecordNames.joined(separator: "\n"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Copy this list from each device. If two devices show different lists despite identical Apple ID, the records are not making it across — diff the lists to see which records are missing where.")
                        .font(.editorialItalic(11))
                        .foregroundStyle(Color.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("If query and zonechanges disagree on this device, the local CloudKit daemon (cloudd) is serving stale state. Reinstalling the app does not clear this — sign out of iCloud entirely (System Settings → Apple ID → Sign Out), reboot, then sign back in. To watch sync activity live, open Console.app and filter on subsystem `com.apple.coredata` or `com.apple.cloudkit` while reproducing the issue.")
                    .font(.editorialItalic(11))
                    .foregroundStyle(Color.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private struct QueryCrossCheckDescriptor {
        let value: String
        let detail: String
        let healthy: Bool
    }

    private func queryCrossCheckDescriptor(report: CloudSyncMonitor.PingReport) -> QueryCrossCheckDescriptor {
        let q = report.queryRecordCount
        let server = report.serverRecordCount
        let perType = perTypeBreakdown(report.queryRecordCountsByType)
        if let q, let server {
            return QueryCrossCheckDescriptor(
                value: "ckquery \(q)  •  zonechanges \(server)",
                detail: queryCrossCheckDetail(query: q, server: server, byType: report.queryRecordCountsByType),
                healthy: q == server
            )
        }
        if let q {
            return QueryCrossCheckDescriptor(
                value: "ckquery \(q)  •  zonechanges —",
                detail: "recordZoneChanges did not return a count. \(perType)",
                healthy: false
            )
        }
        let serverText = server.map { "\($0)" } ?? "—"
        let errLine = report.queryFirstError.map { "\nFirst error — \($0)" } ?? ""
        return QueryCrossCheckDescriptor(
            value: "ckquery —  •  zonechanges \(serverText)",
            detail: "All four CKQuery probes failed. The most common cause is that the record types (CD_Folder, CD_Note, CD_TodoItem, CD_HomepageNote) aren't marked Queryable in the Production schema. In CloudKit Console → Schema → Indexes, add a Queryable index on `recordName` for each type and redeploy.\n\(perType)\(errLine)",
            healthy: false
        )
    }

    private func queryCrossCheckDetail(query: Int, server: Int, byType: [String: Int]) -> String {
        let perType = perTypeBreakdown(byType)
        if query == server {
            return "Both query paths agree. \(perType)"
        }
        if query > server {
            return "CKQuery sees \(query - server) more record\(query - server == 1 ? "" : "s") than recordZoneChanges. The CloudKit daemon's local replica is stale on this device. \(perType)"
        }
        return "recordZoneChanges sees \(server - query) more than CKQuery. Some record types may not be deployed in the production schema. \(perType)"
    }

    private func perTypeBreakdown(_ byType: [String: Int]) -> String {
        let pairs = byType
            .sorted { $0.key < $1.key }
            .map { "\($0.key.dropFirst(3)): \($0.value < 0 ? "err" : "\($0.value)")" }
        return pairs.isEmpty ? "" : "Per-type — " + pairs.joined(separator: ", ")
    }

    @ViewBuilder
    private func pingMetricRow(label: String, value: String, detail: String, isHealthy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.inkMuted)
                    .frame(width: 100, alignment: .leading)
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isHealthy ? Color.editorialSage : Color.editorialAmber)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            Text(detail)
                .font(.editorialItalic(11))
                .foregroundStyle(Color.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 108)
        }
    }

    @ViewBuilder
    private func diagnosticRow(_ label: String, value: String, tint: Color? = nil, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.inkMuted)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: monospaced ? .monospaced : .default))
                .foregroundStyle(tint ?? Color.ink)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func eventCountRow(_ label: String, ok: Int, fail: Int, lastOK: Date?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.inkMuted)
                .frame(width: 130, alignment: .leading)
            Text("ok \(ok)  •  fail \(fail)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ok > 0 ? Color.ink : Color.editorialAmber)
            Spacer(minLength: 0)
            Text(lastOK.map { $0.formatted(.relative(presentation: .named)) } ?? "never")
                .font(.system(size: 11))
                .foregroundStyle(Color.inkSoft)
        }
    }

    @ViewBuilder
    private func recheckButton<P: Equatable>(
        phase: P,
        idleLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        // Translate either RecheckPhase enum into a uniform UI state via the
        // `recheckPhaseDescription` helper below — we accept `Any` here because
        // CloudSyncMonitor.RecheckPhase and IntelligenceService.RecheckPhase
        // are structurally identical but distinct types.
        let descriptor = recheckPhaseDescriptor(phase)
        Button(action: action) {
            HStack(spacing: 6) {
                if descriptor.showSpinner {
                    ProgressView().controlSize(.small)
                }
                Text(descriptor.label.isEmpty ? idleLabel : descriptor.label)
                    .foregroundStyle(descriptor.tint ?? Color.accentColor)
            }
        }
        .font(.system(size: 12))
        .disabled(descriptor.disabled)
    }

    private struct RecheckDescriptor {
        var label: String
        var showSpinner: Bool
        var disabled: Bool
        var tint: Color?
    }

    private func recheckPhaseDescriptor<P: Equatable>(_ phase: P) -> RecheckDescriptor {
        if let p = phase as? CloudSyncMonitor.RecheckPhase {
            return descriptor(for: p)
        }
        if let p = phase as? IntelligenceService.RecheckPhase {
            return descriptor(for: p)
        }
        return RecheckDescriptor(label: "", showSpinner: false, disabled: false, tint: nil)
    }

    private func descriptor(for phase: CloudSyncMonitor.RecheckPhase) -> RecheckDescriptor {
        switch phase {
        case .idle:
            return RecheckDescriptor(label: "", showSpinner: false, disabled: false, tint: nil)
        case .checking:
            return RecheckDescriptor(label: "Re-checking…", showSpinner: true, disabled: true, tint: Color.inkSoft)
        case .settled(let unchanged):
            return RecheckDescriptor(
                label: unchanged ? "Result unchanged" : "Updated",
                showSpinner: false,
                disabled: true,
                tint: unchanged ? Color.inkSoft : Color.editorialSage
            )
        }
    }

    private func descriptor(for phase: IntelligenceService.RecheckPhase) -> RecheckDescriptor {
        switch phase {
        case .idle:
            return RecheckDescriptor(label: "", showSpinner: false, disabled: false, tint: nil)
        case .checking:
            return RecheckDescriptor(label: "Re-checking…", showSpinner: true, disabled: true, tint: Color.inkSoft)
        case .settled(let unchanged):
            return RecheckDescriptor(
                label: unchanged ? "Result unchanged" : "Updated",
                showSpinner: false,
                disabled: true,
                tint: unchanged ? Color.inkSoft : Color.editorialSage
            )
        }
    }

    private func copyDiagnostics() {
        guard let text = cloudSync.lastErrorDiagnostics else { return }
        copyToPasteboard(text)
    }

    private func copyFullDiagnostics() {
        copyToPasteboard(cloudSync.composeFullDiagnostics())
    }

    private func copyToPasteboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        diagnosticsCopied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            diagnosticsCopied = false
        }
    }

    private func openPrivacySettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    private func buildAndExport() {
        guard !building else { return }
        building = true
        exportError = nil
        Task { @MainActor in
            defer { building = false }
            if hasLockedNotes() {
                let ok = await UnlockSession.authenticate(
                    reason: "Authenticate to include sealed notes in your export."
                )
                guard ok else {
                    exportError = "Export cancelled — sealed notes need authentication."
                    return
                }
            }
            guard let data = ExportService.exportAll(context: context) else {
                exportError = "Couldn't build the export — try again."
                return
            }
            exportDocument = ExportDocument(data: data)
            showExporter = true
        }
    }

    private func hasLockedNotes() -> Bool {
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.isLocked })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }
}

#Preview {
    SettingsView()
}
