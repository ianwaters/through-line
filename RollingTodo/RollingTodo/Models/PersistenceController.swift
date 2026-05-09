import Foundation
import SwiftData

enum PersistenceController {
    static let cloudContainerID = "iCloud.com.ianwaters.RollingTodo2"

    static let shared: ModelContainer = {
        let schema = Schema([
            Folder.self,
            Note.self,
            TodoItem.self,
            HomepageNote.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .private(cloudContainerID)
        )
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    @MainActor
    static let preview: ModelContainer = {
        let schema = Schema([
            Folder.self,
            Note.self,
            TodoItem.self,
            HomepageNote.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: config)
        SampleData.seed(into: container.mainContext)
        return container
    }()
}

@MainActor
enum SampleData {
    static func seed(into context: ModelContext) {
        let work = Folder(name: "Work", sortOrder: 0)
        let personal = Folder(name: "Personal", sortOrder: 1)
        context.insert(work)
        context.insert(personal)

        let cal = Calendar.current

        let n1 = Note(title: "Ship v1 to TestFlight", folder: work, sortOrder: 0)
        n1.bodyMarkdown = "Get RollingTodo into TestFlight before end of month."
        n1.todoEnabled = true
        n1.priority = .urgent
        n1.status = .inProgress
        n1.labelColor = .red
        n1.dueDate = cal.date(byAdding: .day, value: -2, to: .now)
        context.insert(n1)

        let n2 = Note(title: "Pick up groceries", folder: personal, sortOrder: 0)
        n2.todoEnabled = true
        n2.priority = .normal
        n2.status = .readyToStart
        n2.labelColor = .green
        n2.dueDate = cal.startOfDay(for: .now)
        context.insert(n2)

        let n3 = Note(title: "Refactor sidebar component", folder: work, sortOrder: 1)
        n3.todoEnabled = true
        n3.priority = .high
        n3.status = .triage
        n3.labelColor = .blue
        n3.dueDate = cal.date(byAdding: .day, value: 5, to: .now)
        context.insert(n3)

        let n4 = Note(title: "Designing Data-Intensive Applications", folder: personal, sortOrder: 1)
        n4.bodyMarkdown = """
        ## Reading goals
        - Foundations of data systems
        - Distributed data
        - Derived data
        """
        context.insert(n4)

        let n5 = Note(title: "Old, finished thing", folder: work, sortOrder: 2)
        n5.todoEnabled = true
        n5.priority = .low
        n5.status = .done
        n5.labelColor = .gray
        context.insert(n5)

        let n6 = Note(title: "Cancelled experiment", folder: work, sortOrder: 3)
        n6.todoEnabled = true
        n6.status = .cancelled
        context.insert(n6)

        let homepage = HomepageNote(body: "Welcome to RollingTodo. Edit this note to surface anything to your home screen.")
        context.insert(homepage)
    }
}
