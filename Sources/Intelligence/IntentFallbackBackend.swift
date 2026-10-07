import Foundation

/// Deterministic floor: a rule-based intent parser that drives the same
/// ToolBox. No generation, but "remind me to send the invoice Friday" still
/// creates the task, and "create a project Launch, add 3 tasks for Friday and
/// link it to brand voice" still runs as a five-step plan. Guarantees the
/// product works on any device, simulator included, with zero model assets.
@MainActor
final class IntentFallbackBackend: ModelBackend {
    let displayName = "Quick intents · offline"

    private let toolbox: ToolBox

    init(toolbox: ToolBox) {
        self.toolbox = toolbox
    }

    func resetConversation() {}

    func reply(to prompt: String) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                let turn = Self.routeTurn(prompt, toolbox: toolbox)
                for event in turn.events {
                    continuation.yield(event)
                    // Let each card breathe; a tool's own start→finish gets the longest beat.
                    if case .toolStarted = event {
                        try? await Task.sleep(for: .milliseconds(350))
                    } else {
                        try? await Task.sleep(for: .milliseconds(120))
                    }
                }
                // Stream the reply in word chunks so the condensation reveal
                // behaves identically to a real model.
                var shown = ""
                for word in turn.reply.split(separator: " ", omittingEmptySubsequences: false) {
                    shown += (shown.isEmpty ? "" : " ") + word
                    continuation.yield(.text(shown))
                    try? await Task.sleep(for: .milliseconds(24))
                }
                continuation.yield(.done(finalText: turn.reply))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Turns

    struct Turn {
        /// Tools that ran, in order.
        var tools: [String]
        var results: [ToolResult]
        var events: [AgentEvent]
        var reply: String
        /// Set when the request ran as a multi-step plan.
        var plan: PlanExecutor.Outcome?
    }

    /// Route a whole request: a compound one becomes a plan, anything else a
    /// single intent. Internal so tests and the eval can drive it directly.
    static func routeTurn(_ prompt: String, toolbox: ToolBox) -> Turn {
        if let plan = CompoundPlanner.plan(prompt) {
            let outcome = PlanExecutor(toolbox: toolbox).execute(plan)
            return Turn(tools: outcome.executedTools,
                        results: outcome.steps.compactMap(\.result),
                        events: outcome.events, reply: outcome.message, plan: outcome)
        }
        let routed = routeIntent(prompt, toolbox: toolbox)
        var events: [AgentEvent] = []
        if let tool = routed.tool, let result = routed.result {
            events.append(.toolStarted(name: tool, summary: routed.activity))
            events.append(.toolFinished(result.record(toolName: tool)))
        }
        return Turn(tools: routed.tool.map { [$0] } ?? [],
                    results: routed.result.map { [$0] } ?? [],
                    events: events, reply: routed.reply, plan: nil)
    }

    // MARK: - Single intents

    /// Internal (not private) so the routing table is directly testable
    /// without iterating the paced stream.
    static func routeIntent(_ prompt: String, toolbox: ToolBox)
        -> (tool: String?, activity: String, result: ToolResult?, reply: String) {
        let parsed = IntentGrammar.parse(prompt)
        let specs = AgentToolRegistry.all(toolbox: toolbox)

        var attempt = parsed
        var result = run(attempt, specs: specs)
        for fallback in parsed.fallback where result?.succeeded != true {
            attempt = fallback
            result = run(attempt, specs: specs)
        }
        guard let result else {
            return (nil, "", nil, "I couldn't run that just now.")
        }
        return (attempt.tool, PlanExecutor.activity(for: attempt.tool), result,
                reply(for: attempt, result: result))
    }

    private static func run(_ intent: ParsedIntent, specs: [AgentToolSpec]) -> ToolResult? {
        specs.first { $0.name == intent.tool }?.run(intent.arguments)
    }

    /// The deterministic brain's voice, per tool.
    static func reply(for intent: ParsedIntent, result r: ToolResult) -> String {
        if intent.isDefault {
            return "I'm running in quick-intent mode on this device, so I keep to direct phrasing — try \"remind me to…\", \"what's blocking…\", or \"summarize my notes from yesterday\". Meanwhile, here's today:\n\(r.detail)"
        }
        switch intent.tool {
        case "createTask": return "Got it — \(r.summary.lowercased())."
        case "createNote": return "Noted."
        case "completeTask": return r.succeeded ? "Done — \(r.summary.lowercased())." : r.detail
        case "notesFrom": return extractiveSummary(of: r.detail)
        case "linkItems": return r.succeeded ? "\(r.summary)." : r.detail
        case "createProject": return "\(r.summary). It's waiting in your Projects space."
        default: return r.detail
        }
    }

    /// Kept for existing callers and tests; the grammar owns the logic.
    static func dueText(in prompt: String) -> String {
        IntentGrammar.dueText(in: prompt)
    }

    /// Cheap extractive summary: first sentence of each note section.
    private static func extractiveSummary(of detail: String) -> String {
        let sections = detail.components(separatedBy: "\n\n")
        let leads = sections.compactMap { section -> String? in
            let flat = section.replacingOccurrences(of: "\n", with: " ")
            guard let stop = flat.firstIndex(where: { ".!?".contains($0) }) else {
                return flat.isEmpty ? nil : String(flat.prefix(120))
            }
            return String(flat[...stop])
        }
        guard !leads.isEmpty else { return "Nothing to summarize from that day." }
        return leads.joined(separator: " ")
    }
}
