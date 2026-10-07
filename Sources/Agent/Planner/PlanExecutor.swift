import Foundation

/// Runs an `AgentPlan` step by step through the tool registry (and therefore
/// ToolBox → DataServices, the single write path). Each step's arguments are
/// resolved against earlier outputs, each result is checked against a
/// postcondition, and the first failure stops the plan with a clear message.
/// Completed steps stay applied and are journaled under the plan's group, so
/// one "undo that" (or the plan card's Undo) reverts them atomically.
///
/// Execution is synchronous — tools are instant at personal scale — and the
/// events it produces are returned for the backend to stream with pacing.
@MainActor
struct PlanExecutor {
    enum StepStatus: Equatable {
        case done
        case failed(String)
        case skipped
    }

    struct StepOutcome {
        let step: PlanStep
        let resolvedArguments: [String: String]
        let result: ToolResult?
        let status: StepStatus
    }

    struct Outcome {
        let plan: AgentPlan
        let steps: [StepOutcome]
        /// Zero-based index of the step that failed, if any.
        let failedAt: Int?
        /// User-facing summary of what happened.
        let message: String
        /// Event stream for the thread: plan card, step cards, final plan card.
        let events: [AgentEvent]
        /// Journal group the plan's mutations were recorded under.
        let group: String

        var succeeded: Bool { failedAt == nil }
        var executedTools: [String] {
            steps.filter { $0.status != .skipped }.map(\.step.tool)
        }
    }

    let toolbox: ToolBox

    /// Upper bound on plan length — a guard against runaway model plans.
    static let maxSteps = 12

    func execute(_ plan: AgentPlan) -> Outcome {
        let specs = AgentToolRegistry.all(toolbox: toolbox)
        let ownsGroup = toolbox.turnGroupID.isEmpty
        if ownsGroup { toolbox.turnGroupID = plan.id.uuidString }
        let group = toolbox.turnGroupID
        defer { if ownsGroup { toolbox.turnGroupID = "" } }

        let steps = Array(plan.steps.prefix(Self.maxSteps))
        let total = steps.count
        var events: [AgentEvent] = []
        var outcomes: [StepOutcome] = []
        var outputs: [[String: String]] = []
        var failedAt: Int?

        var planCard = ToolEventRecord(
            id: plan.id, toolName: "plan",
            summary: "Plan · \(total) step\(total == 1 ? "" : "s")",
            detail: plan.outline, succeeded: true)
        events.append(.toolFinished(planCard))

        for (index, step) in steps.enumerated() {
            let label = "\(index + 1)/\(total)"
            if failedAt != nil {
                outcomes.append(.init(step: step, resolvedArguments: step.arguments,
                                      result: nil, status: .skipped))
                outputs.append([:])
                continue
            }
            events.append(.toolStarted(name: step.tool,
                                       summary: "Step \(label) · \(Self.activity(for: step.tool))"))

            let (resolved, unresolved) = PlanReference.resolve(step.arguments, outputs: outputs)
            let result: ToolResult
            var problem: String?
            if let resolved {
                if let spec = specs.first(where: { $0.name == step.tool }) {
                    result = spec.run(resolved)
                    problem = Self.verify(step.tool, arguments: resolved, result: result,
                                          services: toolbox.services)
                } else {
                    result = ToolResult(summary: "Unknown tool “\(step.tool)”",
                                        detail: "There is no tool named \(step.tool).", succeeded: false)
                    problem = result.detail
                }
            } else {
                let what = unresolved ?? "a reference"
                result = ToolResult(summary: "Missing input \(what)",
                                    detail: "Step \(index + 1) needed \(what), which an earlier step didn't produce.",
                                    succeeded: false)
                problem = result.detail
            }

            var record = result.record(toolName: step.tool)
            record.stepLabel = label
            if problem != nil {
                record.succeeded = false
                // A step that ran but missed its postcondition leaves no
                // trace: revert its own mutation before stopping.
                if let entry = result.journalID {
                    _ = UndoEngine(services: toolbox.services).undo(entryID: entry)
                    record.journalID = nil
                }
            }
            events.append(.toolFinished(record))

            outcomes.append(.init(step: step, resolvedArguments: resolved ?? step.arguments,
                                  result: result,
                                  status: problem.map { .failed($0) } ?? .done))
            outputs.append(result.outputs)
            if problem != nil { failedAt = index }
        }

        // Final state of the plan card, same id so the UI updates in place.
        var marks: [String] = []
        for (offset, outcome) in outcomes.enumerated() {
            let symbol: String
            switch outcome.status {
            case .done: symbol = "✓"
            case .failed: symbol = "✗"
            case .skipped: symbol = "–"
            }
            marks.append("\(symbol) \(offset + 1). \(outcome.step.describe(resolvingNamesFrom: plan))")
        }
        let applied = outcomes.filter { $0.status == .done }.count
        let journaled = !toolbox.services.journal.pending(inGroup: group).isEmpty
        planCard.detail = marks.joined(separator: "\n")
        planCard.succeeded = failedAt == nil
        planCard.summary = failedAt.map { "Plan stopped at step \($0 + 1)/\(total)" }
            ?? "Plan done · \(applied)/\(total) step\(total == 1 ? "" : "s")"
        planCard.undoGroup = journaled ? group : nil
        events.append(.toolFinished(planCard))

        return Outcome(plan: plan, steps: outcomes, failedAt: failedAt,
                       message: Self.message(outcomes: outcomes, failedAt: failedAt, journaled: journaled),
                       events: events, group: group)
    }

