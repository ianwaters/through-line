#if DEBUG && os(macOS)
import AppKit

/// Tiny wrapper around NSAlert so the Debug → Seed CloudKit Schema flow can
/// surface its result without us building a SwiftUI sheet for a developer-only
/// menu item.
@MainActor
enum SchemaDebugAlerts {
    static func show(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
#endif
