import Foundation

/// The deterministic planner: splits a compound utterance on "and", "then",
/// commas and semicolons into clauses, parses each clause with the intent
/// grammar, expands "add 3 tasks…" / "add tasks: a, b and c" into one step
/// per task, and threads context between steps:
///   - tasks created after a project in the same request are filed under it;
///   - pronouns ("it", "that", "them") point at the item the request is about.
/// A split only happens where the next clause starts with a command verb, so
/// "remind me to call mum and dad" stays one task.
enum CompoundPlanner {
    /// Words that can open a new command clause.
    static let commandVerbs: Set<String> = [
        "add", "create", "make", "start", "remind", "link", "connect", "mark", "complete",
        "finish", "check", "tick", "note", "jot", "write", "set", "move", "push",
        "reschedule", "postpone", "snooze", "schedule", "put", "file", "append", "prioritize",
        "undo", "show", "list", "find", "search", "summarize", "export", "attach", "new",
        "todo", "flag", "bump", "delay", "defer", "ask", "give", "what's", "whats",
    ]

    static let pronouns: Set<String> = [
        "it", "this", "that", "them", "this project", "that project", "the project", "it all",
    ]

    // MARK: - Planning

    /// A plan when the request has two or more steps; nil for a single intent.
    static func plan(_ utterance: String) -> AgentPlan? {
        let clauses = split(utterance)
        var intents: [ParsedIntent] = []

        for (index, clause) in clauses.enumerated() {
            let anchorName = intents.indices.reversed()
                .first { intents[$0].tool == "createProject" }
                .flatMap { intents[$0].arguments["name"] }
            if let expanded = expandMulti(clause, anchorName: anchorName) {
                intents.append(contentsOf: expanded)
                continue
            }
            let parsed = IntentGrammar.parse(clause)
            // An unrecognized trailing clause is not a new command: keep the
            // request single rather than inventing a plan around it.
            if parsed.isDefault && index > 0 { return nil }
            intents.append(parsed)
        }
        guard intents.count >= 2 else { return nil }
        return AgentPlan(goal: utterance, steps: threadContext(intents))
    }

    /// True when the request will become a multi-step plan.
    static func isCompound(_ utterance: String) -> Bool { plan(utterance) != nil }

    /// Fill in cross-step references: project filing and pronouns.
    static func threadContext(_ intents: [ParsedIntent]) -> [PlanStep] {
        var steps: [PlanStep] = []
        var lastProject: Int?   // 1-based step number
        var lastTask: Int?
        var lastEntity: Int?
        let creators: Set<String> = ["createTask", "createProject", "createNote", "addMilestone"]

        for intent in intents {
            var args = intent.arguments
            let number = steps.count + 1

            for (key, value) in args where pronouns.contains(value.lowercased()) {
                let target: Int?
                switch intent.tool {
                case "linkItems": target = lastProject ?? lastEntity
                case "addMilestone", "projectStatus", "listMilestones": target = lastProject
                case "createTask": target = key == "project" ? lastProject : lastEntity
                default: target = lastTask ?? lastEntity
                }
                if let target { args[key] = "$\(target)" }
            }
            if let project = lastProject {
                if intent.tool == "createTask", args["project"] == nil { args["project"] = "$\(project)" }
                if intent.tool == "addMilestone", (args["project"] ?? "").isEmpty { args["project"] = "$\(project)" }
            }
            steps.append(PlanStep(tool: intent.tool, arguments: args))

            if intent.tool == "createProject" { lastProject = number }
            if intent.tool == "createTask" { lastTask = number }
            if creators.contains(intent.tool) { lastEntity = number }
        }
        return steps
    }

    // MARK: - Splitting

    /// Clause boundaries: ", and then", ", then", " and then", " then ",
    /// ", and", " and ", ",", ";". A boundary counts only when the text after
    /// it opens with a command verb.
    static func split(_ utterance: String) -> [String] {
        let text = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"\s*(?:[,;]\s*(?:and\s+)?(?:then\s+)?|\s+and\s+(?:then\s+)?|\s+then\s+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return [text]
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [text] }

