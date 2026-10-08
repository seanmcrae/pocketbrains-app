#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// Primary brain: Apple's on-device ~3B foundation model (iOS 26).
/// The app's ToolBox is bridged into native `Tool` conformances with
/// @Generable arguments so the model gets real guided generation.
@MainActor
final class FoundationModelBackend: ModelBackend {
    let displayName = "Apple Intelligence · on-device"

    private let toolbox: ToolBox
    private let sink = ToolEventSink()
    private var session: LanguageModelSession

    init?(toolbox: ToolBox) {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        self.toolbox = toolbox
        self.session = Self.makeSession(toolbox: toolbox, sink: sink)
    }

    private static func makeSession(toolbox: ToolBox, sink: ToolEventSink) -> LanguageModelSession {
        LanguageModelSession(
            tools: Self.tools(toolbox: toolbox, sink: sink),
            instructions: AgentVoice.instructions()
        )
    }

    func resetConversation() {
        session = Self.makeSession(toolbox: toolbox, sink: sink)
    }

    func reply(to prompt: String) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            sink.emit = { continuation.yield($0) }
            sink.resetStepCount()
            let task = Task { @MainActor in
                do {
                    // Compound requests: plan first (guided generation), then
                    // execute deterministically with argument passing,
                    // postconditions and atomic undo. Simple requests use the
                    // model's native multi-turn tool calling.
                    if CompoundPlanner.split(prompt).count > 1,
                       let outcome = await self.runPlanned(prompt, continuation: continuation) {
                        let text = await self.narrate(outcome, prompt: prompt, continuation: continuation)
                        continuation.yield(.done(finalText: text))
                        continuation.finish()
                        return
                    }
                    var lastText = ""
                    // Optional per-request tool trimming (Settings): a fresh
                    // session that sees only the tools relevant to this prompt.
                    let active = ToolTrimming.isEnabled ? self.trimmedSession(for: prompt) : session
                    let stream = active.streamResponse(to: prompt)
                    for try await partial in stream {
                        lastText = partial.content
                        continuation.yield(.text(lastText))
                    }
                    continuation.yield(.done(finalText: lastText))
                    continuation.finish()
                } catch {
                    // Context overflow → start a fresh session and surface
                    // a graceful failure; the orchestrator will retry.
                    self.resetConversation()
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Tool trimming

    /// A one-request session offering only `ToolSelector`'s pick (about 8
    /// of 22 to 24 tools, core tools always included). Trades multi-turn
    /// memory for a much smaller tool schema in the ~3B model's context.
    private func trimmedSession(for prompt: String) -> LanguageModelSession {
        let all = Self.tools(toolbox: toolbox, sink: sink)
        let keep = Set(ToolSelector.select(prompt, available: all.map { $0.name }).tools)
        return LanguageModelSession(tools: all.filter { keep.contains($0.name) },
                                    instructions: AgentVoice.instructions())
    }

    // MARK: - Planning

    /// Ask the model for a structured plan; fall back to the deterministic
    /// planner when generation fails or names unknown tools. Returns nil when
    /// neither produces a plan of two or more steps.
    private func runPlanned(_ prompt: String,
                            continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation) async -> PlanExecutor.Outcome? {
        var plan: AgentPlan?
        do {
            plan = try await generatePlan(for: prompt)
        } catch {
            plan = nil
        }
        if plan == nil { plan = CompoundPlanner.plan(prompt) }
        guard let plan else { return nil }
        let outcome = PlanExecutor(toolbox: toolbox).execute(plan)
        for event in outcome.events {
            continuation.yield(event)
            try? await Task.sleep(for: .milliseconds(120))
        }
        return outcome
    }

    private func generatePlan(for prompt: String) async throws -> AgentPlan? {
        let specs = AgentToolRegistry.all(toolbox: toolbox)
        let names = Set(specs.map(\.name))
        let planner = LanguageModelSession(instructions: Self.plannerInstructions(specs: specs))
        let response = try await planner.respond(to: prompt, generating: GeneratedPlan.self)
        var steps: [PlanStep] = []
        for step in response.content.steps {
            guard names.contains(step.tool) else { return nil } // unknown tool: don't guess
            var arguments: [String: String] = [:]
            for argument in step.arguments where !argument.value.isEmpty {
                arguments[argument.name] = argument.value
            }
            steps.append(PlanStep(tool: step.tool, arguments: arguments))
        }
        guard steps.count >= 2 else { return nil }
        return AgentPlan(goal: prompt, steps: steps)
    }

    private static func plannerInstructions(specs: [AgentToolSpec]) -> String {
        let catalog = specs.map { spec in
            let params = spec.parameters.map { "\($0.name)\($0.required ? "*" : "")" }
                .joined(separator: ", ")
            return "- \(spec.name)(\(params)): \(spec.description)"
        }.joined(separator: "\n")
        return """
        You turn one request into an ordered list of tool calls for a personal \
        workspace app. Use only these tools (* = required argument):
        \(catalog)

        Rules: one step per action, in the order the user said them. To refer \
        to something an earlier step creates, use $N for step N (for example \
        project: "$1"). Use natural-language dates ("Friday"). Never invent \
        tools or arguments.
        """
    }

    /// One short, model-written sentence about what the plan did. Uses a
    /// tool-less session so narration can never trigger a second execution.
    private func narrate(_ outcome: PlanExecutor.Outcome, prompt: String,
                         continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation) async -> String {
        let narrator = LanguageModelSession(instructions: AgentVoice.instructions())
        let facts = outcome.steps.enumerated().map { index, step in
            "\(index + 1). \(step.result?.detail ?? "skipped")"
        }.joined(separator: "\n")
        let request = """
        The user asked: "\(prompt)". These steps ran:
        \(facts)
        \(outcome.succeeded ? "Everything succeeded." : "The plan stopped early: \(outcome.message)")
        Tell the user what happened in one or two sentences. Mention they can say "undo that".
        """
        do {
            var text = ""
            for try await partial in narrator.streamResponse(to: request) {
                text = partial.content
                continuation.yield(.text(text))
            }
            return text.isEmpty ? outcome.message : text
        } catch {
            continuation.yield(.text(outcome.message))
            return outcome.message
        }
    }

    // MARK: - Tool bridge

    private static func tools(toolbox: ToolBox, sink: ToolEventSink) -> [any Tool] {
        // Integration tools are offered only once the user opted in: they
        // cost context, and an unusable tool invites a wasted call.
        var tools = coreTools(toolbox: toolbox, sink: sink)
        if toolbox.integrations.settings.calendarEnabled {
            tools.append(CalendarAgendaTool(toolbox: toolbox, sink: sink))
        }
        if toolbox.integrations.settings.remindersEnabled {
            tools.append(ExportToRemindersTool(toolbox: toolbox, sink: sink))
        }
        return tools
    }

    private static func coreTools(toolbox: ToolBox, sink: ToolEventSink) -> [any Tool] {
        [
            CreateTaskTool(toolbox: toolbox, sink: sink),
            CompleteTaskTool(toolbox: toolbox, sink: sink),
            UpdateTaskTool(toolbox: toolbox, sink: sink),
            QueryTasksTool(toolbox: toolbox, sink: sink),
            CreateProjectTool(toolbox: toolbox, sink: sink),
            ProjectStatusTool(toolbox: toolbox, sink: sink),
            AddMilestoneTool(toolbox: toolbox, sink: sink),
            CreateNoteTool(toolbox: toolbox, sink: sink),
            SearchNotesTool(toolbox: toolbox, sink: sink),
            NotesFromTool(toolbox: toolbox, sink: sink),
            LinkItemsTool(toolbox: toolbox, sink: sink),
            AgendaTool(toolbox: toolbox, sink: sink),
            RecallTool(toolbox: toolbox, sink: sink),
            UndoTool(toolbox: toolbox, sink: sink),
            AskNotesTool(toolbox: toolbox, sink: sink),
            RescheduleTaskTool(toolbox: toolbox, sink: sink),
            SnoozeTaskTool(toolbox: toolbox, sink: sink),
            SetPriorityTool(toolbox: toolbox, sink: sink),
            SetRecurrenceTool(toolbox: toolbox, sink: sink),
            ListMilestonesTool(toolbox: toolbox, sink: sink),
            AppendNoteTool(toolbox: toolbox, sink: sink),
            SearchEverythingTool(toolbox: toolbox, sink: sink),
        ]
    }
}

/// Routes tool activity out of FoundationModels' tool calls and into the
/// backend's event stream, and persists the record for the transcript.
@MainActor
final class ToolEventSink {
    var emit: ((AgentEvent) -> Void)?
    /// Native multi-turn tool calls within one reply are numbered as steps.
    private var stepCount = 0

    func resetStepCount() { stepCount = 0 }

    func perform(_ name: String, _ activity: String,
                 _ op: @MainActor () -> ToolResult) -> String {
        stepCount += 1
        emit?(.toolStarted(name: name, summary: activity))
        let result = op()
        var record = result.record(toolName: name)
        if stepCount > 1 { record.stepLabel = "#\(stepCount)" }
        emit?(.toolFinished(record))
        return result.detail
    }
}

// MARK: - Guided plan generation

@Generable
struct GeneratedPlan {
    @Guide(description: "The tool calls to make, in order")
    let steps: [GeneratedStep]
}

@Generable
struct GeneratedStep {
    @Guide(description: "Exact tool name from the list")
    let tool: String
    @Guide(description: "Arguments for the tool")
    let arguments: [GeneratedArgument]
}

@Generable
struct GeneratedArgument {
    @Guide(description: "Argument name")
    let name: String
    @Guide(description: "Argument value; use $N to refer to what step N created")
    let value: String
}

// MARK: - Tool conformances

private struct CreateTaskTool: Tool {
    let name = "createTask"
    let description = "Create a task or reminder for the user."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "Short imperative task title")
        let title: String
        @Guide(description: "Due date in natural language, e.g. 'Friday', 'tomorrow', 'June 20'")
        let due: String?
        @Guide(description: "Priority: low, normal, high, or urgent")
        let priority: String?
        @Guide(description: "Name of the project to file this under")
        let project: String?
        @Guide(description: "Repeat rule if recurring: daily, weekdays, weekly, every other Monday, every 3 days")
        let repeats: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Creating task") {
            toolbox.createTask(title: arguments.title, due: arguments.due,
                               priority: arguments.priority, projectName: arguments.project,
                               repeats: arguments.repeats)
        }
    }
}

