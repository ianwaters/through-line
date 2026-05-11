import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct HomeScreenView: View {
    var onOpenNote: ((UUID) -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Note> { $0.archivedDate == nil }) private var activeNotes: [Note]
    /// Sorted descending by modifiedDate so `homepageNotes.first` is always the
    /// freshest record on every device — see `ensureHomepageNote()` for why
    /// this matters (the singleton has a cross-device creation race).
    @Query(sort: \HomepageNote.modifiedDate, order: .reverse) private var homepageNotes: [HomepageNote]

    @AppStorage("showHomepageNote") private var showHomepageNote: Bool = true
    @AppStorage("dueTodayIsUrgent") private var dueTodayIsUrgent: Bool = false
    @AppStorage("calendarEventsEnabled") private var calendarEventsEnabled: Bool = false

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSizeClass
    #endif

    @State private var calendarService = CalendarEventsService.shared
    @State private var intelligence = IntelligenceService.shared
    @State private var cloudSync = CloudSyncMonitor.shared

    @State private var confirmingDeleteCancelled: Bool = false
    @State private var summaryState: SummaryState = .pending
    @State private var lastSummaryGeneratedAt: Date = .distantPast
    @State private var diagnosticsCopied: Bool = false

    private enum SummaryState: Equatable {
        case pending             // never tried — assume AI is coming
        case ready(String)       // got a summary
        case useFallback         // tried and failed, OR confirmed AI unavailable
    }

    private var isCompact: Bool {
        #if os(iOS)
        return hSizeClass == .compact
        #else
        return false
        #endif
    }

    private var calendar: Calendar { .current }
    private var startOfToday: Date { calendar.startOfDay(for: .now) }

    /// Active todo notes, excluding ones currently snoozed. Snoozed notes are
    /// hidden from every dashboard count — they shouldn't nag while deferred.
    private var todoEnabledActive: [Note] {
        let now = Date.now
        return activeNotes.filter { $0.todoEnabled && !$0.isSnoozed(at: now) }
    }

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

    /// Notes that woke from snooze in the last 24h. The `snoozedUntil` field
    /// stays set after wake (no maintenance clears it), so this is a pure
    /// derived view — sorted most-recent-wake first.
    private var recentlyWoken: [Note] {
        let now = Date.now
        let cutoff = now.addingTimeInterval(-60 * 60 * 24)
        return activeNotes
            .filter { n in
                guard let until = n.snoozedUntil else { return false }
                return until <= now && until > cutoff
            }
            .sorted {
                ($0.snoozedUntil ?? .distantPast) > ($1.snoozedUntil ?? .distantPast)
            }
    }

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

    private var upcomingEventsToday: [CalendarEventViewModel] {
        let now = Date.now
        return calendarService.events.filter { $0.endDate >= now || $0.isAllDay }
    }

    private var tomorrowDueNotes: [Note] {
        let cal = calendar
        guard let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday),
              let startOfDayAfter = cal.date(byAdding: .day, value: 2, to: startOfToday) else {
            return []
        }
        let now = Date.now
        return activeNotes
            .filter { n in
                guard n.todoEnabled,
                      n.status != .done, n.status != .cancelled,
                      !n.isSnoozed(at: now),
                      let due = n.dueDate else { return false }
                return due >= startOfTomorrow && due < startOfDayAfter
            }
            .sorted { a, b in
                if a.priority.rawValue != b.priority.rawValue {
                    return a.priority.rawValue > b.priority.rawValue
                }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
    }

    private var isEveningOrLater: Bool {
        calendar.component(.hour, from: .now) >= 18
    }

    private var showTomorrowSection: Bool {
        isEveningOrLater && (!calendarService.tomorrowEvents.isEmpty || !tomorrowDueNotes.isEmpty)
    }

    /// Hash of every input that should invalidate the cached summary. Includes
    /// the current hour so summaries refresh as time-of-day changes (morning →
    /// afternoon etc.) when body re-evaluates.
    private var summaryInputHash: Int {
        var hasher = Hasher()
        hasher.combine(urgent.count)
        hasher.combine(dueToday.count)
        hasher.combine(overdue.count)
        hasher.combine(calendar.component(.hour, from: .now))
        hasher.combine(upcomingEventsToday.map(\.id))
        return hasher.finalize()
    }

    @ViewBuilder
    private var summaryView: some View {
        switch summaryState {
        case .pending:
            // Initial state: assume AI is on the way; never preemptively flash
            // the rule-based fallback. If AI turns out to be unavailable, the
            // .task transitions us to .useFallback explicitly.
            ComposingSummaryLine()
        case .ready(let text):
            Text(text)
        case .useFallback:
            Text(updateMessage)
        }
    }

    private func regenerateSummaryIfNeeded() async {
        // Cache hit on the service: render instantly on re-appearance (e.g.
        // user tab-switched away and back on iOS) without spawning a fresh
        // LanguageModelSession.
        let hash = summaryInputHash
        if let cached = intelligence.cachedDailySummary(matching: hash) {
            summaryState = .ready(cached)
            lastSummaryGeneratedAt = .now
            return
        }

        // Debounce: wait for inputs to stabilize before kicking off model work.
        // SwiftData @Query results and CalendarEventsService.events often
        // arrive a few hundred ms after view appear; without this, we'd
        // generate twice (once with empty data, once with the real data) and
        // the second result would overwrite the first.
        try? await Task.sleep(for: .milliseconds(700))
        if Task.isCancelled { return }

        guard intelligence.isAvailable else {
            // Confirmed unavailable — flip to fallback explicitly.
            if case .ready = summaryState { /* keep cached */ } else {
                summaryState = .useFallback
            }
            return
        }

        let input = IntelligenceService.DailySummaryInput(
            timeOfDayNoun: timeOfDay.noun,
            urgentCount: urgent.count,
            dueTodayCount: dueToday.count,
            overdueCount: overdue.count,
            upcomingEvents: upcomingEventsToday.prefix(4).map { event in
                let time = event.isAllDay ? "all day" : event.startDate.formatted(.dateTime.hour().minute())
                return (time: time, title: event.title)
            }
        )
        let result = await intelligence.dailySummary(input, hash: hash)
        // Foundation Models doesn't honour cancellation mid-generation, so a
        // stale completion can land here even after .task(id:) cancelled us.
        // Drop it so a newer task's result wins.
        if Task.isCancelled { return }

        if let result {
            summaryState = .ready(result)
            lastSummaryGeneratedAt = .now
        } else if case .ready = summaryState {
            // Regeneration failed but we have a cached summary — keep showing it.
        } else {
            summaryState = .useFallback
        }
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
                    .padding(.bottom, isCompact ? 32 : 56)

                if calendarEventsEnabled {
                    EventsTodaySection()
                        .padding(.bottom, isCompact ? 32 : 56)
                }

                if showTomorrowSection {
                    TomorrowSection(
                        events: calendarEventsEnabled ? calendarService.tomorrowEvents : [],
                        dueNotes: tomorrowDueNotes,
                        onOpenNote: onOpenNote
                    )
                    .padding(.bottom, isCompact ? 32 : 56)
                }

                if showHomepageNote {
                    homepageSection
                        .padding(.bottom, isCompact ? 32 : 56)
                }

                quickActions

                if showSyncIssueBanner {
                    syncIssueBanner
                        .padding(.top, isCompact ? 32 : 56)
                }
            }
            .padding(.horizontal, isCompact ? 24 : 64)
            .padding(.vertical, isCompact ? 32 : 72)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        #if os(macOS)
        .navigationTitle("")
        #else
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
        .onChange(of: homepageNotes.count) { _, _ in
            // When CloudKit pulls a foreign HomepageNote (e.g. another device's
            // singleton from before this fix shipped), dedupe immediately so
            // the editor below doesn't briefly bind to the wrong record.
            ensureHomepageNote()
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .eyebrowStyle()
                .padding(.bottom, 14)

            Text(greeting)
                .font(.editorialDisplay(isCompact ? 40 : 64, weight: .semibold))
                .foregroundStyle(Color.ink)
                .padding(.bottom, 18)

            summaryView
                .font(.editorialDisplay(22, weight: .regular))
                .italic()
                .foregroundStyle(Color.inkSoft)
                .lineSpacing(4)
                .frame(maxWidth: 540, alignment: .leading)
                .animation(.easeInOut(duration: 0.4), value: summaryState)
                .task(id: summaryInputHash) {
                    await regenerateSummaryIfNeeded()
                }

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

            if !recentlyWoken.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Back to your attention")
                        .eyebrowStyle(tint: Color.inkMuted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recentlyWoken) { note in
                                UpdateChip(note: note, leadingSymbol: "moon.zzz.fill") {
                                    onOpenNote?(note.id)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.top, 18)
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

            if cleanupTotal == 0 {
                Text("All clear, nothing to clean up.")
                    .font(.editorialItalic(14))
                    .foregroundStyle(Color.inkSoft)
                    .padding(.vertical, 4)
            } else {
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
    }

    private var cleanupTotal: Int {
        overdue.count + done.count + cancelled.count
    }

    // MARK: - Sync issue banner

    private var showSyncIssueBanner: Bool {
        switch cloudSync.status {
        case .failed, .noAccount: return true
        case .ready, .syncing, .unknown: return false
        }
    }

    private var syncIssueBanner: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sync Issue").eyebrowStyle(tint: Color.editorialAmber)
                Spacer()
                Circle()
                    .fill(Color.editorialAmber)
                    .frame(width: 8, height: 8)
            }

            Text(cloudSync.statusTitle)
                .font(.editorialDisplay(20, weight: .medium))
                .foregroundStyle(Color.ink)

            Text(cloudSync.statusNote)
                .font(.editorialItalic(14))
                .foregroundStyle(Color.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                ForEach(syncIssueActions, id: \.id) { action in
                    Button(action: action.handler) {
                        Text(action.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(Color.secondary.opacity(0.10))
                            )
                            .overlay(
                                Capsule().strokeBorder(Color.inkHairline, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.editorialAmber.opacity(0.06), in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.editorialAmber.opacity(0.4), lineWidth: 0.5)
        )
    }

    private struct SyncIssueAction: Identifiable {
        let id = UUID()
        let label: String
        let handler: () -> Void
    }

    private var syncIssueActions: [SyncIssueAction] {
        var actions: [SyncIssueAction] = []
        switch cloudSync.status {
        case .noAccount:
            actions.append(SyncIssueAction(label: "Open System Settings") { openICloudSettings() })
            actions.append(SyncIssueAction(label: "Re-check") {
                Task { await cloudSync.refreshAccountStatus() }
            })
        case .failed(let message):
            if message.lowercased().contains("storage is full") {
                actions.append(SyncIssueAction(label: "Manage iCloud Storage") { openICloudSettings() })
            }
            actions.append(SyncIssueAction(label: "Re-check") {
                Task { await cloudSync.refreshAccountStatus() }
            })
            if cloudSync.lastErrorDiagnostics != nil {
                actions.append(SyncIssueAction(label: diagnosticsCopied ? "Copied" : "Copy diagnostics") {
                    copyDiagnostics()
                })
            }
        case .ready, .syncing, .unknown:
            break
        }
        return actions
    }

    private func openICloudSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane") {
            NSWorkspace.shared.open(url)
        }
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
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

    /// HomepageNote is meant to be a singleton — one record shared across the
    /// user's devices via CloudKit. The naive `if isEmpty { create }` runs on
    /// every device's first launch *before* CloudKit has pulled, so each device
    /// ends up creating its own distinct `CKRecord`. The records sync as
    /// separate rows and the unsorted query landed on a different one on each
    /// device, so edits never appeared to converge.
    ///
    /// Strategy: when multiple records exist, pick a canonical one
    /// deterministically (prefer non-empty body, then most recently modified)
    /// and delete the rest. Both devices reach the same conclusion from the
    /// same synced data, so the deletes are idempotent and converge.
    private func ensureHomepageNote() {
        if homepageNotes.isEmpty {
            context.insert(HomepageNote())
            try? context.save()
            return
        }
        guard homepageNotes.count > 1 else { return }
        let withContent = homepageNotes.filter {
            !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let pool = withContent.isEmpty ? homepageNotes : withContent
        // Tie-break with the lowest UUID string so two devices that see the
        // same modifiedDate values agree on the same winner.
        guard let canonical = pool.max(by: { a, b in
            if a.modifiedDate != b.modifiedDate { return a.modifiedDate < b.modifiedDate }
            return a.id.uuidString > b.id.uuidString
        }) else { return }
        for stale in homepageNotes where stale.id != canonical.id {
            context.delete(stale)
        }
        try? context.save()
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
    var leadingSymbol: String? = nil
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
                if let symbol = leadingSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                } else if let dot = leadingDot {
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

/// A pulsing "Composing your summary…" line shown while the LLM generates the
/// daily summary on first appear. Pulses opacity to signal activity without
/// using a spinner (which would clash with the editorial typography).
private struct ComposingSummaryLine: View {
    @State private var pulse: Bool = false

    var body: some View {
        Text("Composing your summary…")
            .opacity(pulse ? 0.45 : 0.85)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
