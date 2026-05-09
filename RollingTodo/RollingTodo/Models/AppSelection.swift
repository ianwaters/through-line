import Foundation

enum SidebarSelection: Hashable {
    case home
    case allNotes
    case folder(UUID)
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
