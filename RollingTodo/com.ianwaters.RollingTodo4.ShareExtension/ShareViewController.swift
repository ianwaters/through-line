import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Entry point for the iOS Share Extension. Reads the shared URL/text out of
/// the `NSExtensionContext`, hands it to the SwiftUI `ShareView`, and on save
/// writes a `PendingShare` JSON envelope to the App Group container for the
/// host app to drain into a real `Note`.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        Task { @MainActor in
            let initial = await loadInitialContent()
            present(initial: initial)
        }
    }

    private func present(initial: SharePayload) {
        let host = UIHostingController(rootView: ShareView(
            initial: initial,
            onSave: { [weak self] share in
                self?.completeWith(share: share)
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        ))
        host.modalPresentationStyle = .formSheet
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }

    private func completeWith(share: PendingShare) {
        do {
            try PendingShare.enqueue(share)
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            // Surface the error briefly so the user knows it didn't save, then
            // bail. The host app's drainer won't see anything because nothing
            // was written.
            let alert = UIAlertController(
                title: "Couldn't save",
                message: "We couldn't write to the shared container. Please try again.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.cancel()
            })
            present(alert, animated: true)
        }
    }

    private func cancel() {
        let err = NSError(domain: "RollingTodoShareExtension", code: NSUserCancelledError)
        extensionContext?.cancelRequest(withError: err)
    }

    /// Pulls the first URL or text attachment from the extension input. Falls
    /// back to an empty payload if nothing recognisable is provided.
    private func loadInitialContent() async -> SharePayload {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            return SharePayload(suggestedTitle: "", suggestedBody: "")
        }
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                        return SharePayload(suggestedTitle: url.absoluteString, suggestedBody: "")
                    }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                        let firstLine = text.components(separatedBy: .newlines).first?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return SharePayload(suggestedTitle: firstLine, suggestedBody: text)
                    }
                }
            }
        }
        return SharePayload(suggestedTitle: "", suggestedBody: "")
    }
}

struct SharePayload {
    var suggestedTitle: String
    var suggestedBody: String
}
