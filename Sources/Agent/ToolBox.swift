import Foundation
import SwiftData

/// Result of any tool run. `summary` is the one-line card text shown in the
/// thread; `detail` is what the model reads to compose its reply.
struct ToolResult {
    var summary: String
    var detail: String
    var succeeded: Bool = true
    /// Journal entry recorded by a mutating tool, so the card can offer Undo.
    var journalID: UUID? = nil
    /// Structured outputs later plan steps can reference: `ref` (an exact
    /// `id:<uuid>` reference), `kind`, `title`, and tool-specific keys.
    var outputs: [String: String] = [:]

    func record(toolName: String) -> ToolEventRecord {
        .init(toolName: toolName, summary: summary, detail: detail,
              succeeded: succeeded, journalID: journalID)
    }
}

/// The canonical implementation of every capability the agent has.
/// Every backend (Foundation Models, MLX, fallback parser) funnels here,
/// and here funnels into DataServices — one write path for the whole app.
/// Every mutation also records its inverse in the action journal.
@MainActor
final class ToolBox {
    let services: DataServices
    let semanticIndex: SemanticIndex

    /// Journal group for the current turn or plan. The orchestrator sets a
    /// fresh value per turn so "undo that" reverts everything the turn did;
    /// when empty (App Intents, tests), each action is its own group.
    var turnGroupID: String = ""

    init(services: DataServices, semanticIndex: SemanticIndex) {
        self.services = services
        self.semanticIndex = semanticIndex
    }

    /// Record an inverse for a mutation and return the journal id.
    @discardableResult
    func journal(_ tool: String, _ summary: String, _ inverse: [InverseStep]) -> UUID {
        let group = turnGroupID.isEmpty ? UUID().uuidString : turnGroupID
        return services.journal.record(tool: tool, summary: summary,
                                       group: group, inverse: inverse).id
    }

    // MARK: Tasks

    func createTask(title: String, details: String = "", due: String? = nil,
                    priority: String? = nil, projectName: String? = nil) -> ToolResult {
        let dueDate = due.flatMap { NaturalDateParser.parse($0) }
        let pri = TaskPriority.from(priority)
        let project = projectName.flatMap { services.projects.find(matching: $0) }
        let task = services.tasks.create(
            title: title, details: details, due: dueDate, priority: pri, project: project)
        var bits = ["Created task “\(task.title)”"]
        if let dueDate { bits.append("due \(NaturalDateParser.describe(dueDate))") }
        if let project { bits.append("in \(project.name)") }
        else if let projectName, !projectName.isEmpty { bits.append("unfiled (no project “\(projectName)”)") }
        let summary = bits.joined(separator: ", ")
        let jid = journal("createTask", summary, [.init(kind: .deleteTask, id: task.id)])
        return ToolResult(summary: summary, detail: summary + ".", journalID: jid,
                          outputs: ["ref": EntityRef.make(task.id), "kind": "task", "title": task.title])
    }

    func completeTask(query: String) -> ToolResult {
        guard let task = services.tasks.find(matching: query) else {
            return ToolResult(summary: "No task matching “\(query)”",
                              detail: "No task found matching “\(query)”.", succeeded: false)
        }
        if task.isDone {
            return ToolResult(summary: "“\(task.title)” was already done",
                              detail: "“\(task.title)” was already marked done.",
                              outputs: ["ref": EntityRef.make(task.id), "kind": "task", "title": task.title])
        }
        services.tasks.complete(task)
        let summary = "Completed “\(task.title)”"
        let jid = journal("completeTask", summary, [.init(kind: .reopenTask, id: task.id)])
        return ToolResult(summary: summary,
                          detail: "Marked “\(task.title)” as done.", journalID: jid,
                          outputs: ["ref": EntityRef.make(task.id), "kind": "task", "title": task.title])
    }