private struct CompleteTaskTool: Tool {
    let name = "completeTask"
    let description = "Mark a task as done, matched by words from its title."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "Words from the task's title")
        let query: String
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Completing task") {
            toolbox.completeTask(query: arguments.query)
        }
    }
}

private struct UpdateTaskTool: Tool {
    let name = "updateTask"
    let description = "Change a task's due date, priority, or project."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "Words from the task's title")
        let query: String
        @Guide(description: "New due date in natural language")
        let due: String?
        @Guide(description: "New priority: low, normal, high, or urgent")
        let priority: String?
        @Guide(description: "Project to move the task into")
        let project: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Updating task") {
            toolbox.updateTask(query: arguments.query, due: arguments.due,
                               priority: arguments.priority, projectName: arguments.project)
        }
    }
}

private struct QueryTasksTool: Tool {
    let name = "queryTasks"
    let description = "List the user's tasks with a filter."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "Filter: today, overdue, blocked, upcoming, or all")
        let filter: String
        @Guide(description: "Limit results to this project name")
        let project: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Looking at tasks") {
            toolbox.queryTasks(filter: arguments.filter, projectName: arguments.project)
        }
    }
}

private struct CreateProjectTool: Tool {
    let name = "createProject"
    let description = "Create a new project."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "Project name")
        let projectName: String
        @Guide(description: "One-line summary of the project")
        let summary: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Creating project") {
            toolbox.createProject(name: arguments.projectName, summary: arguments.summary ?? "")
        }
    }
}

