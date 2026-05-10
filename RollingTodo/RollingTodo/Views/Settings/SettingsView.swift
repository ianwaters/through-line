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

            if case .failed = cloudSync.status, cloudSync.lastErrorDiagnostics != nil {
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
