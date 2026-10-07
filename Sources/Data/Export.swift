import Foundation

/// Full-fidelity JSON export — the user's data belongs to the user.
/// Plain Codable DTOs so the format is stable and readable anywhere.
enum Exporter {
    struct Payload: Codable {
        var exportedAt: Date
        var app = "PocketBrains"
        var version = 1
        var tasks: [TaskDTO]
        var projects: [ProjectDTO]
        var notes: [NoteDTO]
        var links: [LinkDTO]
    }

    struct TaskDTO: Codable {
        var id: UUID, title: String, details: String
        var createdAt: Date, dueDate: Date?, completedAt: Date?
        var priority: String, project: String?, blockedBy: [UUID]
    }

    struct ProjectDTO: Codable {
        var id: UUID, name: String, summary: String, status: String
        var createdAt: Date
        var milestones: [MilestoneDTO]
    }

    struct MilestoneDTO: Codable {
        var title: String, targetDate: Date?, reachedAt: Date?
    }

    struct NoteDTO: Codable {
        var id: UUID, title: String, body: String, tags: [String]
        var createdAt: Date, modifiedAt: Date, project: String?
    }

    struct LinkDTO: Codable {
        var fromKind: String, fromID: UUID, toKind: String, toID: UUID, relation: String
    }

    @MainActor
    static func makeFile(services: DataServices) -> URL? {
        let payload = Payload(
            exportedAt: .now,
            tasks: services.tasks.all(includeDone: true).map {
                TaskDTO(id: $0.id, title: $0.title, details: $0.details,
                        createdAt: $0.createdAt, dueDate: $0.dueDate,
                        completedAt: $0.completedAt, priority: $0.priority.label,
                        project: $0.project?.name, blockedBy: $0.blockedByIDs)
            },
            projects: services.projects.all().map { project in
                ProjectDTO(id: project.id, name: project.name, summary: project.summary,
                           status: project.status.rawValue, createdAt: project.createdAt,
                           milestones: (project.milestones ?? []).map {
                               MilestoneDTO(title: $0.title, targetDate: $0.targetDate,
                                            reachedAt: $0.reachedAt)
                           })
            },
            notes: services.notes.all().map {
                NoteDTO(id: $0.id, title: $0.title, body: $0.body, tags: $0.tags,
                        createdAt: $0.createdAt, modifiedAt: $0.modifiedAt,
                        project: $0.project?.name)
            },
            links: services.graph.allLinks().map {
                LinkDTO(fromKind: $0.fromKindRaw, fromID: $0.fromID,
                        toKind: $0.toKindRaw, toID: $0.toID, relation: $0.relation)
            })

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return nil }
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PocketBrains-\(stamp).json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }
}