private struct ProjectStatusTool: Tool {
    let name = "projectStatus"
    let description = "Get progress, blockers, milestones and recent activity for a project."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "Project name")
        let projectName: String
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Checking project") {
            toolbox.projectStatus(name: arguments.projectName)
        }
    }
}

private struct AddMilestoneTool: Tool {
    let name = "addMilestone"
    let description = "Add a milestone to a project."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "Project name")
        let projectName: String
        @Guide(description: "Milestone title")
        let title: String
        @Guide(description: "Target date in natural language")
        let target: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Adding milestone") {
            toolbox.addMilestone(projectName: arguments.projectName,
                                 title: arguments.title, target: arguments.target)
        }
    }
}

private struct CreateNoteTool: Tool {
    let name = "createNote"
    let description = "Capture a note for the user."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "Note title")
        let title: String
        @Guide(description: "Note content")
        let body: String
        @Guide(description: "Project name to file it under")
        let project: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Writing note") {
            toolbox.createNote(title: arguments.title, body: arguments.body,
                               projectName: arguments.project)
        }
    }
}

private struct SearchNotesTool: Tool {
    let name = "searchNotes"
    let description = "Semantic and keyword search across all the user's notes."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "What to search for")
        let query: String
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Searching notes") {
            toolbox.searchNotes(query: arguments.query)
        }
    }
}

private struct NotesFromTool: Tool {
    let name = "notesFrom"
    let description = "Fetch full text of notes from a given day (e.g. 'yesterday', 'Monday')."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "The day, in natural language")
        let day: String
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Reading notes") {
            toolbox.notesFrom(dayDescription: arguments.day)
        }
    }
}

