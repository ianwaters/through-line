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

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = EKEventViewController()
        vc.event = event
        vc.allowsEditing = false
        vc.allowsCalendarPreview = true
        vc.delegate = context.coordinator
        configureDoneButton(on: vc, with: context.coordinator)
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        if let vc = uiViewController.viewControllers.first as? EKEventViewController {
            configureDoneButton(on: vc, with: context.coordinator)
        }
    }

    private func configureDoneButton(on vc: EKEventViewController, with coordinator: Coordinator) {
        // Leading position avoids EKEventViewController's own trailing items
        // (Edit / Share) overwriting ours when it lays itself out.
        let item = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { _ in coordinator.dismiss() }
        )
        vc.navigationItem.leftBarButtonItem = item
    }

    final class Coordinator: NSObject, EKEventViewDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }

        func dismiss() { onDone() }

        func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) {
            onDone()
        }
    }
}
#endif
