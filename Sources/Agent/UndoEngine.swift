import Foundation

/// Reverts journaled actions. A group (one turn or one plan) is reverted
/// atomically: every inverse is validated first, and if any cannot apply
/// nothing is touched. Inverses run newest-first so later steps unwind
/// before the items they depended on disappear.
@MainActor
struct UndoEngine {
    enum Scope: String {
        /// Everything the most recent turn or plan did.
        case turn
        /// Only the single most recent action.
        case step

        static func from(_ text: String?) -> Scope {
            let lower = (text ?? "").lowercased()
            if lower.contains("step") || lower.contains("action") || lower.contains("single") { return .step }
            return .turn
        }
    }

    let services: DataServices

    func undoLast(scope: Scope) -> ToolResult {
        guard let last = services.journal.lastUndoable() else {
            return ToolResult(summary: "Nothing to undo",
                              detail: "There is nothing left to undo.", succeeded: false)
        }
        switch scope {
        case .step: return revert([last])
        case .turn: return revert(services.journal.pending(inGroup: last.groupID))
        }
    }

    func undo(entryID: UUID) -> ToolResult {
        guard let entry = services.journal.entry(id: entryID), !entry.isUndone else {
            return ToolResult(summary: "Already undone",
                              detail: "That action was already undone.", succeeded: false)
        }
        return revert([entry])
    }

    func undo(group: String) -> ToolResult {
        let entries = services.journal.pending(inGroup: group)
        guard !entries.isEmpty else {
            return ToolResult(summary: "Already undone",
                              detail: "Everything in that plan was already undone.", succeeded: false)
        }
        return revert(entries)
    }

    /// Reverts the given entries as one unit. Order is normalized to
    /// newest-first regardless of how they were passed.
    func revert(_ entries: [JournalEntry]) -> ToolResult {
        let ordered = entries.sorted { $0.createdAt > $1.createdAt }
        guard !ordered.isEmpty else {
            return ToolResult(summary: "Nothing to undo",
                              detail: "There is nothing left to undo.", succeeded: false)
        }
        // 1. Validate everything before touching anything.
        for entry in ordered {
            for step in entry.inverse {
                if let problem = validate(step) {
                    return ToolResult(summary: "Couldn't undo “\(entry.summary)”",
                                      detail: "Nothing was changed: \(problem)", succeeded: false)
                }
            }
        }
        // 2. Apply.
        for entry in ordered {
            for step in entry.inverse { apply(step) }
        }
        services.journal.markUndone(ordered)
        let count = ordered.count
        let lines = ordered.map { "• \($0.summary)" }.joined(separator: "\n")
        return ToolResult(
            summary: count == 1 ? "Undid: \(ordered[0].summary)" : "Undid \(count) actions",
            detail: "Reverted \(count) action\(count == 1 ? "" : "s"):\n\(lines)",
            outputs: ["count": String(count)])
    }

    // MARK: - Steps

    /// nil when the step can apply. Deleting something already gone is fine.
    private func validate(_ step: InverseStep) -> String? {
        guard let id = step.id else { return "the action has no target recorded." }
        switch step.kind {
        case .reopenTask:
            return services.tasks.find(id: id) == nil ? "that task no longer exists." : nil
        case .restoreTask:
            if services.tasks.find(id: id) == nil { return "that task no longer exists." }
            return step.task == nil ? "the earlier version wasn't recorded." : nil
        case .restoreNoteBody:
            if services.notes.find(id: id) == nil { return "that note no longer exists." }
            return step.text == nil ? "the earlier text wasn't recorded." : nil
        case .deleteTask, .deleteProject, .deleteMilestone, .deleteNote, .deleteLink:
            return nil
        }
    }

    private func apply(_ step: InverseStep) {
        guard let id = step.id else { return }
        switch step.kind {
        case .deleteTask:
            if let task = services.tasks.find(id: id) {
                services.graph.unlinkAll(touching: id)
                services.tasks.delete(task)
            }
        case .reopenTask:
            if let task = services.tasks.find(id: id) { services.tasks.reopen(task) }
        case .restoreTask:
            if let task = services.tasks.find(id: id), let snapshot = step.task {
                let project = snapshot.projectID.flatMap { services.projects.find(id: $0) }
                services.tasks.restore(task, to: snapshot, project: project)
            }
        case .deleteProject:
            if let project = services.projects.find(id: id) {
                services.graph.unlinkAll(touching: id)
                services.projects.delete(project)
            }
        case .deleteMilestone:
            if let milestone = services.projects.milestone(id: id) {
                services.projects.deleteMilestone(milestone)
            }
        case .deleteNote:
            if let note = services.notes.find(id: id) {
                services.graph.unlinkAll(touching: id)
                services.notes.delete(note)
            }
        case .restoreNoteBody:
            if let note = services.notes.find(id: id), let text = step.text {
                services.notes.setBody(note, text)
            }
        case .deleteLink:
            if let link = services.graph.link(id: id) { services.graph.delete(link) }
        }
    }
}
