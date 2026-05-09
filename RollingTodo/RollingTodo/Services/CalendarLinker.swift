import SwiftUI
import EventKit

#if os(macOS)
import AppKit
#else
import UIKit
import EventKitUI
#endif

enum CalendarLinker {
    #if os(macOS)
    @MainActor
    static func openEvent(id: String) {
        guard let url = URL(string: "ical://ekevent/\(id)") else { return }
        NSWorkspace.shared.open(url)
    }
    #endif
}

#if os(iOS)
struct EventDetailSheet: View {
    let eventID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let event = CalendarEventsService.shared.event(withIdentifier: eventID) {
            EventDetailRepresentable(event: event, onDone: { dismiss() })
                .ignoresSafeArea()
        } else {
            VStack(spacing: 12) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color.inkMuted)
                Text("Event not found")
                    .font(.editorialDisplay(20, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Button("Done") { dismiss() }
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        }
    }
}

private struct EventDetailRepresentable: UIViewControllerRepresentable {
    let event: EKEvent
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = EKEventViewController()
        vc.event = event
        vc.allowsEditing = false
        vc.allowsCalendarPreview = true
        vc.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { _ in onDone() }
        )
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
#endif
