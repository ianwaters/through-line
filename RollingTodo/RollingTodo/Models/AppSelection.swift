import Foundation

enum SidebarSelection: Hashable {
    case home
    case allNotes
    case folder(UUID)
    case tag(String)
}

enum NoteListScope: Hashable {
    case all
    case folder(UUID)
    case tag(String)
}

enum AppTab: String, CaseIterable, Identifiable {
    case notes
    case archive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notes: "Notes"
        case .archive: "Archive"
        }
    }
}
