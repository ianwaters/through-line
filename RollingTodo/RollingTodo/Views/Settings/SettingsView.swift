import SwiftUI

struct SettingsView: View {
    @AppStorage("showHomepageNote") private var showHomepageNote: Bool = true
    @AppStorage("autoRescheduleOverdue") private var autoRescheduleOverdue: Bool = false
    @AppStorage("dueTodayIsUrgent") private var dueTodayIsUrgent: Bool = false
    @AppStorage("autoArchiveEnabled") private var autoArchiveEnabled: Bool = false
    @AppStorage("autoArchiveAge") private var autoArchiveAge: ArchiveAge = .month

    var body: some View {
        Form {
            Section("Home Screen") {
                Toggle("Show notes section on home screen", isOn: $showHomepageNote)
            }

            Section("Todo Behaviour") {
                Toggle("Items due today are urgent (sorting)", isOn: $dueTodayIsUrgent)
                Toggle("Auto-reschedule overdue to today", isOn: $autoRescheduleOverdue)
            }

            Section("Auto-Archive") {
                Toggle("Auto-archive inactive items", isOn: $autoArchiveEnabled)
                Picker("Inactive after", selection: $autoArchiveAge) {
                    ForEach(ArchiveAge.allCases) { age in
                        Text(age.displayName).tag(age)
                    }
                }
                .disabled(!autoArchiveEnabled)
            }

            Section {
                Text("Auto-archive and overdue rescheduling run when the app comes to the foreground.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .frame(minWidth: 420, minHeight: 380)
    }
}

#Preview {
    SettingsView()
}
