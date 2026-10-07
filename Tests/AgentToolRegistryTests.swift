import Foundation
import SwiftData
import Testing
@testable import PocketBrains

/// The backend-neutral tool registry: its surface, its string-argument
/// handling, and the prompted path (envelope -> registry -> ToolBox) that the
/// MLX backend uses.
@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct AgentToolRegistryTests {
    /// See ToolBoxTests.makeBox: the container must outlive the test.
    private func makeBox() -> (ToolBox, ModelContainer) {
        let container = Store.makeContainer(inMemory: true)
        let services = DataServices(context: container.mainContext)
        return (ToolBox(services: services, semanticIndex: SemanticIndex(context: container.mainContext)),
                container)
    }

    private func spec(_ name: String, in box: ToolBox) throws -> AgentToolSpec {
        try #require(AgentToolRegistry.all(toolbox: box).first { $0.name == name })
    }

    @Test func exposesTheDocumentedTools() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        let names = AgentToolRegistry.all(toolbox: box).map(\.name)
        #expect(names.count == 15)
        #expect(Set(names).count == names.count)
        #expect(Set(names) == [
            "createTask", "completeTask", "updateTask", "queryTasks",
            "createProject", "projectStatus", "addMilestone",
            "createNote", "searchNotes", "askNotes", "notesFrom", "linkItems",
            "agenda", "recall", "undo",
        ])
    }

    @Test func everyToolIsDescribedAndParametersAreUnique() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        for spec in AgentToolRegistry.all(toolbox: box) {
            #expect(!spec.description.isEmpty, "\(spec.name) has no description")
            let params = spec.parameters.map(\.name)
            #expect(Set(params).count == params.count, "\(spec.name) repeats a parameter")
            #expect(spec.parameters.allSatisfy { !$0.description.isEmpty })
        }
        #expect(try spec("agenda", in: box).parameters.isEmpty)
    }

    @Test func createTaskParsesStringArguments() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createProject(name: "Q3 Planning")
        let result = try spec("createTask", in: box).run(
            ["title": "Draft budget", "due": "tomorrow", "priority": "critical", "project": "q3"])
        #expect(result.succeeded)
        let task = try #require(box.services.tasks.all().first)
        #expect(task.title == "Draft budget")
        #expect(task.priority == .urgent) // "critical" is an accepted synonym
        #expect(task.project?.name == "Q3 Planning")
        #expect(task.dueDate.map { Calendar.current.isDateInTomorrow($0) } == true)
    }

    @Test func missingOptionalArgumentsFallBackToDefaults() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        let result = try spec("createTask", in: box).run([:])
        #expect(result.succeeded)
        let task = try #require(box.services.tasks.all().first)
        #expect(task.title == "Untitled")
        #expect(task.priority == .normal)
        #expect(task.dueDate == nil)
    }

    @Test func unparseableDueDateLeavesTaskUndated() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = try spec("createTask", in: box).run(["title": "Someday", "due": "when pigs fly"])
        #expect(box.services.tasks.all().first?.dueDate == nil)
    }

    @Test func updateTaskReportsNoChangesHonestly() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createTask(title: "Write launch copy")
        let result = try spec("updateTask", in: box).run(["query": "launch copy"])
        #expect(result.succeeded)
        #expect(result.summary.contains("no changes"))
    }

    @Test func promptedToolCallRoutesThroughRegistry() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createTask(title: "Book flights for the offsite")
        let output = #"<tool_call>{"name": "completeTask", "arguments": {"query": "book flights"}}</tool_call>"#
        let call = try #require(ToolCallParser.parse(output))
        let result = try spec(call.name, in: box).run(call.arguments)
        #expect(result.succeeded)
        #expect(box.services.tasks.all(includeDone: true).first?.isDone == true)
    }
}
