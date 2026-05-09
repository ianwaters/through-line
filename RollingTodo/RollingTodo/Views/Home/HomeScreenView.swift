import SwiftUI
import SwiftData

struct HomeScreenView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Note> { $0.archivedDate == nil }) private var activeNotes: [Note]
    @Query private var homepageNotes: [HomepageNote]

    @AppStorage("showHomepageNote") private var showHomepageNote: Bool = true
    @AppStorage("dueTodayIsUrgent") private var dueTodayIsUrgent: Bool = false

    @State private var confirmingDeleteCancelled: Bool = false

    private var calendar: Calendar { .current }
    private var startOfToday: Date { calendar.startOfDay(for: .now) }

    private var todoEnabledActive: [Note] { activeNotes.filter(\.todoEnabled) }

    private var overdue: [Note] {
        todoEnabledActive.filter { n in
            guard let due = n.dueDate else { return false }
            guard n.status != .done, n.status != .cancelled else { return false }
            return calendar.startOfDay(for: due) < startOfToday
        }
    }

    private var dueToday: [Note] {
        todoEnabledActive.filter { n in
            guard let due = n.dueDate else { return false }
            guard n.status != .done, n.status != .cancelled else { return false }
            return calendar.isDate(due, inSameDayAs: .now)
        }
    }

    private var urgent: [Note] {
        todoEnabledActive.filter { n in
            guard n.status != .done, n.status != .cancelled else { return false }
            if n.priority == .urgent { return true }
            if dueTodayIsUrgent, let due = n.dueDate, calendar.isDate(due, inSameDayAs: .now) { return true }
            return false
        }
    }

    private var done: [Note] { todoEnabledActive.filter { $0.status == .done } }
    private var cancelled: [Note] { todoEnabledActive.filter { $0.status == .cancelled } }

    private var greeting: String {
        let hour = calendar.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Hello"
        }
    }

    private var updateMessage: String {
        if urgent.count > 0 {
            return urgent.count == 1 ? "You have 1 urgent item." : "You have \(urgent.count) urgent items."
        }
        if dueToday.count > 0 {
            return dueToday.count == 1 ? "You have 1 item due today." : "You have \(dueToday.count) items due today."
        }
        if overdue.count > 0 {
            return overdue.count == 1 ? "You have 1 overdue item." : "You have \(overdue.count) overdue items."
        }
        return "You have no urgent items."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                updateCard
                quickActions
                if showHomepageNote {
                    homepageSection
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Home")
        .confirmationDialog(
            "Delete \(cancelled.count) cancelled note\(cancelled.count == 1 ? "" : "s")?",
            isPresented: $confirmingDeleteCancelled,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { performDeleteCancelled() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete every note with status Cancelled. This can't be undone.")
        }
        .onAppear(perform: ensureHomepageNote)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.largeTitle.bold())
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var updateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Update")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(updateMessage)
                .font(.title2)
                .fontWeight(.medium)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Clean Up")
                .font(.headline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                QuickActionCard(
                    title: "Set overdue to Triage",
                    systemImage: "questionmark.circle",
                    count: overdue.count,
                    role: nil
                ) { performSetOverdueToTriage() }

                QuickActionCard(
                    title: "Move done to Archive",
                    systemImage: "archivebox",
                    count: done.count,
                    role: nil
                ) { performMoveDoneToArchive() }

                QuickActionCard(
                    title: "Move cancelled to Archive",
                    systemImage: "archivebox",
                    count: cancelled.count,
                    role: nil
                ) { performMoveCancelledToArchive() }

                QuickActionCard(
                    title: "Delete cancelled",
                    systemImage: "trash",
                    count: cancelled.count,
                    role: .destructive
                ) { confirmingDeleteCancelled = true }
            }
        }
    }

    @ViewBuilder
    private var homepageSection: some View {
        if let note = homepageNotes.first {
            HomepageNoteSection(note: note)
        }
    }

    private func ensureHomepageNote() {
        if homepageNotes.isEmpty {
            context.insert(HomepageNote())
            try? context.save()
        }
    }

    private func performSetOverdueToTriage() {
        for n in overdue {
            n.status = .triage
            n.modifiedDate = .now
        }
        try? context.save()
    }

    private func performMoveDoneToArchive() {
        let now = Date.now
        for n in done {
            n.archivedDate = now
        }
        try? context.save()
    }

    private func performMoveCancelledToArchive() {
        let now = Date.now
        for n in cancelled {
            n.archivedDate = now
        }
        try? context.save()
    }

    private func performDeleteCancelled() {
        for n in cancelled {
            context.delete(n)
        }
        try? context.save()
    }
}

private struct QuickActionCard: View {
    let title: String
    let systemImage: String
    let count: Int
    let role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(role == .destructive ? .red : .accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text("\(count) item\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .opacity(count == 0 ? 0.45 : 1)
    }
}

private struct HomepageNoteSection: View {
    @Bindable var note: HomepageNote
    @Environment(\.modelContext) private var context
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)
                .foregroundStyle(.secondary)
            TextEditor(text: $note.body)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 140)
                .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
                )
                .onChange(of: note.body) { _, _ in scheduleSave() }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            note.modifiedDate = .now
            try? context.save()
        }
        saveTask = task
    }
}

#Preview {
    NavigationStack {
        HomeScreenView()
    }
    .modelContainer(PersistenceController.preview)
}
