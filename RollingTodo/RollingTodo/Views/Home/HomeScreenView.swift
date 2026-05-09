import SwiftUI
import SwiftData

struct HomeScreenView: View {
    var onOpenNote: ((UUID) -> Void)? = nil

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

    private enum TimeOfDay {
        case morning, afternoon, evening, night

        var greeting: String {
            switch self {
            case .morning: "Good morning"
            case .afternoon: "Good afternoon"
            case .evening: "Good evening"
            case .night: "Hello"
            }
        }

        var noun: String {
            switch self {
            case .morning: "morning"
            case .afternoon: "afternoon"
            case .evening: "evening"
            case .night: "night"
            }
        }
    }

    private var timeOfDay: TimeOfDay {
        switch calendar.component(.hour, from: .now) {
        case 5..<12: .morning
        case 12..<17: .afternoon
        case 17..<22: .evening
        default: .night
        }
    }

    private var greeting: String { timeOfDay.greeting }

    private var updateMessage: String {
        if urgent.count > 0 {
            return urgent.count == 1 ? "One urgent item asks for your attention." : "\(urgent.count) urgent items ask for your attention."
        }
        if dueToday.count > 0 {
            return dueToday.count == 1 ? "One thing due today." : "\(dueToday.count) things due today."
        }
        if overdue.count > 0 {
            return overdue.count == 1 ? "One overdue item lingers." : "\(overdue.count) overdue items linger."
        }
        return "Nothing urgent. A clear \(timeOfDay.noun)."
    }

    /// The notes that the update message refers to — surfaced as chips below the headline.
    private var updateNotes: [Note] {
        if !urgent.isEmpty { return urgent }
        if !dueToday.isEmpty { return dueToday }
        if !overdue.isEmpty { return overdue }
        return []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                    .padding(.bottom, 56)

                quickActions
                    .padding(.bottom, showHomepageNote && !homepageNotes.isEmpty ? 56 : 24)

                if showHomepageNote {
                    homepageSection
                }
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 72)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("")
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

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .eyebrowStyle()
                .padding(.bottom, 14)

            Text(greeting)
                .font(.editorialDisplay(64, weight: .semibold))
                .foregroundStyle(Color.ink)
                .padding(.bottom, 18)

            Text(updateMessage)
                .font(.editorialDisplay(22, weight: .regular))
                .italic()
                .foregroundStyle(Color.inkSoft)
                .lineSpacing(4)
                .frame(maxWidth: 540, alignment: .leading)

            if !updateNotes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(updateNotes) { note in
                            UpdateChip(note: note) {
                                onOpenNote?(note.id)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .padding(.top, 16)
            }
        }
    }

    // MARK: - Quick actions (editorial list, not card grid)

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Quick Cleanup")
                    .eyebrowStyle()
                Spacer()
                Text(cleanupTotal == 0 ? "All clear" : "\(cleanupTotal) waiting")
                    .font(.editorialItalic(13))
                    .foregroundStyle(Color.inkMuted)
            }
            .padding(.bottom, 18)

            VStack(spacing: 0) {
                QuickActionRow(
                    title: "Set overdue to Triage",
                    detail: "Stops the bleed; marks them for review",
                    symbol: "questionmark.circle",
                    count: overdue.count,
                    action: performSetOverdueToTriage
                )
                Divider().background(Color.inkHairline)
                QuickActionRow(
                    title: "Move done to Archive",
                    detail: "Closes out finished work",
                    symbol: "archivebox",
                    count: done.count,
                    action: performMoveDoneToArchive
                )
                Divider().background(Color.inkHairline)
                QuickActionRow(
                    title: "Move cancelled to Archive",
                    detail: "Tidy without deleting",
                    symbol: "archivebox.fill",
                    count: cancelled.count,
                    action: performMoveCancelledToArchive
                )
                Divider().background(Color.inkHairline)
                QuickActionRow(
                    title: "Delete cancelled",
                    detail: "Permanent — gone for good",
                    symbol: "trash",
                    count: cancelled.count,
                    role: .destructive,
                    action: { confirmingDeleteCancelled = true }
                )
            }
            .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.inkHairline, lineWidth: 0.5)
            )
        }
    }

    private var cleanupTotal: Int {
        overdue.count + done.count + cancelled.count
    }

    @ViewBuilder
    private var homepageSection: some View {
        if let note = homepageNotes.first {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Notes")
                        .eyebrowStyle()
                    Spacer()
                    Text("Pinned to home")
                        .font(.editorialItalic(13))
                        .foregroundStyle(Color.inkMuted)
                }

                HomepageNoteSection(note: note)
            }
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
        for n in done { n.archivedDate = now }
        try? context.save()
    }

    private func performMoveCancelledToArchive() {
        let now = Date.now
        for n in cancelled { n.archivedDate = now }
        try? context.save()
    }

    private func performDeleteCancelled() {
        for n in cancelled { context.delete(n) }
        try? context.save()
    }
}

// MARK: - Quick Action Row (editorial list style)

private struct UpdateChip: View {
    let note: Note
    let action: () -> Void

    @State private var isHovered: Bool = false

    private var leadingDot: Color? {
        if note.priority == .urgent { return .editorialRed }
        if note.priority == .high { return .editorialAmber }
        if note.todoEnabled { return note.status.tint }
        return nil
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let dot = leadingDot {
                    Circle()
                        .fill(dot)
                        .frame(width: 6, height: 6)
                }
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(
                    isHovered
                        ? Color.secondary.opacity(0.15)
                        : Color.secondary.opacity(0.08)
                )
            )
            .overlay(
                Capsule().strokeBorder(Color.inkHairline, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}

private struct QuickActionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let count: Int
    var role: ButtonRole? = nil
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(role: role, action: action) {
            HStack(alignment: .center, spacing: 18) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(role == .destructive ? Color.editorialRed : Color.accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.editorialDisplay(17, weight: .medium))
                        .foregroundStyle(Color.ink)
                    Text(detail)
                        .font(.editorialItalic(13))
                        .foregroundStyle(Color.inkMuted)
                }

                Spacer()

                Text(count == 0 ? "—" : "\(count)")
                    .font(.editorialNumeric(20, weight: .regular))
                    .foregroundStyle(count == 0 ? Color.inkMuted.opacity(0.5) : Color.ink)

                Image(systemName: "arrow.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(isHovered ? 1 : 0))
                    .offset(x: isHovered ? 0 : -4)
                    .frame(width: 14)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .contentShape(.rect)
            .background(isHovered ? Color.accentColor.opacity(0.04) : Color.clear)
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .opacity(count == 0 ? 0.5 : 1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}

// MARK: - Homepage Note Section

private struct HomepageNoteSection: View {
    @Bindable var note: HomepageNote
    @Environment(\.modelContext) private var context
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        TextEditor(text: $note.body)
            .font(.system(size: 15, design: .serif))
            .lineSpacing(5)
            .scrollContentBackground(.hidden)
            .padding(20)
            .frame(minHeight: 160)
            .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.inkHairline, lineWidth: 0.5)
            )
            .onChange(of: note.body) { _, _ in scheduleSave() }
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
