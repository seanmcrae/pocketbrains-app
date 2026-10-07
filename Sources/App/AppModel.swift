import SwiftUI
import SwiftData

enum SpaceKind: Int, CaseIterable, Identifiable {
    case today, projects, knowledge

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .today: return "Today"
        case .projects: return "Projects"
        case .knowledge: return "Knowledge"
        }
    }
    var icon: String {
        switch self {
        case .today: return "sun.horizon"
        case .projects: return "square.stack"
        case .knowledge: return "circle.hexagongrid"
        }
    }
    var hue: Color {
        switch self {
        case .today: return DomainHue.task
        case .projects: return lumen
        case .knowledge: return DomainHue.knowledge
        }
    }
}

/// App-wide state. One scalar — `zoom` — drives the entire thread↔spaces
/// transition, so the signature moment can never desynchronize.
@MainActor
@Observable
final class AppModel {
    // Core stack
    let services: DataServices
    let semanticIndex: SemanticIndex
    let toolbox: ToolBox
    let agent: AgentOrchestrator

    // Navigation
    /// 0 = thread is home, 1 = spaces. Scrubbed by gesture, settled by spring.
    var zoom: CGFloat = 0
    var space: SpaceKind = .today
    var focusedProject: Project?
    var focusedNote: Note?

    init(context: ModelContext) {
        let services = DataServices(context: context)
        let semanticIndex = SemanticIndex(context: context)
        let toolbox = ToolBox(services: services, semanticIndex: semanticIndex)
        self.services = services
        self.semanticIndex = semanticIndex
        self.toolbox = toolbox
        self.agent = AgentOrchestrator(context: context, toolbox: toolbox)
    }

    func bootstrap() {
        SeedData.seedIfNeeded(services)
        semanticIndex.reindexAll(notes: services.notes.all())
        toolbox.notesIndex.sync(notes: services.notes.all())
    }

    /// Open a cited source note from the thread.
    func openNote(id: UUID) {
        guard let note = services.notes.find(id: id) else { return }
        openSpaces(.knowledge)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450)) // let the zoom settle
            self.focusedNote = note
        }
    }

    func openSpaces(_ kind: SpaceKind? = nil) {
        if let kind { space = kind }
        withAnimation(Motion.glide) { zoom = 1 }
        Haptics.commit()
    }

    func returnToThread() {
        withAnimation(Motion.glide) { zoom = 0 }
        focusedProject = nil
        focusedNote = nil
        Haptics.touch()
    }

    // MARK: Settings actions

    func restoreSampleContent() {
        UserDefaults.standard.set(false, forKey: "pb.seeded")
        SeedData.seedIfNeeded(services)
        semanticIndex.reindexAll(notes: services.notes.all())
        toolbox.notesIndex.sync(notes: services.notes.all())
    }

    /// Deletes every entity and the conversation. The empty state that
    /// follows is the product's actual first-run truth.
    func eraseAllData() {
        agent.clearHistory()
        let context = services.context
        for link in context.fetchAll(KnowledgeLink.self) { context.delete(link) }
        for record in context.fetchAll(EmbeddingRecord.self) { context.delete(record) }
        for chunk in context.fetchAll(NoteChunk.self) { context.delete(chunk) }
        for entry in context.fetchAll(JournalEntry.self) { context.delete(entry) }
        for note in context.fetchAll(Note.self) { context.delete(note) }
        for task in context.fetchAll(TaskItem.self) { context.delete(task) }
        for milestone in context.fetchAll(Milestone.self) { context.delete(milestone) }
        for project in context.fetchAll(Project.self) { context.delete(project) }
        try? context.save()
        UserDefaults.standard.set(false, forKey: "pb.seeded")
    }

    var libraryCounts: (tasks: Int, projects: Int, notes: Int, links: Int) {
        (services.tasks.all(includeDone: true).count,
         services.projects.all().count,
         services.notes.all().count,
         services.graph.allLinks().count)
    }
}
