import SwiftUI
import EventKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct EventsTodaySection: View {
    @State private var service = CalendarEventsService.shared
    #if os(iOS)
    @State private var presentedEventID: PresentedEventID?
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 18)

            VStack(spacing: 0) {
                content
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
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Today's Events")
                .eyebrowStyle()
            Spacer()
            Text(headerDetail)
                .font(.editorialItalic(13))
                .foregroundStyle(Color.inkMuted)
        }
    }

    private var headerDetail: String {
        switch service.authStatus {
        case .denied, .restricted: "Access denied"
        case .notDetermined: "Permission needed"
        case .writeOnly: "Read access needed"
        case .fullAccess:
            if service.selectedCalendarIDs.isEmpty { "No calendars chosen" }
            else if service.events.isEmpty { "Nothing on the calendar" }
            else if service.events.count == 1 { "1 event" }
            else { "\(service.events.count) events" }
        @unknown default: ""
        }
    }

    @ViewBuilder
    private var content: some View {
        switch service.authStatus {
        case .notDetermined:
            grantAccessRow
        case .denied, .restricted, .writeOnly:
            deniedRow
        case .fullAccess:
            if service.selectedCalendarIDs.isEmpty {
                placeholderRow(
                    title: "Pick which calendars to show",
                    detail: "Choose them in Settings → Calendar Events.",
                    symbol: "calendar.badge.plus"
                )
            } else if service.events.isEmpty {
                placeholderRow(
                    title: "Nothing scheduled",
                    detail: "Your day is clear.",
                    symbol: "calendar"
                )
            } else {
                ForEach(Array(service.events.enumerated()), id: \.element.id) { index, event in
                    if index > 0 { Divider().background(Color.inkHairline) }
                    EventRow(event: event, onTap: { tap(event) })
                }
            }
        @unknown default:
            placeholderRow(title: "Calendar unavailable", detail: nil, symbol: "calendar")
        }
    }

    private var grantAccessRow: some View {
        Button {
            Task { _ = await service.requestAccess() }
        } label: {
            rowChrome(
                symbol: "lock.open",
                title: "Grant access to your Calendar",
                detail: "We'll show today's events here.",
                trailing: AnyView(
                    Image(systemName: "arrow.forward")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                )
            )
        }
        .buttonStyle(.plain)
    }

    private var deniedRow: some View {
        Button(action: openPrivacySettings) {
            rowChrome(
                symbol: "lock.fill",
                title: "Calendar access denied",
                detail: "Open System Settings to enable.",
                trailing: AnyView(
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                )
            )
        }
        .buttonStyle(.plain)
    }

    private func placeholderRow(title: String, detail: String?, symbol: String) -> some View {
        rowChrome(
            symbol: symbol,
            title: title,
            detail: detail,
            trailing: nil
        )
    }

    private func rowChrome(symbol: String, title: String, detail: String?, trailing: AnyView?) -> some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(Color.accentColor.opacity(0.7))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.editorialDisplay(17, weight: .medium))
                    .foregroundStyle(Color.ink)
                if let detail {
                    Text(detail)
                        .font(.editorialItalic(13))
                        .foregroundStyle(Color.inkMuted)
                }
            }
            Spacer()
            if let trailing { trailing }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .contentShape(.rect)
    }

    private func tap(_ event: CalendarEventViewModel) {
        #if os(macOS)
        CalendarLinker.openEvent(id: event.id)
        #else
        presentedEventID = PresentedEventID(id: event.id)
        #endif
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
}

#if os(iOS)
private struct PresentedEventID: Identifiable {
    let id: String
}
#endif

private struct EventRow: View {
    let event: CalendarEventViewModel
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 18) {
                timeColumn
                    .frame(width: 56, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.editorialDisplay(17, weight: .medium))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    if let location = event.location {
                        Text(location)
                            .font(.editorialItalic(13))
                            .foregroundStyle(Color.inkMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Circle()
                    .fill(event.calendarColor)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(event.calendarTitle)

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

    @ViewBuilder
    private var timeColumn: some View {
        if event.isAllDay {
            Text("All day")
                .font(.editorialItalic(13))
                .foregroundStyle(Color.inkMuted)
        } else {
            Text(event.startDate.formatted(.dateTime.hour().minute()))
                .font(.editorialNumeric(15, weight: .regular))
                .foregroundStyle(Color.ink)
        }
    }
}
