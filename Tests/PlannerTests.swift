import Foundation
import SwiftData
import Testing
@testable import PocketBrains

/// Multi-step agent: splitting, planning, argument passing between steps,
/// postconditions and safe failure.
@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct PlannerTests {
    /// See ToolBoxTests.makeBox — the container must outlive the test.
    private func makeBox() -> (ToolBox, ModelContainer) {
        let container = Store.makeContainer(inMemory: true)
        let services = DataServices(context: container.mainContext)
        return (ToolBox(services: services, semanticIndex: SemanticIndex(context: container.mainContext)),
                container)
    }

    static let launchRequest = "Create a project Launch, add 3 tasks for Friday and link it to brand voice"

    // MARK: Splitting

    @Test func splitsOnCommasAndAndBeforeCommandVerbs() {
        let clauses = CompoundPlanner.split(Self.launchRequest)
        #expect(clauses == ["Create a project Launch", "add 3 tasks for Friday", "link it to brand voice"])
    }

    @Test func keepsConjunctionsInsideATitle() {
        #expect(CompoundPlanner.split("Remind me to call mum and dad tomorrow").count == 1)
        #expect(CompoundPlanner.split("Note: buy milk, eggs and bread").count == 1)
        #expect(CompoundPlanner.plan("Remind me to call mum and dad tomorrow") == nil)
    }

    @Test func splitsOnThen() {
        let clauses = CompoundPlanner.split("remind me to pay rent then mark renew passport done")
        #expect(clauses.count == 2)
    }

    // MARK: Planning

    @Test func plansCompoundRequestWithReferences() throws {
        let plan = try #require(CompoundPlanner.plan(Self.launchRequest))
        #expect(plan.steps.map(\.tool) == ["createProject", "createTask", "createTask", "createTask", "linkItems"])
        #expect(plan.steps[0].arguments["name"] == "Launch")
        for step in plan.steps[1...3] {
            #expect(step.arguments["project"] == "$1")
            #expect(step.arguments["due"] == "friday")
        }
        #expect(plan.steps[1].arguments["title"] == "Launch task 1")
        #expect(plan.steps[4].arguments["from"] == "$1")
        #expect(plan.steps[4].arguments["to"] == "brand voice")
        #expect(plan.outline.contains("1. Create project “Launch”"))
    }

    @Test func expandsAnExplicitTaskList() throws {
        let plan = try #require(CompoundPlanner.plan("Add tasks: draft copy, book venue and send invites for Friday"))
        #expect(plan.steps.map { $0.arguments["title"] } == ["Draft copy", "Book venue", "Send invites"])
        #expect(plan.steps.allSatisfy { $0.arguments["due"] == "friday" })
    }

    @Test func referenceResolution() {
        let outputs: [[String: String]] = [["ref": "id:A", "title": "Launch"], [:], ["ref": "id:C"]]
        let ok = PlanReference.resolve(["project": "$1", "name": "$1.title", "x": "plain", "y": "$last"],
                                       outputs: outputs)
        #expect(ok.resolved == ["project": "id:A", "name": "Launch", "x": "plain", "y": "id:C"])
        let missing = PlanReference.resolve(["project": "$2"], outputs: outputs)
        #expect(missing.resolved == nil)
        #expect(missing.unresolved == "$2")
    }

    // MARK: Execution

    @Test func executesPlanPassingCreatedIDsBetweenSteps() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createNote(title: "Brand voice", body: "Confident, never loud.")
        // A decoy whose name also contains "Launch": fuzzy matching would pick
        // it (newest first), exact references must not.
        _ = box.createProject(name: "Launch party")

        let turn = IntentFallbackBackend.routeTurn(Self.launchRequest, toolbox: box)
        let outcome = try #require(turn.plan)
        #expect(outcome.succeeded)
        #expect(turn.tools == ["createProject", "createTask", "createTask", "createTask", "linkItems"])

        let launch = try #require(box.services.projects.all().first { $0.name == "Launch" })
        #expect(launch.tasks?.count == 3)
        #expect(box.services.projects.all().first { $0.name == "Launch party" }?.tasks?.isEmpty ?? true)
        for task in launch.tasks ?? [] {
            #expect(task.dueDate.map { Calendar.current.component(.weekday, from: $0) } == 6)
        }
        let links = box.services.graph.links(touching: launch.id)
        #expect(links.contains { $0.toKind == .note && $0.fromID == launch.id })

        // Thread events: plan card first, step cards, final plan card in place.
        guard case .toolFinished(let first) = outcome.events.first,
              case .toolFinished(let last) = outcome.events.last else {
            Issue.record("plan card events missing"); return
        }
        #expect(first.toolName == "plan" && last.toolName == "plan" && first.id == last.id)
        #expect(last.summary.contains("5/5"))
        #expect(last.undoGroup != nil)
    }

    @Test func stopsSafelyAtFirstFailedStep() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        let plan = AgentPlan(goal: "test", steps: [
            PlanStep(tool: "createTask", arguments: ["title": "First"]),
            PlanStep(tool: "completeTask", arguments: ["query": "does not exist"]),
            PlanStep(tool: "createTask", arguments: ["title": "Never"]),
        ])
        let outcome = PlanExecutor(toolbox: box).execute(plan)
        #expect(!outcome.succeeded)
        #expect(outcome.failedAt == 1)
        #expect(outcome.steps[2].status == .skipped)
        #expect(box.services.tasks.all().map(\.title) == ["First"])
        #expect(outcome.message.contains("stopped at step 2 of 3"))
        #expect(outcome.message.contains("undo that"))
    }

    @Test func unresolvableReferenceFailsTheStep() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        let plan = AgentPlan(goal: "test", steps: [
            PlanStep(tool: "agenda", arguments: [:]),
            PlanStep(tool: "createTask", arguments: ["title": "Filed", "project": "$1"]),
        ])
        let outcome = PlanExecutor(toolbox: box).execute(plan)
        #expect(outcome.failedAt == 1)
        #expect(box.services.tasks.all().isEmpty)
        #expect(outcome.message.contains("Nothing was changed"))
    }

    @Test func postconditionCatchesMissingProject() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        let plan = AgentPlan(goal: "test", steps: [
            PlanStep(tool: "createTask", arguments: ["title": "Orphan", "project": "Nonexistent"]),
            PlanStep(tool: "createTask", arguments: ["title": "Second"]),
        ])
        let outcome = PlanExecutor(toolbox: box).execute(plan)
        #expect(outcome.failedAt == 0)
        #expect(outcome.message.contains("Nonexistent"))
        // The step's own half-done write was reverted.
        #expect(box.services.tasks.all().isEmpty)
        #expect(outcome.message.contains("Nothing was changed"))
    }

    @Test func unknownToolFailsCleanly() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        let plan = AgentPlan(goal: "test", steps: [
            PlanStep(tool: "teleport", arguments: [:]),
            PlanStep(tool: "createTask", arguments: ["title": "Never"]),
        ])
        let outcome = PlanExecutor(toolbox: box).execute(plan)
        #expect(outcome.failedAt == 0)
        #expect(box.services.tasks.all().isEmpty)
        #expect(outcome.message.contains("Nothing was changed"))
    }

    @Test func multipleEnvelopesBecomeAPlan() throws {
        let text = #"<tool_call>{"name": "createProject", "arguments": {"name": "Garden"}}</tool_call> <tool_call>{"name": "createTask", "arguments": {"title": "Buy seeds", "project": "$1"}}</tool_call>"#
        #expect(ToolCallParser.parseAll(text).count == 2)
        let plan = try #require(ToolCallParser.plan(from: text, goal: "garden"))
        #expect(plan.steps[1].arguments["project"] == "$1")
        #expect(ToolCallParser.plan(from: #"<tool_call>{"name": "agenda"}</tool_call>"#, goal: "x") == nil)
    }
}