private struct LinkItemsTool: Tool {
    let name = "linkItems"
    let description = "Create a knowledge-graph link between two items (notes, tasks, projects)."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "Source item, referenced by name")
        let from: String
        @Guide(description: "Target item, referenced by name")
        let to: String
        @Guide(description: "Relation, e.g. references, inspired-by, blocks")
        let relation: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Linking items") {
            toolbox.linkItems(from: arguments.from, to: arguments.to,
                              relation: arguments.relation ?? "references")
        }
    }
}

private struct AgendaTool: Tool {
    let name = "agenda"
    let description = "What needs the user's attention today: overdue, due today, blocked, this week."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Composing agenda") {
            toolbox.agenda()
        }
    }
}

private struct AskNotesTool: Tool {
    let name = "askNotes"
    let description = "Answer a question from the user's own notes. Returns numbered source passages; answer only from them and cite inline as [n]."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "The user's question")
        let question: String
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Reading your notes") {
            toolbox.askNotes(question: arguments.question)
        }
    }
}

private struct CalendarAgendaTool: Tool {
    let name = "calendarAgenda"
    let description = "Read the user's calendar for a window: today, this morning, this afternoon, this evening, or tomorrow."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "today, this morning, this afternoon, this evening, or tomorrow")
        let window: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Reading your calendar") {
            toolbox.calendarAgenda(window: arguments.window)
        }
    }
}

private struct ExportToRemindersTool: Tool {
    let name = "exportToReminders"
    let description = "Copy tasks into Apple Reminders."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "today, upcoming, overdue, all, or words from a task title")
        let scope: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Exporting to Reminders") {
            toolbox.exportToReminders(scope: arguments.scope)
        }
    }
}

private struct RescheduleTaskTool: Tool {
    let name = "rescheduleTask"
    let description = "Move a task's due date to a new date, or shift it by an amount."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "Words from the task's title")
        let query: String
        @Guide(description: "New date in natural language, e.g. 'next Tuesday', 'end of month'")
        let to: String?
        @Guide(description: "Relative shift, e.g. '2 days', 'a week'")
        let by: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Rescheduling") {
            toolbox.rescheduleTask(query: arguments.query, to: arguments.to, by: arguments.by)
        }
    }
}

private struct SnoozeTaskTool: Tool {
    let name = "snoozeTask"
    let description = "Snooze a task until later; defaults to tomorrow."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "Words from the task's title")
        let query: String
        @Guide(description: "'tomorrow', '3 days', 'a week' or 'until Monday'")
        let until: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Snoozing") {
            toolbox.snoozeTask(query: arguments.query, until: arguments.until)
        }
    }
}

private struct SetPriorityTool: Tool {
    let name = "setPriority"
    let description = "Set a task's priority."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "Words from the task's title")
        let query: String
        @Guide(description: "low, normal, high, or urgent")
        let priority: String
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Setting priority") {
            toolbox.setPriority(query: arguments.query, priority: arguments.priority)
        }
    }
}

private struct SetRecurrenceTool: Tool {
    let name = "setRecurrence"
    let description = "Make a task repeat, or stop it repeating with 'none'."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "Words from the task's title")
        let query: String
        @Guide(description: "daily, weekdays, weekly, every other Monday, every 3 days, or none")
        let rule: String
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Setting repeat") {
            toolbox.setRecurrence(query: arguments.query, rule: arguments.rule)
        }
    }
}

private struct ListMilestonesTool: Tool {
    let name = "listMilestones"
    let description = "List a project's milestones and target dates."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "Project name")
        let projectName: String
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Milestones") {
            toolbox.listMilestones(projectName: arguments.projectName)
        }
    }
}

private struct AppendNoteTool: Tool {
    let name = "appendNote"
    let description = "Add text to the end of an existing note."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "Words from the note's title")
        let query: String
        @Guide(description: "Text to append")
        let text: String
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Writing note") {
            toolbox.appendNote(query: arguments.query, text: arguments.text)
        }
    }
}

private struct SearchEverythingTool: Tool {
    let name = "searchEverything"
    let description = "Search tasks, projects and notes at once."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "What to look for")
        let query: String
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Searching") {
            toolbox.searchEverything(query: arguments.query)
        }
    }
}

private struct UndoTool: Tool {
    let name = "undo"
    let description = "Undo the last change: the whole last request (turn) or only the last action (step)."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "turn or step")
        let scope: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Undoing") {
            toolbox.undo(scope: arguments.scope)
        }
    }
}

private struct RecallTool: Tool {
    let name = "recall"
    let description = "Search past conversations and completed work."
    let toolbox: ToolBox
    let sink: ToolEventSink

    @Generable
    struct Arguments {
        @Guide(description: "What to remember")
        let query: String
    }

    func call(arguments: Arguments) async throws -> String {
        await sink.perform(name, "Remembering") {
            toolbox.recall(query: arguments.query)
        }
    }
}
#endif
