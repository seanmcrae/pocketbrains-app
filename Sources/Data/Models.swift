import Foundation
import SwiftData

// MARK: - Tasks

enum TaskPriority: Int, Codable, CaseIterable {
    case low = 0, normal = 1, high = 2, urgent = 3

    var bars: Int { max(0, rawValue) }
    var label: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        case .urgent: return "Urgent"
        }
    }
}

/// Named `TaskItem` (not `Task`) to avoid the Swift Concurrency type.
@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var createdAt: Date
    var dueDate: Date?
    var completedAt: Date?
    var priorityRaw: Int
    var project: Project?
    /// IDs of tasks that must finish before this one can start, packed as
    /// 16 bytes per UUID. A self-referential relationship crashes SwiftData
    /// at fetch, and a `[UUID]` attribute traps on insert (CI crash report,
    /// iOS 26 runtime) — raw Data is the storage that cannot betray us.
    /// Assigned in init (no macro default-value expression).
    var blockedByData: Data

    var blockedByIDs: [UUID] {
        get {
            stride(from: 0, to: blockedByData.count - 15, by: 16).compactMap { offset in
                let slice = blockedByData.subdata(in: offset..<(offset + 16))
                return slice.withUnsafeBytes { raw -> UUID? in
                    guard raw.count == 16 else { return nil }
                    return UUID(uuid: raw.load(as: uuid_t.self))
                }
            }
        }
        set {
            var packed = Data(capacity: newValue.count * 16)
            for id in newValue {
                withUnsafeBytes(of: id.uuid) { packed.append(contentsOf: $0) }
            }
            blockedByData = packed
        }
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }
    var isDone: Bool { completedAt != nil }
    /// Resolved blocker tasks (requires the model to be in a context).
    var blockers: [TaskItem] {
        guard let context = modelContext, !blockedByData.isEmpty else { return [] }
        let ids = blockedByIDs
        return context.fetchAll(TaskItem.self).filter { ids.contains($0.id) }
    }
    var isBlocked: Bool { blockers.contains { !$0.isDone } }
    var isOverdue: Bool {
        guard let dueDate, !isDone else { return false }
        return dueDate < Calendar.current.startOfDay(for: .now)
    }

    init(title: String, details: String = "", dueDate: Date? = nil,
         priority: TaskPriority = .normal, project: Project? = nil) {
        self.id = UUID()
        self.title = title
        self.details = details
        self.createdAt = .now
        self.dueDate = dueDate
        self.priorityRaw = priority.rawValue
        self.project = project
        self.blockedByData = Data()
    }
}

// MARK: - Projects

enum ProjectStatus: String, Codable, CaseIterable {
    case active, paused, done

