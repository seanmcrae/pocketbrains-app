import AppIntents
import Foundation

/// Siri / Shortcuts reach: capture and ask without opening the app.
/// Intents run in-process, share the app's container, and go through the
/// same ToolBox → DataServices write path (so they are journaled and
/// undoable from the thread like any other action).

@MainActor
enum IntentRuntime {
    /// One toolbox per process for intents, on the shared container.
    static let toolbox: ToolBox = {
        let context = Store.sharedContainer.mainContext
        return ToolBox(services: DataServices(context: context),
                       semanticIndex: SemanticIndex(context: context))
    }()

    /// Answer a request with the best available brain and return its final
    /// text. Falls back to the deterministic router if a model fails.
    static func ask(_ question: String) async -> String {
        let box = toolbox
        box.turnGroupID = UUID().uuidString
        defer { box.turnGroupID = "" }
        let backend = AgentVoice.selectBackend(toolbox: box)
        do {
            var final = ""
            for try await event in backend.reply(to: question) {
                if case .done(let text) = event { final = text }
            }
            if !final.isEmpty { return final }
        } catch {
            // fall through to the deterministic floor
        }
        return IntentFallbackBackend.routeTurn(question, toolbox: box).reply
    }

    /// Blockers for a project as a spoken sentence (pure, unit-tested).
    static func blockersDialog(for project: Project) -> String {
        let blockers = project.blockers
        guard !blockers.isEmpty else {
            return "Nothing is blocking \(project.name). \(project.openTasks.count) open task\(project.openTasks.count == 1 ? "" : "s")."
        }
        let lines = blockers.map { task -> String in
            let waiting = task.blockers.filter { !$0.isDone }.map(\.title)
            return "“\(task.title)” is waiting on \(waiting.joined(separator: " and "))"
        }
        return "\(project.name): " + lines.joined(separator: "; ") + "."
    }
}

struct AskPocketBrainsIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask PocketBrains"
    static let description = IntentDescription("Ask your on-device agent anything about your tasks, projects and notes.")

    @Parameter(title: "Request")
    var request: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await IntentRuntime.ask(request)
        return .result(dialog: "\(answer)")
    }
}

struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a Task"
    static let description = IntentDescription("Create a task in PocketBrains.")

    @Parameter(title: "Title") var taskTitle: String
    @Parameter(title: "Due date") var due: Date?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = IntentRuntime.toolbox.createTask(title: taskTitle, dueDate: due)
        return .result(dialog: "\(result.summary).")
    }
}

struct QuickNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture a Note"
    static let description = IntentDescription("Capture a note in PocketBrains.")

    @Parameter(title: "Note") var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = IntentRuntime.toolbox.createNote(title: String(text.prefix(48)), body: text)
        return .result(dialog: "Noted.")
    }
}

// MARK: - What's blocking <project>

struct ProjectEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Project"
    static let defaultQuery = ProjectEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ProjectEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [ProjectEntity] {
        await MainActor.run { () -> [ProjectEntity] in
            IntentRuntime.toolbox.services.projects.all()
                .filter { identifiers.contains($0.id) }
                .map { ProjectEntity(id: $0.id, name: $0.name) }
        }
    }

    func entities(matching string: String) async throws -> [ProjectEntity] {
        await MainActor.run { () -> [ProjectEntity] in
            let q = string.lowercased()
            return IntentRuntime.toolbox.services.projects.all()
                .filter { $0.name.lowercased().contains(q) }
                .map { ProjectEntity(id: $0.id, name: $0.name) }
        }
    }

    func suggestedEntities() async throws -> [ProjectEntity] {
        await MainActor.run { () -> [ProjectEntity] in
            IntentRuntime.toolbox.services.projects.all()
                .filter { $0.status == .active }
                .map { ProjectEntity(id: $0.id, name: $0.name) }
        }
    }
}

struct ProjectBlockersIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Blocking a Project"
    static let description = IntentDescription("Hear which tasks in a project are blocked, and on what.")

    @Parameter(title: "Project") var project: ProjectEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = IntentRuntime.toolbox.services.projects.find(id: project.id) else {
            return .result(dialog: "I couldn't find that project.")
        }
        return .result(dialog: "\(IntentRuntime.blockersDialog(for: model))")
    }
}

struct PocketBrainsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskPocketBrainsIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask \(.applicationName) a question",
            ],
            shortTitle: "Ask PocketBrains",
            systemImageName: "sparkles")
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add a task in \(.applicationName)",
                "Remind me in \(.applicationName)",
            ],
            shortTitle: "Add Task",
            systemImageName: "checkmark.circle")
        AppShortcut(
            intent: ProjectBlockersIntent(),
            phrases: [
                "What's blocking \(\.$project) in \(.applicationName)",
                "What's blocking my project in \(.applicationName)",
            ],
            shortTitle: "What's Blocking",
            systemImageName: "hourglass")
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
