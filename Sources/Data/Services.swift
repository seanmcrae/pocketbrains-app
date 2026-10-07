import Foundation
import SwiftData

/// The single write path. Agent tools AND structured views both call these,
/// so every mutation is visible everywhere instantly.
@MainActor
struct DataServices {
    let context: ModelContext
    let tasks: TaskService
    let projects: ProjectService
    let notes: NoteService
    let graph: GraphService
    let journal: JournalService

    init(context: ModelContext) {
        self.context = context
        self.tasks = TaskService(context: context)
        self.projects = ProjectService(context: context)
        self.notes = NoteService(context: context)
        self.graph = GraphService(context: context)
        self.journal = JournalService(context: context)
    }
}

// MARK: - Tasks

@MainActor
struct TaskService {
    let context: ModelContext

    @discardableResult
    func create(title: String, details: String = "", due: Date? = nil,
                priority: TaskPriority = .normal, project: Project? = nil) -> TaskItem {
        let task = TaskItem(title: title, details: details, dueDate: due,
                            priority: priority, project: project)
        context.insert(task)
        try? context.save()
        NotificationPlanner.sync(tasks: all())
        WidgetPublisher.publish(services: DataServices(context: context))
        return task
    }

    /// Marks the task done. A recurring task spawns its next occurrence
    /// (same title, details, priority and project), and the repeat rule moves
    /// to it. Returns the spawned task, if any.
    @discardableResult
    func complete(_ task: TaskItem) -> TaskItem? {
        task.completedAt = .now
        var spawned: TaskItem?
        if let ruleRow = recurrenceRow(for: task.id), let rule = ruleRow.rule {
            let next = TaskItem(title: task.title, details: task.details,
                                dueDate: rule.nextOccurrence(afterCompleting: task.dueDate),
                                priority: task.priority, project: task.project)
            context.insert(next)
            ruleRow.taskID = next.id
            spawned = next
        }
        try? context.save()
        NotificationPlanner.sync(tasks: all())
        WidgetPublisher.publish(services: DataServices(context: context))
        return spawned
    }

    // MARK: Recurrence

    func recurrenceRow(for taskID: UUID) -> RecurrenceRule? {
        context.fetchAll(RecurrenceRule.self).first { $0.taskID == taskID }
    }

    func recurrence(of task: TaskItem) -> Recurrence? {
        recurrenceRow(for: task.id)?.rule
    }

    /// Set (or with nil, clear) a task's repeat rule.
    func setRecurrence(_ task: TaskItem, _ rule: Recurrence?) {
        if let row = recurrenceRow(for: task.id) {
            if let rule { row.ruleRaw = rule.raw } else { context.delete(row) }
        } else if let rule {
            context.insert(RecurrenceRule(taskID: task.id, rule: rule))
        }
        try? context.save()
    }

    /// Move a repeat rule from one task to another (undo of a completion).
    func moveRecurrence(from source: UUID, to target: UUID) {
        guard let row = recurrenceRow(for: source) else { return }
        row.taskID = target
        try? context.save()
    }

    func reopen(_ task: TaskItem) {
        task.completedAt = nil
        try? context.save()
        NotificationPlanner.sync(tasks: all())
        WidgetPublisher.publish(services: DataServices(context: context))
    }

    func update(_ task: TaskItem, title: String? = nil, details: String? = nil,
                due: Date?? = nil, priority: TaskPriority? = nil, project: Project?? = nil) {
        if let title { task.title = title }
        if let details { task.details = details }
        if let due { task.dueDate = due }
        if let priority { task.priority = priority }
        if let project { task.project = project }
        try? context.save()
        NotificationPlanner.sync(tasks: all())
        WidgetPublisher.publish(services: DataServices(context: context))
    }

    func delete(_ task: TaskItem) {
        if let row = recurrenceRow(for: task.id) { context.delete(row) }
        context.delete(task)
        try? context.save()
        NotificationPlanner.sync(tasks: all())
        WidgetPublisher.publish(services: DataServices(context: context))
    }

