import Foundation

/// One tool call inside a multi-step plan. Argument values may reference the
/// outputs of earlier steps:
///   `$2`        → step 2's exact reference (`id:<uuid>` of what it created)
///   `$2.title`  → any named output of step 2 (`title`, `kind`, …)
///   `$last`     → the most recent step that produced a reference
struct PlanStep: Equatable {
    var tool: String
    var arguments: [String: String]

    /// Human phrasing for the plan card, e.g. "Add task “Draft copy” · Friday".
    func describe(resolvingNamesFrom plan: AgentPlan? = nil) -> String {
        func arg(_ key: String) -> String? {
            guard let raw = arguments[key], !raw.isEmpty else { return nil }
            return plan?.displayName(for: raw) ?? raw
        }
        switch tool {
        case "createTask":
            var line = "Add task “\(arg("title") ?? "Untitled")”"
            if let due = arg("due") { line += " · \(due)" }
            if let project = arg("project") { line += " · in \(project)" }
            if let rule = arg("repeat") { line += " · repeats \(rule)" }
            return line
        case "createProject": return "Create project “\(arg("name") ?? "Untitled")”"
        case "createNote": return "Write note “\(arg("title") ?? "Untitled")”"
        case "linkItems": return "Link \(arg("from") ?? "?") → \(arg("to") ?? "?")"
        case "completeTask": return "Complete “\(arg("query") ?? "?")”"
        case "addMilestone": return "Add milestone “\(arg("title") ?? "?")” to \(arg("project") ?? "?")"
        case "updateTask", "rescheduleTask", "snoozeTask", "setPriority", "setRecurrence":
            let changes = arguments.keys.filter { $0 != "query" }.sorted()
                .compactMap { key in arg(key).map { "\(key) \($0)" } }
                .joined(separator: ", ")
            return "Update “\(arg("query") ?? "?")”" + (changes.isEmpty ? "" : " · \(changes)")
        default:
            let args = arguments.keys.sorted()
                .compactMap { key in arg(key).map { "\(key): \($0)" } }
                .joined(separator: ", ")
            return args.isEmpty ? tool : "\(tool) · \(args)"
        }
    }
}

struct AgentPlan: Equatable {
    var id: UUID = UUID()
    /// The request the plan answers, verbatim.
    var goal: String
    var steps: [PlanStep]

    /// Readable stand-in for a `$n` reference on the plan card: step 1
    /// creating project "Launch" turns `$1` into "Launch".
    func displayName(for value: String) -> String? {
        guard let index = PlanReference.stepIndex(in: value, stepCount: steps.count) else { return nil }
        let step = steps[index]
        return step.arguments["name"] ?? step.arguments["title"] ?? "step \(index + 1)"
    }

    /// Numbered plan text, as shown on the plan card before execution.
    var outline: String {
        steps.enumerated()
            .map { "\($0.offset + 1). \($0.element.describe(resolvingNamesFrom: self))" }
            .joined(separator: "\n")
    }
}

/// `$n` / `$n.key` / `$last` reference syntax.
enum PlanReference {
    /// Zero-based index of the step a bare reference points at, if any.
    static func stepIndex(in value: String, stepCount: Int) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("$") else { return nil }
        let body = trimmed.dropFirst().split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
        if body == "last" { return stepCount > 0 ? stepCount - 1 : nil }
        guard let n = Int(body), n >= 1, n <= stepCount else { return nil }
        return n - 1
    }

    /// Substitute references using the outputs of steps run so far.
    /// Returns nil (with the offending value) when a reference can't resolve.
    static func resolve(_ arguments: [String: String],
                        outputs: [[String: String]]) -> (resolved: [String: String]?, unresolved: String?) {
        var out: [String: String] = [:]
        for (key, value) in arguments {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("$") else { out[key] = value; continue }
            let parts = trimmed.dropFirst().split(separator: ".", maxSplits: 1).map(String.init)
            let head = parts.first ?? ""
            let field = parts.count > 1 ? parts[1] : "ref"
            let index: Int?
            if head == "last" {
                index = outputs.lastIndex { $0[field] != nil }
            } else if let n = Int(head), n >= 1, n <= outputs.count {
                index = n - 1
            } else {
                index = nil
            }
            guard let index, let resolved = outputs[index][field] else {
                return (nil, value)
            }
            out[key] = resolved
        }
        return (out, nil)
    }
}
