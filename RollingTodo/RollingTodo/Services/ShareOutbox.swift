import Foundation
import SwiftData

/// JSON envelope for a Share Extension hand-off. The extension writes one of
/// these per share into the App Group's `ShareOutbox/` directory; the host
/// app drains and turns them into real `Note`s via `NoteCreator`.
struct PendingShare: Codable {
    let id: UUID
    let title: String
    let body: String
    let asTodo: Bool
    let createdAt: Date
}

/// Outbox shared with the iOS Share Extension via the App Group container.
/// The extension can't easily reach SwiftData (cross-target model membership
/// in synchronized groups is awkward), so it writes a file per share here and
/// the host app drains into real `Note`s on launch / `scenePhase == .active`.
enum ShareOutbox {
    static let appGroupID = "group.com.ianwaters.RollingTodo4"
    static let directoryName = "ShareOutbox"

    /// Folder URL inside the App Group container, lazily created on first
    /// access. Returns `nil` if the App Group isn't entitled (e.g. running in
    /// previews without the entitlement plumbed through).
    static func directoryURL() -> URL? {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else { return nil }
        let dir = groupURL.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Called by the Share Extension to enqueue a new share.
    static func enqueue(_ share: PendingShare) throws {
        guard let dir = directoryURL() else { throw OutboxError.appGroupUnavailable }
        let url = dir.appendingPathComponent("\(share.id.uuidString).json")
        let data = try JSONEncoder.outbox.encode(share)
        try data.write(to: url, options: .atomic)
    }

    /// Called by the host app on launch and on every active-scene transition.
    /// Drains every queued share into a `Note` via `NoteCreator`. Successfully
    /// converted files are deleted; files that fail to decode are quarantined
    /// (renamed with a `.bad` suffix) so they don't block subsequent drains.
    @MainActor
    static func drain(into context: ModelContext) {
        guard let dir = directoryURL() else { return }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in entries where url.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: url)
                let share = try JSONDecoder.outbox.decode(PendingShare.self, from: data)
                NoteCreator.create(
                    in: context,
                    title: share.title,
                    body: share.body,
                    folder: nil,
                    asTodo: share.asTodo
                )
                try? fm.removeItem(at: url)
            } catch {
                let quarantined = url.appendingPathExtension("bad")
                _ = try? fm.moveItem(at: url, to: quarantined)
            }
        }
    }

    enum OutboxError: Error {
        case appGroupUnavailable
    }
}

private extension JSONEncoder {
    static let outbox: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

private extension JSONDecoder {
    static let outbox: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
