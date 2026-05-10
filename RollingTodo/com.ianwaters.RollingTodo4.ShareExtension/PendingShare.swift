import Foundation

/// JSON envelope shared with the host app via the App Group container.
/// Mirrors the canonical definition in `RollingTodo/Services/ShareOutbox.swift`
/// — keep the two in sync. The extension only needs the encode side; the host
/// owns the drain logic.
struct PendingShare: Codable {
    let id: UUID
    let title: String
    let body: String
    let asTodo: Bool
    let createdAt: Date

    static let appGroupID = "group.com.ianwaters.RollingTodo4"
    static let directoryName = "ShareOutbox"

    static func enqueue(_ share: PendingShare) throws {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else { throw ShareEnqueueError.appGroupUnavailable }
        let dir = groupURL.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(share.id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(share)
        try data.write(to: url, options: .atomic)
    }
}

enum ShareEnqueueError: Error {
    case appGroupUnavailable
}
