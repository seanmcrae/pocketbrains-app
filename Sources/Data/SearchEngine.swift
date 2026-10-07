import Foundation

/// One query across everything you've ever put in: keyword over tasks and
/// projects, keyword + semantic over notes.
@MainActor
enum SearchEngine {
    struct Results {
        var tasks: [TaskItem] = []
        var projects: [Project] = []
        var notes: [Note] = []

        var isEmpty: Bool { tasks.isEmpty && projects.isEmpty && notes.isEmpty }
    }

    static func search(_ query: String, services: DataServices,
                       index: SemanticIndex) -> Results {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 2 else { return Results() }

        var results = Results()
        results.tasks = Array(
            services.tasks.all(includeDone: true)
                .filter { $0.title.lowercased().contains(q) || $0.details.lowercased().contains(q) }
                .prefix(6))
        results.projects = Array(
            services.projects.all()
                .filter { $0.name.lowercased().contains(q) || $0.summary.lowercased().contains(q) }
                .prefix(4))

        // Notes: keyword first (exact wins), semantic fills the tail.
        var seen = Set<UUID>()
        let keyword = services.notes.keywordSearch(q, limit: 6)
        let semantic = index.search(query, limit: 4)
        results.notes = (keyword + semantic).filter { seen.insert($0.id).inserted }
        return results
    }
}