    func addDependency(_ task: TaskItem, blockedBy blocker: TaskItem) {
        guard task.id != blocker.id, !task.blockedByIDs.contains(blocker.id) else { return }
        task.blockedByIDs.append(blocker.id)
        try? context.save()
    }

    func all(includeDone: Bool = false) -> [TaskItem] {
        let items = context.fetchAll(TaskItem.self, sortBy: [.init(\.createdAt, order: .reverse)])
        return includeDone ? items : items.filter { !$0.isDone }
    }

    func find(matching query: String) -> TaskItem? {
        if let id = EntityRef.id(from: query) { return find(id: id) }
        let q = query.lowercased()
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let candidates = all(includeDone: true)
        if let exact = candidates.first(where: { $0.title.lowercased().contains(q) || q.contains($0.title.lowercased()) }) {
            return exact
        }
        return FuzzyMatch.best(query, in: candidates.filter { !$0.isDone }, title: \.title)
            ?? FuzzyMatch.best(query, in: candidates, title: \.title)
    }

    func find(id: UUID) -> TaskItem? {
        context.fetchAll(TaskItem.self).first { $0.id == id }
    }

    /// Put a task's fields back to a snapshot (undo of an update).
    func restore(_ task: TaskItem, to snapshot: TaskSnapshot, project: Project?) {
        task.title = snapshot.title
        task.details = snapshot.details
        task.dueDate = snapshot.dueDate
        task.priorityRaw = snapshot.priorityRaw
        task.project = project
        task.completedAt = snapshot.completedAt
        try? context.save()
        NotificationPlanner.sync(tasks: all())
        WidgetPublisher.publish(services: DataServices(context: context))
    }

    func dueToday() -> [TaskItem] {
        let cal = Calendar.current
        return all().filter { $0.dueDate.map { cal.isDateInToday($0) || $0 < .now } ?? false }
    }

    func dueWithin(days: Int) -> [TaskItem] {
        guard let horizon = Calendar.current.date(byAdding: .day, value: days, to: .now)
        else { return [] }
        return all().filter { $0.dueDate.map { $0 <= horizon } ?? false }
    }
}

// MARK: - Projects

@MainActor
struct ProjectService {
    let context: ModelContext

    @discardableResult
    func create(name: String, summary: String = "") -> Project {
        // Round-robin hue assignment, skipping the most recent project's hue.
        let existing = all()
        let used = existing.first.map(\.hue)
        var hue = ProjectHue.allCases[existing.count % ProjectHue.allCases.count]
        if hue == used { hue = ProjectHue.allCases[(existing.count + 1) % ProjectHue.allCases.count] }
        let project = Project(name: name, summary: summary, hue: hue)
        context.insert(project)
        try? context.save()
        return project
    }

    func all() -> [Project] {
        context.fetchAll(Project.self, sortBy: [.init(\.createdAt, order: .reverse)])
    }

    func find(matching query: String) -> Project? {
        if let id = EntityRef.id(from: query) { return find(id: id) }
        let q = query.lowercased()
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let projects = all()
        if let exact = projects.first(where: { $0.name.lowercased().contains(q) || q.contains($0.name.lowercased()) }) {
            return exact
        }
        return FuzzyMatch.best(query, in: projects, title: \.name)
    }

    @discardableResult
    func addMilestone(to project: Project, title: String, target: Date? = nil) -> Milestone {
        let m = Milestone(title: title, targetDate: target, project: project)
        context.insert(m)
        try? context.save()
        return m
    }

    func find(id: UUID) -> Project? {
        context.fetchAll(Project.self).first { $0.id == id }
    }

    func milestone(id: UUID) -> Milestone? {
        context.fetchAll(Milestone.self).first { $0.id == id }
    }