    var label: String { rawValue.capitalized }
}

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var summary: String
    var statusRaw: String
    var hueRaw: Int
    var createdAt: Date
    /// Inverses are inferred from `TaskItem.project` / `Milestone.project` —
    /// explicit `@Relationship(inverse:)` declarations trapped at insert on
    /// the iOS 26 runtime (CI crash reports; Note, with an inferred inverse,
    /// always inserted cleanly). Inference is unambiguous for these pairs.
    var tasks: [TaskItem]?
    var milestones: [Milestone]?

    var status: ProjectStatus {
        get { ProjectStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
    var hue: ProjectHue {
        get { ProjectHue(rawValue: hueRaw) ?? .slate }
        set { hueRaw = newValue.rawValue }
    }
    var progress: Double {
        let all = tasks ?? []
        guard !all.isEmpty else { return 0 }
        return Double(all.filter(\.isDone).count) / Double(all.count)
    }
    var openTasks: [TaskItem] { (tasks ?? []).filter { !$0.isDone } }
    var blockers: [TaskItem] { openTasks.filter(\.isBlocked) }

    init(name: String, summary: String = "", hue: ProjectHue = .slate) {
        self.id = UUID()
        self.name = name
        self.summary = summary
        self.statusRaw = ProjectStatus.active.rawValue
        self.hueRaw = hue.rawValue
        self.createdAt = .now
    }
}

@Model
final class Milestone {
    @Attribute(.unique) var id: UUID
    var title: String
    var targetDate: Date?
    var reachedAt: Date?
    var project: Project?

    var isReached: Bool { reachedAt != nil }

    init(title: String, targetDate: Date? = nil, project: Project? = nil) {
        self.id = UUID()
        self.title = title
        self.targetDate = targetDate
        self.project = project
    }
}

// MARK: - Notes & knowledge

@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var title: String
    var body: String
    var createdAt: Date
    var modifiedAt: Date
    /// Newline-joined — primitive-array attributes trap on insert (see
    /// TaskItem.blockedByData); tags never contain newlines.
    var tagsRaw: String
    var project: Project?

    var tags: [String] {
        get { tagsRaw.isEmpty ? [] : tagsRaw.components(separatedBy: "\n") }
        set {
            // Strip newlines before joining — a tag containing \n would split
            // into phantom tags on the next read. Also drop empty strings.
            tagsRaw = newValue
                .map { $0.components(separatedBy: .newlines).joined() }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
    }

    init(title: String, body: String = "", tags: [String] = [], project: Project? = nil) {
        self.id = UUID()
        self.title = title
        self.body = body
        self.createdAt = .now
        self.modifiedAt = .now
        // Sanitize tags consistently with the computed-property setter.
        self.tagsRaw = tags
            .map { $0.components(separatedBy: .newlines).joined() }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        self.project = project
    }
}

/// What kind of entity an edge endpoint refers to.
enum EntityKind: String, Codable {
    case task, project, note, milestone
}

/// A typed edge in the knowledge graph. Endpoints are (kind, id) pairs so
/// any entity can link to any other.
@Model
final class KnowledgeLink {
    @Attribute(.unique) var id: UUID
    var fromKindRaw: String
    var fromID: UUID
    var toKindRaw: String
    var toID: UUID
    /// e.g. "references", "blocks", "inspired-by", "belongs-to"
    var relation: String
    var createdAt: Date

    var fromKind: EntityKind { EntityKind(rawValue: fromKindRaw) ?? .note }
    var toKind: EntityKind { EntityKind(rawValue: toKindRaw) ?? .note }

    init(from: (EntityKind, UUID), to: (EntityKind, UUID), relation: String) {
        self.id = UUID()
        self.fromKindRaw = from.0.rawValue
        self.fromID = from.1
        self.toKindRaw = to.0.rawValue
        self.toID = to.1
        self.relation = relation
        self.createdAt = .now
    }
}

// MARK: - Chat transcript

enum ChatRole: String, Codable {
    case user, agent
}

/// One persisted turn in the thread. Tool activity is stored as encoded
/// `ToolEventRecord`s so history replays with its cards intact.
@Model
final class ChatMessage {
    @Attribute(.unique) var id: UUID
    var roleRaw: String
    var text: String
    var createdAt: Date
    var toolEventsData: Data?

    var role: ChatRole { ChatRole(rawValue: roleRaw) ?? .agent }
    var toolEvents: [ToolEventRecord] {
        get {
            guard let toolEventsData else { return [] }
            return (try? JSONDecoder().decode([ToolEventRecord].self, from: toolEventsData)) ?? []
        }
        set { toolEventsData = try? JSONEncoder().encode(newValue) }
    }

    init(role: ChatRole, text: String) {
        self.id = UUID()
        self.roleRaw = role.rawValue
        self.text = text
        self.createdAt = .now
    }
}

struct ToolEventRecord: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var toolName: String
    var summary: String
    var detail: String
    var succeeded: Bool
    /// Journal entry this action can be undone through (mutating tools only).
    var journalID: UUID? = nil
    /// Undo the whole group (a plan card undoes every step it ran).
    var undoGroup: String? = nil
    /// "2/4" when the call ran as a step of a multi-step plan.
    var stepLabel: String? = nil
    /// Source notes behind a cited answer ([n] → note).
    var citations: [Citation]? = nil
}

// MARK: - Semantic index cache

@Model
final class EmbeddingRecord {
    @Attribute(.unique) var entityID: UUID
    var kindRaw: String
    /// Packed [Float] vector.
    var vector: Data
    var contentHash: Int

    init(entityID: UUID, kind: EntityKind, vector: [Float], contentHash: Int) {
        self.entityID = entityID
        self.kindRaw = kind.rawValue
        self.vector = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        self.contentHash = contentHash
    }

    var floats: [Float] {
        vector.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