    func updateTask(query: String, due: String? = nil, priority: String? = nil,
                    projectName: String? = nil) -> ToolResult {
        guard let task = services.tasks.find(matching: query) else {
            return ToolResult(summary: "No task matching “\(query)”",
                              detail: "No task found matching “\(query)”.", succeeded: false)
        }
        let before = TaskSnapshot(task)
        var changes: [String] = []
        if let due, let date = NaturalDateParser.parse(due) {
            services.tasks.update(task, due: date)
            changes.append("due \(NaturalDateParser.describe(date))")
        }
        if let priority {
            services.tasks.update(task, priority: .from(priority))
            changes.append("priority \(TaskPriority.from(priority).label.lowercased())")
        }
        if let projectName, let project = services.projects.find(matching: projectName) {
            services.tasks.update(task, project: project)
            changes.append("moved to \(project.name)")
        }
        let what = changes.isEmpty ? "no changes" : changes.joined(separator: ", ")
        let summary = "Updated “\(task.title)”: \(what)"
        let jid = changes.isEmpty ? nil
            : journal("updateTask", summary, [.init(kind: .restoreTask, id: task.id, task: before)])
        return ToolResult(summary: summary,
                          detail: "Updated “\(task.title)” — \(what).", journalID: jid,
                          outputs: ["ref": EntityRef.make(task.id), "kind": "task", "title": task.title])
    }

    func queryTasks(filter: String, projectName: String? = nil) -> ToolResult {
        let project = projectName.flatMap { services.projects.find(matching: $0) }
        var items: [TaskItem]
        switch filter.lowercased() {
        case "today", "due": items = services.tasks.dueToday()
        case "overdue": items = services.tasks.all().filter(\.isOverdue)
        case "blocked": items = services.tasks.all().filter(\.isBlocked)
        case "upcoming": items = services.tasks.dueWithin(days: 7)
        default: items = services.tasks.all()
        }
        if let project { items = items.filter { $0.project?.id == project.id } }
        guard !items.isEmpty else {
            return ToolResult(summary: "No matching tasks",
                              detail: "No tasks match filter “\(filter)”.")
        }
        let lines = items.prefix(12).map { task -> String in
            var line = "• \(task.title)"
            if let d = task.dueDate { line += " (\(NaturalDateParser.describe(d)))" }
            if task.isBlocked { line += " [blocked]" }
            return line
        }
        return ToolResult(summary: "\(items.count) task\(items.count == 1 ? "" : "s") found",
                          detail: lines.joined(separator: "\n"))
    }

    // MARK: Projects

    func createProject(name: String, summary: String = "") -> ToolResult {
        let project = services.projects.create(name: name, summary: summary)
        let line = "Created project “\(project.name)”"
        let jid = journal("createProject", line, [.init(kind: .deleteProject, id: project.id)])
        return ToolResult(summary: line,
                          detail: "Created project “\(project.name)” (\(project.hue.name)).", journalID: jid,
                          outputs: ["ref": EntityRef.make(project.id), "kind": "project", "title": project.name])
    }

    func projectStatus(name: String) -> ToolResult {
        guard let project = services.projects.find(matching: name) else {
            return ToolResult(summary: "No project matching “\(name)”",
                              detail: "No project found matching “\(name)”.", succeeded: false)
        }
        let open = project.openTasks
        let blockers = project.blockers
        var lines = [
            "\(project.name): \(Int(project.progress * 100))% complete, \(open.count) open task\(open.count == 1 ? "" : "s")."
        ]
        if !blockers.isEmpty {
            lines.append("Blocked: " + blockers.map { task in
                let blockingTitles = task.blockers
                    .filter { !$0.isDone }.map(\.title).joined(separator: ", ")
                return "“\(task.title)” waiting on \(blockingTitles)"
            }.joined(separator: "; "))
        }
        for milestone in (project.milestones ?? []) where !milestone.isReached {
            if let t = milestone.targetDate {
                lines.append("Next milestone: \(milestone.title) (\(NaturalDateParser.describe(t)))")
            }
        }
        lines.append(contentsOf: services.projects.recentActivity(for: project, limit: 3))
        return ToolResult(summary: "\(project.name) — \(Int(project.progress * 100))%, \(blockers.count) blocker\(blockers.count == 1 ? "" : "s")",
                          detail: lines.joined(separator: "\n"))
    }

