import AppIntents
import Foundation

/// Siri / Shortcuts reach: capture without even opening the app.
/// Intents run in-process and share the app's container.

struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a Task"
    static let description = IntentDescription("Create a task in PocketBrains.")

    @Parameter(title: "Title") var taskTitle: String
    @Parameter(title: "Due date") var due: Date?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let services = DataServices(context: Store.sharedContainer.mainContext)
        _ = services.tasks.create(title: taskTitle, due: due)
        return .result(dialog: "Added “\(taskTitle)”.")
    }
}

struct QuickNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture a Note"
    static let description = IntentDescription("Capture a note in PocketBrains.")

    @Parameter(title: "Note") var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let services = DataServices(context: Store.sharedContainer.mainContext)
        let title = String(text.prefix(48))
        let note = services.notes.create(title: title, body: text)
        _ = services.graph.autoWeave(note: note,
                                     projects: services.projects.all(),
                                     tasks: services.tasks.all(includeDone: true))
        return .result(dialog: "Noted.")
    }
}

struct PocketBrainsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add a task in \(.applicationName)",
                "Remind me in \(.applicationName)",
            ],
            shortTitle: "Add Task",
            systemImageName: "checkmark.circle")
        AppShortcut(
            intent: QuickNoteIntent(),
            phrases: [
                "Capture a note in \(.applicationName)",
                "Take a note in \(.applicationName)",
            ],
            shortTitle: "Capture Note",
            systemImageName: "square.and.pencil")
    }
}
