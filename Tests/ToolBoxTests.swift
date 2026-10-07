import Foundation
import SwiftData
import Testing
@testable import PocketBrains

@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct ToolBoxTests {
    /// ModelContext does not retain its ModelContainer — if the container
    /// deallocates, every later context operation traps (the entire CI crash
    /// saga). Tests must keep the container alive for their full lifetime.
    private func makeBox() -> (ToolBox, ModelContainer) {
        let container = Store.makeContainer(inMemory: true)
        let services = DataServices(context: container.mainContext)
        let index = SemanticIndex(context: container.mainContext)
        return (ToolBox(services: services, semanticIndex: index), container)
    }

    @Test func createTaskWithDueDateAndPriority() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        let result = box.createTask(title: "Send the invoice", due: "tomorrow", priority: "urgent")
        #expect(result.succeeded)
        let task = try #require(box.services.tasks.all().first)
        #expect(task.title == "Send the invoice")
        #expect(task.priority == .urgent)
        #expect(task.dueDate.map { Calendar.current.isDateInTomorrow($0) } == true)
    }

    @Test func completeTaskByFuzzyTitle() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createTask(title: "Book flights for the offsite")
        let result = box.completeTask(query: "book flights")
        #expect(result.succeeded)
        #expect(box.services.tasks.all(includeDone: true).first?.isDone == true)
    }

    @Test func completeUnknownTaskFails() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        let result = box.completeTask(query: "does not exist")
        #expect(!result.succeeded)
    }

    @Test func projectStatusReportsBlockers() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createProject(name: "Website Redesign")
        let project = box.services.projects.find(matching: "website")!
        let copy = box.services.tasks.create(title: "Write copy", project: project)
        let build = box.services.tasks.create(title: "Build site", project: project)
        box.services.tasks.addDependency(build, blockedBy: copy)

        let status = box.projectStatus(name: "website redesign")
        #expect(status.succeeded)
        #expect(status.detail.contains("Build site"))
        #expect(status.detail.contains("Write copy"))
        #expect(!project.blockers.isEmpty)

        // Completing the blocker unblocks the dependent task.
        box.services.tasks.complete(copy)
        #expect(project.blockers.isEmpty)
    }

    @Test func tasksFileIntoProjectsByName() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createProject(name: "Q3 Planning")
        let result = box.createTask(title: "Draft budget", projectName: "q3")
        #expect(result.succeeded)
        #expect(box.services.tasks.all().first?.project?.name == "Q3 Planning")
    }

    @Test func linkItemsCreatesEdgeBetweenKinds() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createNote(title: "Brand voice", body: "Confident, never loud.")
        _ = box.createProject(name: "Website Redesign")
        let result = box.linkItems(from: "brand voice", to: "website", relation: "references")
        #expect(result.succeeded)
        let links = box.services.graph.allLinks()
        #expect(links.count == 1)
        #expect(links.first?.fromKind == .note)
        #expect(links.first?.toKind == .project)
    }

    @Test func agendaRanksOverdueFirst() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createTask(title: "Late thing", due: "yesterday")
        _ = box.createTask(title: "Today thing", due: "today")
        let agenda = box.agenda()
        #expect(agenda.detail.contains("Overdue: Late thing"))
        #expect(agenda.detail.contains("Today thing"))
    }

    @Test func emptyAgendaIsClearRunway() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        let agenda = box.agenda()
        #expect(agenda.summary.contains("Clear runway"))
    }

    @Test func autoWeaveLinksMentionedProjects() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createProject(name: "Website Redesign")
        let result = box.createNote(
            title: "Kickoff", body: "Notes from the website redesign kickoff.")
        #expect(result.succeeded)
        let links = box.services.graph.allLinks()
        #expect(links.contains { $0.relation == "mentions" })
    }

    @Test func dailyBriefComposesCountsAndFocus() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createTask(title: "Late thing", due: "yesterday", priority: "urgent")
        let brief = DailyBrief.compose(services: box.services)
        #expect(brief.overdue == 1)
        #expect(brief.focus?.contains("Late thing") == true)
        #expect(!brief.isQuiet)
    }

    @Test func unifiedSearchFindsAcrossKinds() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createTask(title: "Book flights for the offsite")
        _ = box.createProject(name: "Website Redesign")
        _ = box.createNote(title: "Brand voice", body: "Confident, never loud.")

        let byTask = SearchEngine.search("flights", services: box.services,
                                         index: box.semanticIndex)
        #expect(byTask.tasks.count == 1 && byTask.projects.isEmpty)

        let byProject = SearchEngine.search("redesign", services: box.services,
                                            index: box.semanticIndex)
        #expect(byProject.projects.count == 1)

        let byNote = SearchEngine.search("confident", services: box.services,
                                         index: box.semanticIndex)
        #expect(byNote.notes.count == 1)

        #expect(SearchEngine.search("x", services: box.services,
                                    index: box.semanticIndex).isEmpty)
    }

    @Test func keywordNoteSearchFindsContent() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createNote(title: "Kickoff meeting", body: "They proposed three design directions.")
        let result = box.searchNotes(query: "design directions")
        #expect(result.detail.contains("Kickoff meeting"))
    }
}
