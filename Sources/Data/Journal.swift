import Foundation
import SwiftData

// MARK: - Action journal

/// One mutation the agent performed, with everything needed to reverse it.
/// Entries that share a `groupID` were produced by the same turn or plan and
/// are undone together. Attribute types deliberately mirror ones the iOS 26
/// runtime is proven to insert cleanly (see AAStoreDiagnostics): String,
/// Date, Date?, Data and a unique UUID; no Bool, no primitive arrays.
@Model
final class JournalEntry {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    /// Turn or plan identifier; every entry has one.
    var groupID: String
    var toolName: String
    var summary: String
    /// JSON-encoded `[InverseStep]`, applied in order to revert the action.
    var inverseData: Data
    /// Set once the entry has been reverted.
    var undoneAt: Date?

    var isUndone: Bool { undoneAt != nil }

    var inverse: [InverseStep] {
        (try? JSONDecoder().decode([InverseStep].self, from: inverseData)) ?? []
    }

    init(groupID: String, toolName: String, summary: String, inverse: [InverseStep]) {
        self.id = UUID()
        self.createdAt = .now
        self.groupID = groupID
        self.toolName = toolName
        self.summary = summary
        self.inverseData = (try? JSONEncoder().encode(inverse)) ?? Data()
    }
}

/// Field values of a task before a mutation, so an update can be reversed.
struct TaskSnapshot: Codable, Equatable {
    var title: String
    var details: String
    var dueDate: Date?
    var priorityRaw: Int
    var projectID: UUID?
    var completedAt: Date?

    init(_ task: TaskItem) {
        title = task.title
        details = task.details
        dueDate = task.dueDate
        priorityRaw = task.priorityRaw
        projectID = task.project?.id
        completedAt = task.completedAt
    }
}

/// A single reversing operation. Kept as a flat struct (not an enum with
/// payloads) so the JSON stays readable in exports and stable across versions.
struct InverseStep: Codable, Equatable {
    enum Kind: String, Codable {
        case deleteTask        // undo a creation
        case reopenTask        // undo a completion
        case restoreTask       // undo an update (uses `task`)
        case deleteProject
        case deleteMilestone
        case deleteNote
        case restoreNoteBody   // undo an append/edit (uses `text`)
        case deleteLink
        case removeReminder    // delete an exported Reminders item (`text` = its identifier)
        case setRecurrence     // put a repeat rule back (`text` = Recurrence.raw)
        case clearRecurrence   // remove a repeat rule the action added
        case moveRecurrence    // move the rule back to `id` from the task in `text`
    }

    var kind: Kind
    var id: UUID?
    var task: TaskSnapshot? = nil
    var text: String? = nil
}

// MARK: - Entity references

/// Exact references passed between plan steps: `id:<uuid>`. Every service
/// `find(matching:)` honours them before any fuzzy title matching, so a step
/// that created "Launch" can hand exactly that project to the next step even
/// when "Launch v1" also exists.
enum EntityRef {
    static let prefix = "id:"

    static func make(_ id: UUID) -> String { prefix + id.uuidString }

    static func id(from text: String) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(trimmed.dropFirst(prefix.count)))
    }

    static func isRef(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix(prefix)
    }
}
