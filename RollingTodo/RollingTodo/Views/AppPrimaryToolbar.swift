import SwiftUI

/// Three top-level actions surfaced everywhere in the app: Focus toggle,
/// Quick Capture, Settings. Used in ContentView's window toolbar on macOS
/// and in each column's nav bar on iOS so they remain reachable from any
/// screen on iPhone.
struct AppPrimaryToolbar: ToolbarContent {
    @Binding var focusModeEnabled: Bool
    let onQuickCapture: () -> Void
    let onAINote: () -> Void
    let onSettings: () -> Void
    let intelligenceAvailable: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { focusModeEnabled.toggle() } label: {
                Label("Focus", systemImage: focusModeEnabled ? "scope" : "circle.dotted")
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .help(focusModeEnabled ? "Turn off Focus (⇧⌘F)" : "Focus on what's due or urgent (⇧⌘F)")
            .foregroundStyle(focusModeEnabled ? Color.accentColor : Color.secondary)

            Button(action: onQuickCapture) {
                Label("Quick Capture", systemImage: "bolt.fill")
            }
            .keyboardShortcut("k", modifiers: .command)
            .help("Quick Capture (⌘K)")

            if intelligenceAvailable {
                Button(action: onAINote) {
                    Label("New Note from Prompt", systemImage: "wand.and.sparkles")
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .help("New Note from Prompt (⇧⌘K)")
            }

            Button(action: onSettings) {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Settings (⌘,)")
        }
    }
}

/// On iOS, attaches `AppPrimaryToolbar` to the underlying view. On macOS it's
/// a no-op — the macOS toolbar lives at the NavigationSplitView root. Used by
/// detail-column placeholders (empty editor, archive empty) so the primary
/// actions stay reachable when no note is selected on iPad.
struct IOSPrimaryToolbarFallback: ViewModifier {
    @Binding var focusModeEnabled: Bool
    let intelligenceAvailable: Bool
    let onQuickCapture: () -> Void
    let onAINote: () -> Void
    let onSettings: () -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
        content.toolbar {
            AppPrimaryToolbar(
                focusModeEnabled: $focusModeEnabled,
                onQuickCapture: onQuickCapture,
                onAINote: onAINote,
                onSettings: onSettings,
                intelligenceAvailable: intelligenceAvailable
            )
        }
        #else
        content
        #endif
    }
}