    func addMilestone(projectName: String, title: String, target: String? = nil) -> ToolResult {
        guard let project = services.projects.find(matching: projectName) else {
            return ToolResult(summary: "No project matching “\(projectName)”",
                              detail: "No project found.", succeeded: false)
        }
        let date = target.flatMap { NaturalDateParser.parse($0) }
        let milestone = services.projects.addMilestone(to: project, title: title, target: date)
        var line = "Milestone “\(title)” added to \(project.name)"
        if let date { line += ", target \(NaturalDateParser.describe(date))" }
        let jid = journal("addMilestone", line, [.init(kind: .deleteMilestone, id: milestone.id)])
        return ToolResult(summary: line, detail: line + ".", journalID: jid,
                          outputs: ["ref": EntityRef.make(milestone.id), "kind": "milestone", "title": title])
    }

    // MARK: Notes

    func createNote(title: String, body: String, tags: [String] = [],
                    projectName: String? = nil) -> ToolResult {
        let project = projectName.flatMap { services.projects.find(matching: $0) }
        let note = services.notes.create(title: title, body: body, tags: tags, project: project)
        semanticIndex.index(note: note)
        if let project {
            services.graph.link(from: (.note, note.id), to: (.project, project.id), relation: "belongs-to")
        }
        let woven = services.graph.autoWeave(
            note: note, projects: services.projects.all(),
            tasks: services.tasks.all(includeDone: true))
        let weaveNote = woven.isEmpty
            ? "" : " Linked to \(woven.joined(separator: ", "))."
        let summary = woven.isEmpty
            ? "Noted “\(note.title)”"
            : "Noted “\(note.title)” · \(woven.count) link\(woven.count == 1 ? "" : "s") woven"
        // Deleting the note also removes every edge touching it (belongs-to, woven).
        let jid = journal("createNote", summary, [.init(kind: .deleteNote, id: note.id)])
        return ToolResult(summary: summary,
                          detail: "Created note “\(note.title)”\(project.map { " in \($0.name)" } ?? "").\(weaveNote)",
                          journalID: jid,
                          outputs: ["ref": EntityRef.make(note.id), "kind": "note", "title": note.title])
    }

    func appendNote(query: String, text: String) -> ToolResult {
        guard let note = services.notes.find(matching: query) else {
            return ToolResult(summary: "No note matching “\(query)”",
                              detail: "No note found.", succeeded: false)
        }
        let previous = note.body
        services.notes.append(note, text: text)
        semanticIndex.index(note: note)
        let summary = "Appended to “\(note.title)”"
        let jid = journal("appendNote", summary, [.init(kind: .restoreNoteBody, id: note.id, text: previous)])
        return ToolResult(summary: summary,
                          detail: "Appended to note “\(note.title)”.", journalID: jid,
                          outputs: ["ref": EntityRef.make(note.id), "kind": "note", "title": note.title])
    }

    func searchNotes(query: String) -> ToolResult {
        let semantic = semanticIndex.search(query, limit: 5)
        let keyword = services.notes.keywordSearch(query, limit: 5)
        var seen = Set<UUID>()
        let merged = (semantic + keyword).filter { seen.insert($0.id).inserted }
        guard !merged.isEmpty else {
            return ToolResult(summary: "No notes found", detail: "No notes match “\(query)”.")
        }
        let lines = merged.prefix(6).map { "• \($0.title): \($0.body.prefix(140))" }
        return ToolResult(summary: "\(merged.count) note\(merged.count == 1 ? "" : "s") found",
                          detail: lines.joined(separator: "\n"))
    }

    func notesFrom(dayDescription: String) -> ToolResult {
        let day = NaturalDateParser.parse(dayDescription)
            ?? Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let notes = services.notes.from(day: day)
        guard !notes.isEmpty else {
            return ToolResult(summary: "No notes that day",
                              detail: "No notes were created or edited \(dayDescription).")
        }
        let lines = notes.map { "• \($0.title):\n\($0.body)" }
        return ToolResult(summary: "\(notes.count) note\(notes.count == 1 ? "" : "s") from \(dayDescription)",
                          detail: lines.joined(separator: "\n\n"))
    }

    // MARK: Knowledge