        var clauses: [String] = []
        var current = ""
        var cursor = 0
        for match in matches {
            let piece = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let separator = ns.substring(with: match.range)
            current += piece
            let restStart = match.range.location + match.range.length
            let rest = ns.substring(from: restStart)
            if opensCommand(rest) && !current.trimmingCharacters(in: .whitespaces).isEmpty {
                clauses.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current += separator
            }
            cursor = restStart
        }
        current += ns.substring(from: cursor)
        let last = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !last.isEmpty { clauses.append(last) }
        return clauses.isEmpty ? [text] : clauses
    }

    static func opensCommand(_ text: String) -> Bool {
        var words = text.lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .punctuationCharacters.subtracting(["'"])) }
        while let first = words.first, ["also", "please", "then", "and"].contains(first) {
            words.removeFirst()
        }
        guard let first = words.first else { return false }
        if first == "i" && words.count > 2 && words[1] == "need" { return true }
        return commandVerbs.contains(first)
    }

    // MARK: - Multi-item expansion

    static let numberWords: [String: Int] = [
        "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "a couple of": 2, "a few": 3,
    ]

    /// "add 3 tasks for Friday" → three createTask steps;
    /// "add tasks: draft copy, book venue and send invites" → one per item.
    static func expandMulti(_ clause: String, anchorName: String?) -> [ParsedIntent]? {
        let lower = clause.lowercased()
        let counted = #"^(?:please\s+)?(?:add|create|make)\s+(\d+|two|three|four|five|six|seven|eight|nine|ten|a couple of|a few)\s+(?:new\s+)?(?:tasks|todos|to-dos)\b(.*)$"#
        if let match = lower.range(of: counted, options: .regularExpression) {
            let body = String(lower[match])
            let regex = try? NSRegularExpression(pattern: counted)
            let ns = body as NSString
            guard let m = regex?.firstMatch(in: body, range: NSRange(location: 0, length: ns.length)) else { return nil }
            let countText = ns.substring(with: m.range(at: 1))
            let tail = m.range(at: 2).location == NSNotFound ? "" : ns.substring(with: m.range(at: 2))
            guard let count = Int(countText) ?? numberWords[countText], (1...10).contains(count) else { return nil }
            let due = NaturalDateParser.parse(tail) != nil ? IntentGrammar.dueText(in: tail) : nil
            let stem = anchorName.map { "\($0) task" } ?? "New task"
            return (1...count).map { i in
                var args = ["title": "\(stem) \(i)"]
                if let due { args["due"] = due }
                return ParsedIntent(tool: "createTask", arguments: args)
            }
        }

        let listed = #"^(?:please\s+)?(?:add|create)\s+(?:the\s+)?(?:following\s+)?(?:tasks|todos|to-dos)\s*:?\s+(.+)$"#
        if lower.range(of: listed, options: .regularExpression) != nil,
           let colon = clause.range(of: #"(?i)(tasks|todos|to-dos)\s*:?\s+"#, options: .regularExpression) {
            var body = String(clause[colon.upperBound...])
            var due: String?
            if NaturalDateParser.parse(body) != nil {
                let words = IntentGrammar.dueText(in: body)
                if words.lowercased() != body.lowercased() {
                    due = words
                    let trimmed = IntentGrammar.removeSuffix(body, "for \(words)")
                    body = trimmed != body ? trimmed : IntentGrammar.removeSuffix(body, words)
                }
            }
            let items = body
                .replacingOccurrences(of: #"\s*(?:,\s*(?:and\s+)?|\s+and\s+)"#, with: "\u{1F}", options: .regularExpression)
                .split(separator: "\u{1F}")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
                .filter { !$0.isEmpty }
            guard items.count >= 2 else { return nil }
            return items.map { item in
                var args = ["title": IntentGrammar.sentenceCase(item)]
                if let due { args["due"] = due }
                return ParsedIntent(tool: "createTask", arguments: args)
            }
        }
        return nil
    }
}