    /// Milestones for a project, soonest target first; undated last.
    func milestones(of project: Project) -> [Milestone] {
        (project.milestones ?? []).sorted {
            ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture)
        }
    }

    func deleteMilestone(_ milestone: Milestone) {
        context.delete(milestone)
        try? context.save()
    }

    /// Deletes the project; its tasks and notes are kept and simply unfiled.
    func delete(_ project: Project) {
        for task in project.tasks ?? [] { task.project = nil }
        for milestone in project.milestones ?? [] { context.delete(milestone) }
        for note in context.fetchAll(Note.self) where note.project?.id == project.id {
            note.project = nil
        }
        context.delete(project)
        try? context.save()
    }

    func setStatus(_ project: Project, _ status: ProjectStatus) {
        project.status = status
        try? context.save()
    }

    /// Recent activity feed for a project — completions, new tasks, notes.
    func recentActivity(for project: Project, limit: Int = 5) -> [String] {
        var events: [(Date, String)] = []
        for t in project.tasks ?? [] {
            if let done = t.completedAt { events.append((done, "Completed “\(t.title)”")) }
            else { events.append((t.createdAt, "Added “\(t.title)”")) }
        }
        for m in project.milestones ?? [] where m.isReached {
            events.append((m.reachedAt!, "Milestone reached: \(m.title)"))
        }
        return events.sorted { $0.0 > $1.0 }.prefix(limit).map(\.1)
    }
}

// MARK: - Notes

@MainActor
struct NoteService {
    let context: ModelContext

    @discardableResult
    func create(title: String, body: String, tags: [String] = [], project: Project? = nil) -> Note {
        let note = Note(title: title, body: body, tags: tags, project: project)
        context.insert(note)
        try? context.save()
        return note
    }

    func append(_ note: Note, text: String) {
        note.body += (note.body.isEmpty ? "" : "\n\n") + text
        note.modifiedAt = .now
        try? context.save()
    }

    func all() -> [Note] {
        context.fetchAll(Note.self, sortBy: [.init(\.modifiedAt, order: .reverse)])
    }

    func find(matching query: String) -> Note? {
        if let id = EntityRef.id(from: query) { return find(id: id) }
        let q = query.lowercased()
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return all().first { $0.title.lowercased().contains(q) || q.contains($0.title.lowercased()) }
    }

    func find(id: UUID) -> Note? {
        context.fetchAll(Note.self).first { $0.id == id }
    }

    /// Replace a note's body (UI edits and undo of an append).
    func setBody(_ note: Note, _ body: String) {
        note.body = body
        note.modifiedAt = .now
        try? context.save()
    }

    func delete(_ note: Note) {
        context.delete(note)
        try? context.save()
    }

    /// Plain keyword search; semantic search lives in SemanticIndex and is
    /// merged by the searchNotes tool.
    func keywordSearch(_ query: String, limit: Int = 8) -> [Note] {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }
        return all()
            .map { note -> (Note, Int) in
                let hay = (note.title + " " + note.body + " " + note.tags.joined(separator: " ")).lowercased()
                return (note, terms.filter { hay.contains($0) }.count)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    func from(day: Date) -> [Note] {
        let cal = Calendar.current
        return all().filter { cal.isDate($0.createdAt, inSameDayAs: day) || cal.isDate($0.modifiedAt, inSameDayAs: day) }
    }
}

// MARK: - Knowledge graph

@MainActor
struct GraphService {
    let context: ModelContext

    @discardableResult
    func link(from: (EntityKind, UUID), to: (EntityKind, UUID), relation: String) -> KnowledgeLink {
        let edges = allLinks()
        if let existing = edges.first(where: {
            $0.fromID == from.1 && $0.toID == to.1 && $0.relation == relation
        }) { return existing }
        let link = KnowledgeLink(from: from, to: to, relation: relation)
        context.insert(link)
        try? context.save()
        return link
    }

    func link(id: UUID) -> KnowledgeLink? {
        allLinks().first { $0.id == id }
    }

    func delete(_ link: KnowledgeLink) {
        context.delete(link)
        try? context.save()
    }

    /// Remove every edge touching an entity (used when the entity goes away).
    func unlinkAll(touching id: UUID) {
        for link in links(touching: id) { context.delete(link) }
        try? context.save()
    }

