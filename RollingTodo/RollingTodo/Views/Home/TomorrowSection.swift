import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Evening preview of tomorrow's calendar events + due notes, with a one-line
/// AI sentence at the top. Caller decides whether to render it (typically:
/// only after 18:00 and only when there's something to show).
struct TomorrowSection: View {
    let events: [CalendarEventViewModel]
    let dueNotes: [Note]
    var onOpenNote: ((UUID) -> Void)? = nil

    @State private var summaryState: SummaryState = .pending
    @State private var intelligence = IntelligenceService.shared
    #if os(iOS)
    @State private var presentedEventID: PresentedTomorrowEventID?
    #endif

    private enum SummaryState: Equatable {
        case pending
        case ready(String)
        case useFallback
    }

    private var calendar: Calendar { .current }
    private var startOfTomorrow: Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))
            ?? calendar.startOfDay(for: .now)
    }

    private var weekdayNoun: String {
        startOfTomorrow.formatted(.dateTime.weekday(.wide))
    }

    private var detailLine: String {
        var parts: [String] = []
        parts.append(weekdayNoun)
        if events.count > 0 {
            parts.append("\(events.count) event\(events.count == 1 ? "" : "s")")
        }
        if dueNotes.count > 0 {
            parts.append("\(dueNotes.count) due")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 18)

            VStack(spacing: 0) {
                summaryRow
                if !events.isEmpty || !dueNotes.isEmpty {
                    Divider().background(Color.inkHairline)
                }
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    if index > 0 { Divider().background(Color.inkHairline) }
                    EventRow(event: event, onTap: { tap(event) })
                }
                if !events.isEmpty && !dueNotes.isEmpty {
                    Divider().background(Color.inkHairline)
                }
                ForEach(Array(dueNotes.enumerated()), id: \.element.id) { index, note in
                    if index > 0 { Divider().background(Color.inkHairline) }
                    TomorrowDueRow(note: note) {
                        onOpenNote?(note.id)
                    }
                }
            }
            .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.inkHairline, lineWidth: 0.5)
            )
        }
        #if os(iOS)
        .sheet(item: $presentedEventID) { wrapped in
            EventDetailSheet(eventID: wrapped.id)
        }
        #endif
        .task(id: summaryHash) {
            await regenerateSummaryIfNeeded()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Tomorrow")
                .eyebrowStyle()
            Spacer()
            Text(detailLine)
                .font(.editorialItalic(13))
                .foregroundStyle(Color.inkMuted)
        }
    }

    @ViewBuilder
    private var summaryRow: some View {
        let label: AnyView = switch summaryState {
        case .pending: AnyView(ComposingSummaryLine(text: "Composing tomorrow's preview…"))
        case .ready(let text): AnyView(Text(text))
        case .useFallback: AnyView(Text(fallbackText))
        }
        label
            .font(.editorialDisplay(15, weight: .regular))
            .italic()
            .foregroundStyle(Color.inkSoft)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .animation(.easeInOut(duration: 0.4), value: summaryState)
    }

    private var fallbackText: String {
        var bits: [String] = []
        if events.count > 0 {
            bits.append("\(events.count) event\(events.count == 1 ? "" : "s")")
        }
        if dueNotes.count > 0 {
            bits.append("\(dueNotes.count) due item\(dueNotes.count == 1 ? "" : "s")")
        }
        if bits.isEmpty { return "Tomorrow looks clear." }
        return "Tomorrow brings " + bits.joined(separator: " and ") + "."
    }

    private var summaryHash: Int {
        var hasher = Hasher()
        hasher.combine(events.map(\.id))
        hasher.combine(dueNotes.count)
        hasher.combine(urgentDueCount)
        hasher.combine(Calendar.current.component(.hour, from: .now))
        return hasher.finalize()
    }

    private var urgentDueCount: Int {
        dueNotes.reduce(0) { $0 + ($1.priority == .urgent ? 1 : 0) }
    }

    private func tap(_ event: CalendarEventViewModel) {
        #if os(macOS)
        CalendarLinker.openEvent(id: event.id)
        #else
        presentedEventID = PresentedTomorrowEventID(id: event.id)
        #endif
    }

    private func regenerateSummaryIfNeeded() async {
        let hash = summaryHash
        if let cached = intelligence.cachedTomorrowSummary(matching: hash) {
            summaryState = .ready(cached)
            return
        }
        try? await Task.sleep(for: .milliseconds(500))
        if Task.isCancelled { return }

        guard intelligence.isAvailable else {
            summaryState = .useFallback
            return
        }

        let firstEvent = events.first
        let input = IntelligenceService.TomorrowSummaryInput(
            weekdayNoun: weekdayNoun,
            eventCount: events.count,
            firstEventTime: firstEvent.map { $0.isAllDay ? "all day" : $0.startDate.formatted(.dateTime.hour().minute()) },
            firstEventTitle: firstEvent?.title,
            dueCount: dueNotes.count,
            urgentDueCount: urgentDueCount
        )
        let result = await intelligence.tomorrowSummary(input, hash: hash)
        if Task.isCancelled { return }

        if let result {
            summaryState = .ready(result)
        } else if case .ready = summaryState {
            // Keep prior cached value if regeneration failed.
        } else {
            summaryState = .useFallback
        }
    }
}

#if os(iOS)
private struct PresentedTomorrowEventID: Identifiable {
    let id: String
}
#endif

private struct TomorrowDueRow: View {
    let note: Note
    let action: () -> Void

    @State private var isHovered: Bool = false

    private var priorityDot: Color {
        switch note.priority {
        case .urgent: .editorialRed
        case .high: .editorialAmber
        default: note.todoEnabled ? note.status.tint : .clear
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    Circle()
                        .fill(priorityDot)
                        .frame(width: 8, height: 8)
                }
                .frame(width: 56, alignment: .leading)

                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.editorialDisplay(17, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "arrow.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(isHovered ? 1 : 0))
                    .offset(x: isHovered ? 0 : -4)
                    .frame(width: 14)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(.rect)
            .background(isHovered ? Color.accentColor.opacity(0.04) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}

private struct ComposingSummaryLine: View {
    let text: String
    @State private var pulse: Bool = false

    var body: some View {
        Text(text)
            .opacity(pulse ? 0.45 : 0.85)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
