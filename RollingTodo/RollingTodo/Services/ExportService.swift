import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum ExportService {
    /// Builds a zip archive containing one markdown file per note (with YAML front-matter)
    /// inside folders mirroring the in-app folder structure. Returns the zip Data.
    static func exportAll(context: ModelContext) -> Data? {
        let tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RollingTodo-Export-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpRoot) }

        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []

        for note in notes {
            let folderName = sanitize(note.folder?.name.isEmpty == false ? note.folder!.name : (note.folder == nil ? "Unfiled" : "Untitled"))
            let folderURL = tmpRoot.appendingPathComponent(folderName, isDirectory: true)
            try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

            let baseName = sanitize(note.title.isEmpty ? "Untitled" : note.title)
            let fileURL = uniqueURL(in: folderURL, base: baseName, ext: "md")
            let markdown = markdown(for: note)
            try? markdown.data(using: .utf8)?.write(to: fileURL)
        }

        return zip(directory: tmpRoot)
    }

    static func suggestedFilename(date: Date = .now) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "RollingTodo-Export-\(f.string(from: date))"
    }

    // MARK: - Markdown

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func markdown(for note: Note) -> String {
        var lines: [String] = ["---"]
        lines.append("title: \(yamlValue(note.title))")
        lines.append("created: \(isoFormatter.string(from: note.createdDate))")
        lines.append("modified: \(isoFormatter.string(from: note.modifiedDate))")
        if let folder = note.folder { lines.append("folder: \(yamlValue(folder.name))") }
        if let archived = note.archivedDate {
            lines.append("archived: \(isoFormatter.string(from: archived))")
        }
        if note.todoEnabled {
            lines.append("todoEnabled: true")
            lines.append("priority: \(note.priority.rawValue)")
            lines.append("status: \(note.status.rawValue)")
            if note.recurrence != .none {
                lines.append("recurrence: \(note.recurrenceRaw)")
            }
        }
        if note.labelColor != .none {
            lines.append("labelColor: \(note.labelColor.rawValue)")
        }
        if let due = note.dueDate {
            lines.append("dueDate: \(isoFormatter.string(from: due))")
        }
        if note.isPinned, let pin = note.pinnedDate {
            lines.append("pinned: \(isoFormatter.string(from: pin))")
        }
        if note.isLocked {
            lines.append("locked: true")
        }
        if let tags = note.tags, !tags.isEmpty {
            lines.append("tags: [\(tags.map(yamlValue).joined(separator: ", "))]")
        }
        if note.todoEnabled, let items = note.todoItems, !items.isEmpty {
            lines.append("todos:")
            for item in items.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                let mark = item.isDone ? "x" : " "
                lines.append("  - [\(mark)] \(yamlValue(item.text))")
            }
        }
        lines.append("---")
        lines.append("")
        lines.append(note.bodyMarkdown)
        return lines.joined(separator: "\n")
    }

    private static func yamlValue(_ s: String) -> String {
        let needsQuoting = s.contains(":") || s.contains("#") || s.contains("\n") || s.contains("\"") || s.isEmpty
        if needsQuoting {
            let escaped = s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            return "\"\(escaped)\""
        }
        return s
    }

    // MARK: - File helpers

    private static func sanitize(_ s: String) -> String {
        let banned: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
        var out = String(s.map { banned.contains($0) ? "_" : $0 })
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty { out = "Untitled" }
        return out
    }

    private static func uniqueURL(in dir: URL, base: String, ext: String) -> URL {
        var candidate = dir.appendingPathComponent("\(base).\(ext)")
        var i = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(i).\(ext)")
            i += 1
        }
        return candidate
    }

    private static func zip(directory: URL) -> Data? {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var data: Data?
        coordinator.coordinate(readingItemAt: directory, options: .forUploading, error: &coordError) { zipURL in
            data = try? Data(contentsOf: zipURL)
        }
        return data
    }
}

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        if let d = configuration.file.regularFileContents {
            self.data = d
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