    func allLinks() -> [KnowledgeLink] {
        context.fetchAll(KnowledgeLink.self)
    }

    func links(touching id: UUID) -> [KnowledgeLink] {
        allLinks().filter { $0.fromID == id || $0.toID == id }
    }

    /// Auto-weave: when a note mentions a project or task by name, the link
    /// creates itself. Knowledge compounds without ceremony.
    @discardableResult
    func autoWeave(note: Note, projects: [Project], tasks: [TaskItem]) -> [String] {
        let hay = (note.title + " " + note.body).lowercased()
        var woven: [String] = []
        for project in projects
        where project.id != note.project?.id
            && project.name.count > 3
            && hay.contains(project.name.lowercased()) {
            link(from: (.note, note.id), to: (.project, project.id), relation: "mentions")
            woven.append(project.name)
        }
        for task in tasks
        where task.title.count > 6 && hay.contains(task.title.lowercased()) {
            link(from: (.note, note.id), to: (.task, task.id), relation: "mentions")
            woven.append(task.title)
        }
        return woven
    }

    /// Display name resolution for any edge endpoint.
    func title(of kind: EntityKind, id: UUID) -> String? {
        switch kind {
        case .task: context.fetchAll(TaskItem.self).first { $0.id == id }?.title
        case .project: context.fetchAll(Project.self).first { $0.id == id }?.name
        case .note: context.fetchAll(Note.self).first { $0.id == id }?.title
        case .milestone: context.fetchAll(Milestone.self).first { $0.id == id }?.title
        }
    }
}


// MARK: - Action journal

@MainActor
struct JournalService {
    let context: ModelContext

    @discardableResult
    func record(tool: String, summary: String, group: String,
                inverse: [InverseStep]) -> JournalEntry {
        let entry = JournalEntry(groupID: group, toolName: tool, summary: summary, inverse: inverse)
        context.insert(entry)
        try? context.save()
        return entry
    }

    /// Newest first.
    func all() -> [JournalEntry] {
        context.fetchAll(JournalEntry.self, sortBy: [.init(\.createdAt, order: .reverse)])
    }

    func entry(id: UUID) -> JournalEntry? {
        all().first { $0.id == id }
    }

    /// The most recent action that has not been undone yet.
    func lastUndoable() -> JournalEntry? {
        all().first { !$0.isUndone }
    }

    /// Live (not yet undone) entries of a group, newest first.
    func pending(inGroup group: String) -> [JournalEntry] {
        all().filter { $0.groupID == group && !$0.isUndone }
    }

    func markUndone(_ entries: [JournalEntry]) {
        let now = Date.now
        for entry in entries { entry.undoneAt = now }
        try? context.save()
    }
}


// MARK: - Fuzzy title matching

/// Token-overlap fallback for "the launch copy" → "Write launch copy" when
/// no title contains the query verbatim. Content words are stemmed and
/// stopwords dropped; a candidate must cover every query word (or, for
/// queries of 3+ words, all but one) to qualify, so near-misses don't
/// silently act on the wrong task.
enum FuzzyMatch {
    static let filler: Set<String> = ["task", "todo", "item", "thing", "project", "list", "one"]

    static func words(_ text: String) -> Set<String> {
        Set(TextTokens.tokenize(text).filter { !filler.contains($0) })
    }

    static func best<T>(_ query: String, in items: [T], title: KeyPath<T, String>) -> T? {
        let q = words(query)
        guard !q.isEmpty else { return nil }
        let needed = q.count >= 3 ? q.count - 1 : q.count
        var bestItem: T?
        var bestScore = 0.0
        for item in items {
            let t = words(item[keyPath: title])
            let hits = q.intersection(t).count
            guard hits >= needed, !t.isEmpty else { continue }
            let score = Double(hits) / Double(q.union(t).count)
            if score > bestScore { bestScore = score; bestItem = item }
        }
        return bestItem
    }
}
