import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("showHomepageNote") private var showHomepageNote: Bool = true
    @AppStorage("autoRescheduleOverdue") private var autoRescheduleOverdue: Bool = false
    @AppStorage("dueTodayIsUrgent") private var dueTodayIsUrgent: Bool = false
    @AppStorage("autoArchiveEnabled") private var autoArchiveEnabled: Bool = false
    @AppStorage("autoArchiveAge") private var autoArchiveAge: ArchiveAge = .month
    @AppStorage("focusDueWindow") private var focusDueWindow: FocusDueWindow = .thisWeek
    @AppStorage("focusPriorityFloor") private var focusPriorityFloor: FocusPriorityFloor = .highOrUrgent

    @State private var exportDocument: ExportDocument?
    @State private var showExporter: Bool = false
    @State private var building: Bool = false
    @State private var exportError: String?

    var body: some View {
        Form {
            Section("Home Screen") {
                Toggle("Show notes section on home screen", isOn: $showHomepageNote)
            }

            Section("Todo Behaviour") {
                Toggle("Items due today are urgent (sorting)", isOn: $dueTodayIsUrgent)
                Toggle("Auto-reschedule overdue todos to today", isOn: $autoRescheduleOverdue)
            }

            Section("Focus Mode") {
                Picker("Due within", selection: $focusDueWindow) {
                    ForEach(FocusDueWindow.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Or priority", selection: $focusPriorityFloor) {
                    ForEach(FocusPriorityFloor.allCases) { Text($0.displayName).tag($0) }
                }
                Text("When Focus is on, the note list hides anything that isn't due within your window or above your priority floor. Pinned notes always pass; done and cancelled todos never do.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Auto-Archive Inactive Todos") {
                Toggle("Auto-archive inactive todo notes", isOn: $autoArchiveEnabled)
                Picker("Untouched for", selection: $autoArchiveAge) {
                    ForEach(ArchiveAge.allCases) { age in
                        Text(age.displayName).tag(age)
                    }
                }
                .disabled(!autoArchiveEnabled)
                Text("Only notes with Todo enabled are auto-archived. Reference notes and other plain markdown notes are never touched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Backup") {
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
                        .foregroundStyle(.red)
                }
                Text("Exports every note as a markdown file with YAML front-matter for metadata. One zip you can drop anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Auto-archive and overdue rescheduling run when the app comes to the foreground.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .frame(minWidth: 460, minHeight: 480)
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

    private func buildAndExport() {
        guard !building else { return }
        building = true
        exportError = nil
        Task { @MainActor in
            defer { building = false }
            guard let data = ExportService.exportAll(context: context) else {
                exportError = "Couldn't build the export — try again."
                return
            }
            exportDocument = ExportDocument(data: data)
            showExporter = true
        }
    }
}

#Preview {
    SettingsView()
}