/// The action journal and undo: single actions, whole plans, atomicity.
@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct UndoTests {
    private func makeBox() -> (ToolBox, ModelContainer) {
        let container = Store.makeContainer(inMemory: true)
        let services = DataServices(context: container.mainContext)
        return (ToolBox(services: services, semanticIndex: SemanticIndex(context: container.mainContext)),
                container)
    }

    @Test func undoesASingleCreate() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        let created = box.createTask(title: "Water plants")
        #expect(created.journalID != nil)
        let undone = box.undo(scope: "step")
        #expect(undone.succeeded)
        #expect(box.services.tasks.all(includeDone: true).isEmpty)
        #expect(!box.undo().succeeded) // nothing left
    }

    @Test func undoRestoresAnUpdate() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createTask(title: "Send the invoice", due: "tomorrow", priority: "low")
        _ = box.updateTask(query: "invoice", due: "in 5 days", priority: "urgent")
        _ = box.undo(scope: "step")
        let task = try #require(box.services.tasks.all().first)
        #expect(task.priority == .low)
        #expect(task.dueDate.map { Calendar.current.isDateInTomorrow($0) } == true)
    }

    @Test func undoReopensACompletedTask() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createTask(title: "Renew passport")
        _ = box.completeTask(query: "passport")
        #expect(box.services.tasks.all().isEmpty)
        _ = box.undo(scope: "step")
        #expect(box.services.tasks.all().count == 1)
    }

    @Test func undoRestoresAppendedNote() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createNote(title: "Ideas", body: "First idea.")
        _ = box.appendNote(query: "ideas", text: "Second idea.")
        _ = box.undo(scope: "step")
        let note = try #require(box.services.notes.all().first)
        #expect(note.body == "First idea.")
    }

    @Test func undoRevertsAWholePlanAtomically() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createNote(title: "Brand voice", body: "Confident, never loud.")
        let turn = IntentFallbackBackend.routeTurn(PlannerTests.launchRequest, toolbox: box)
        #expect(turn.plan?.succeeded == true)
        #expect(box.services.projects.all().count == 1)

        let undo = IntentFallbackBackend.routeIntent("undo that", toolbox: box)
        #expect(undo.tool == "undo")
        #expect(undo.result?.succeeded == true)
        #expect(undo.result?.outputs["count"] == "5")
        #expect(box.services.projects.all().isEmpty)
        #expect(box.services.tasks.all(includeDone: true).isEmpty)
        #expect(box.services.graph.allLinks().isEmpty)
        // The note that predates the plan is untouched.
        #expect(box.services.notes.all().count == 1)
    }

    @Test func planCardUndoRevertsItsGroup() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        let turn = IntentFallbackBackend.routeTurn("Add tasks: draft copy, book venue and send invites", toolbox: box)
        let group = try #require(turn.plan?.group)
        _ = box.createTask(title: "Unrelated later task")
        let result = box.undo(group: group)
        #expect(result.succeeded)
        #expect(box.services.tasks.all().map(\.title) == ["Unrelated later task"])
    }

    @Test func groupUndoIsAllOrNothing() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        box.turnGroupID = "turn-1"
        _ = box.createTask(title: "Keep me")
        _ = box.createTask(title: "Edit me")
        _ = box.updateTask(query: "edit me", priority: "urgent")
        box.turnGroupID = ""
        // The updated task disappears behind the journal's back, so its
        // restore can't apply: nothing in the group may change.
        let edited = try #require(box.services.tasks.find(matching: "edit me"))
        box.services.tasks.delete(edited)

        let result = box.undo(group: "turn-1")
        #expect(!result.succeeded)
        #expect(result.detail.contains("Nothing was changed"))
        #expect(box.services.tasks.find(matching: "keep me") != nil)
    }
}