    func linkItems(from: String, to: String, relation: String = "references") -> ToolResult {
        guard let source = resolveEntity(from) else {
            return ToolResult(summary: "Couldn't find “\(from)”",
                              detail: "No entity found matching “\(from)”.", succeeded: false)
        }
        guard let target = resolveEntity(to) else {
            return ToolResult(summary: "Couldn't find “\(to)”",
                              detail: "No entity found matching “\(to)”.", succeeded: false)
        }
        let existed = services.graph.allLinks().contains {
            $0.fromID == source.1 && $0.toID == target.1 && $0.relation == relation
        }
        let link = services.graph.link(from: (source.0, source.1), to: (target.0, target.1), relation: relation)
        let summary = "Linked “\(source.2)” → “\(target.2)”"
        let jid = existed ? nil
            : journal("linkItems", summary, [.init(kind: .deleteLink, id: link.id)])
        return ToolResult(summary: summary,
                          detail: "Linked \(source.0.rawValue) “\(source.2)” to \(target.0.rawValue) “\(target.2)” (\(relation)).",
                          journalID: jid,
                          outputs: ["ref": EntityRef.make(link.id), "kind": "link",
                                    "from": EntityRef.make(source.1), "to": EntityRef.make(target.1)])
    }

    /// Resolve a free-text reference to any entity, preferring notes → tasks → projects.
    func resolveEntity(_ query: String) -> (EntityKind, UUID, String)? {
        if let note = services.notes.find(matching: query) { return (.note, note.id, note.title) }
        if let task = services.tasks.find(matching: query) { return (.task, task.id, task.title) }
        if let project = services.projects.find(matching: query) { return (.project, project.id, project.name) }
        return nil
    }

    // MARK: Undo

    /// Revert the last turn/plan (`turn`, default) or only the last action (`step`).
    func undo(scope: String? = nil) -> ToolResult {
        UndoEngine(services: services).undoLast(scope: .from(scope))
    }

    func undo(entryID: UUID) -> ToolResult {
        UndoEngine(services: services).undo(entryID: entryID)
    }

    func undo(group: String) -> ToolResult {
        UndoEngine(services: services).undo(group: group)
    }

    // MARK: Agenda & recall

    func agenda() -> ToolResult {
        let overdue = services.tasks.all().filter(\.isOverdue)
        let today = services.tasks.dueToday().filter { !$0.isOverdue }
        let blocked = services.tasks.all().filter(\.isBlocked)
        let week = services.tasks.dueWithin(days: 7)
            .filter { !$0.isOverdue && !Calendar.current.isDateInToday($0.dueDate ?? .distantFuture) }

        var lines: [String] = []
        if !overdue.isEmpty { lines.append("Overdue: " + overdue.map(\.title).joined(separator: "; ")) }
        if !today.isEmpty { lines.append("Due today: " + today.map(\.title).joined(separator: "; ")) }
        if !blocked.isEmpty { lines.append("Blocked: " + blocked.map(\.title).joined(separator: "; ")) }
        if !week.isEmpty { lines.append("This week: " + week.map(\.title).joined(separator: "; ")) }
        if lines.isEmpty { lines.append("Nothing pressing. The runway is clear.") }
        let count = overdue.count + today.count
        return ToolResult(summary: count == 0 ? "Clear runway today" : "\(count) item\(count == 1 ? "" : "s") need attention",
                          detail: lines.joined(separator: "\n"))
    }

    func recall(query: String) -> ToolResult {
        let q = query.lowercased()
        let messages = services.context.fetchAll(
            ChatMessage.self, sortBy: [.init(\.createdAt, order: .reverse)])
            .filter { $0.text.lowercased().contains(q) }
            .prefix(4)
        let doneTasks = services.tasks.all(includeDone: true)
            .filter { $0.isDone && $0.title.lowercased().contains(q) }
            .prefix(4)
        var lines: [String] = []
        lines.append(contentsOf: messages.map {
            "[\($0.createdAt.formatted(.dateTime.month().day()))] \($0.role == .user ? "You" : "Agent"): \($0.text.prefix(120))"
        })
        lines.append(contentsOf: doneTasks.map {
            "Completed “\($0.title)” on \($0.completedAt!.formatted(.dateTime.month().day()))"
        })
        guard !lines.isEmpty else {
            return ToolResult(summary: "Nothing in history", detail: "No history matching “\(query)”.")
        }
        return ToolResult(summary: "\(lines.count) memory match\(lines.count == 1 ? "" : "es")",
                          detail: lines.joined(separator: "\n"))
    }
}

extension TaskPriority {
    static func from(_ string: String?) -> TaskPriority {
        switch string?.lowercased() {
        case "low": .low
        case "high": .high
        case "urgent", "critical": .urgent
        default: .normal
        }
    }
}