    // MARK: - Postconditions

    /// nil when the step did what it claimed; otherwise the problem.
    static func verify(_ tool: String, arguments: [String: String], result: ToolResult,
                       services: DataServices) -> String? {
        guard result.succeeded else { return result.detail }
        let ref = result.outputs["ref"].flatMap(EntityRef.id(from:))
        switch tool {
        case "createTask":
            guard let ref, let task = services.tasks.find(id: ref) else { return "the task wasn't saved." }
            if let wanted = arguments["project"], !wanted.isEmpty, task.project == nil {
                return "couldn't find the project “\(wanted)” to file “\(task.title)” under."
            }
            return nil
        case "createProject":
            return ref.flatMap { services.projects.find(id: $0) } == nil ? "the project wasn't saved." : nil
        case "createNote", "appendNote":
            return ref.flatMap { services.notes.find(id: $0) } == nil ? "the note wasn't saved." : nil
        case "addMilestone":
            return ref.flatMap { services.projects.milestone(id: $0) } == nil ? "the milestone wasn't saved." : nil
        case "completeTask":
            guard let ref, let task = services.tasks.find(id: ref) else { return "the task wasn't found." }
            // A recurring task is reopened as its next occurrence; the
            // completed instance is what we check.
            return task.isDone ? nil : "“\(task.title)” isn't marked done."
        case "linkItems":
            return ref.flatMap { services.graph.link(id: $0) } == nil ? "the link wasn't saved." : nil
        default:
            return nil
        }
    }

    // MARK: - Messages

    static func message(outcomes: [StepOutcome], failedAt: Int?, journaled: Bool) -> String {
        let total = outcomes.count
        guard let failedAt else {
            let done = outcomes.compactMap { $0.result?.summary }
            return "Done — \(total) step\(total == 1 ? "" : "s"): " + done.joined(separator: "; ") + "."
        }
        var problem = "that step failed"
        if case .failed(let why) = outcomes[failedAt].status { problem = why }
        var text = "I stopped at step \(failedAt + 1) of \(total) (\(outcomes[failedAt].step.describe())): \(problem)"
        if !text.hasSuffix(".") { text += "." }
        if journaled {
            text += failedAt == 1
                ? " Step 1 is in place; say “undo that” to roll it back."
                : " Steps 1–\(failedAt) are in place; say “undo that” to roll them back."
        } else {
            text += " Nothing was changed."
        }
        return text
    }

    static func activity(for tool: String) -> String {
        switch tool {
        case "createTask": return "Creating task"
        case "completeTask": return "Completing task"
        case "updateTask", "rescheduleTask", "snoozeTask", "setPriority", "setRecurrence": return "Updating task"
        case "queryTasks": return "Looking at tasks"
        case "createProject": return "Creating project"
        case "projectStatus": return "Checking project"
        case "addMilestone", "listMilestones": return "Milestones"
        case "createNote", "appendNote": return "Writing note"
        case "searchNotes", "searchEverything", "notesFrom": return "Searching"
        case "askNotes": return "Reading your notes"
        case "linkItems": return "Linking items"
        case "agenda", "calendarAgenda": return "Composing agenda"
        case "recall": return "Remembering"
        case "undo": return "Undoing"
        case "exportToReminders": return "Exporting to Reminders"
        default: return "Working"
        }
    }
}
