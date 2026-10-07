import Foundation

/// A parsed, not-yet-executed intent: which tool, with which string
/// arguments. Parsing is pure, so the planner can build a whole multi-step
/// plan (and show it) before anything runs.
struct ParsedIntent: Equatable {
    var tool: String
    var arguments: [String: String] = [:]
    /// Tried in order when the primary call fails ("what's blocking X" falls
    /// back to listing blocked tasks when X isn't a project).
    var fallback: [ParsedIntent] = []
    /// True when nothing matched and the router fell back to the agenda.
    var isDefault: Bool = false
}

/// The deterministic brain's grammar. Rules run in order; explicit capture
/// commands come first because in "remind me to finish the deck" the verbs
/// belong to the task title, not the intent.
enum IntentGrammar {
    static func parse(_ prompt: String) -> ParsedIntent {
        let lower = prompt.lowercased()

        // Reminders / tasks
        if lower.hasPrefix("remind me") || lower.contains("add a task") || lower.contains("add task")
            || lower.hasPrefix("todo") || lower.hasPrefix("i need to") {
            var title = strip(prompt, prefixes: ["remind me to", "remind me", "add a task to", "add a task:", "add task", "todo:", "todo", "i need to"])
            var args: [String: String] = [:]
            if NaturalDateParser.parse(prompt) != nil {
                let dueWords = dueText(in: prompt)
                title = removeSuffix(title, dueWords)
                args["due"] = dueWords
            }
            args["title"] = sentenceCase(title)
            return ParsedIntent(tool: "createTask", arguments: args)
        }

        // Notes — capture. "notes about …" is a search, not a capture.
        if lower.hasPrefix("note ") || lower.hasPrefix("note:") || lower.contains("take a note")
            || lower.hasPrefix("jot") {
            let body = strip(prompt, prefixes: ["note that", "note:", "note", "take a note:", "take a note", "jot down", "jot"])
            return ParsedIntent(tool: "createNote",
                                arguments: ["title": sentenceCase(String(body.prefix(48))), "body": body])
        }

        // Undo
        if let undo = parseUndo(lower) { return undo }

        // Ask your notes (cited Q&A) — before the agenda's "what do i…".
        if let question = askNotesQuestion(prompt) {
            return ParsedIntent(tool: "askNotes", arguments: ["question": question])
        }

        // Agenda
        if lower.contains("agenda") || lower.contains("what's today") || lower.contains("what do i")
            || lower.contains("needs my attention") || (lower.contains("today") && lower.contains("due")) {
            return ParsedIntent(tool: "agenda")
        }

        // Blockers / project status
        if lower.contains("blocking") || lower.contains("blocked") || lower.contains("status of") {
            let name = strip(prompt, prefixes: ["what's blocking", "whats blocking", "what is blocking", "status of", "what's the status of"])
            let blocked = ParsedIntent(tool: "queryTasks", arguments: ["filter": "blocked"])
            if !name.isEmpty {
                return ParsedIntent(tool: "projectStatus", arguments: ["name": name], fallback: [blocked])
            }
            return blocked
        }

        // Complete
        if let range = lower.range(of: #"(complete|finish|mark .* done|i did|check off) "#, options: .regularExpression) {
            // Indices belong to `lower` — convert to a distance before
            // slicing `prompt` (foreign String.Index use traps).
            let offset = lower.distance(from: lower.startIndex, to: range.upperBound)
            guard let start = prompt.index(prompt.startIndex, offsetBy: offset,
                                           limitedBy: prompt.endIndex) else {
                return ParsedIntent(tool: "agenda")
            }
            let query = String(prompt[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return ParsedIntent(tool: "completeTask", arguments: ["query": query])
        }

        // Summaries of a day's notes
        if lower.contains("summarize") || lower.contains("summary") {
            let day = lower.contains("yesterday") ? "yesterday" : lower.contains("today") ? "today" : "yesterday"
            return ParsedIntent(tool: "notesFrom", arguments: ["day": day])
        }

        // Link
        if lower.hasPrefix("link ") || lower.contains("connect ") {
            let body = strip(prompt, prefixes: ["link", "connect"])
            let parts = body.components(separatedBy: " to ")
            if parts.count == 2 {
                return ParsedIntent(tool: "linkItems", arguments: [
                    "from": parts[0].trimmingCharacters(in: .whitespaces),
                    "to": parts[1].trimmingCharacters(in: .whitespaces),
                ])
            }
        }

        // Search
        if lower.contains("find") || lower.contains("search") || lower.contains("notes about")
            || lower.hasPrefix("what do my notes") {
            let query = strip(prompt, prefixes: ["find notes about", "find", "search notes for", "search for", "search", "notes about"])
            return ParsedIntent(tool: "searchNotes", arguments: ["query": query])
        }

        // Recall
        if lower.contains("did i") || lower.contains("when did") || lower.contains("remember") {
            return ParsedIntent(tool: "recall", arguments: [
                "query": strip(prompt, prefixes: ["do you remember", "remember", "when did i", "did i"]),
            ])
        }

        // New project
        if lower.contains("new project") || lower.contains("create a project") || lower.contains("start a project") {
            let name = strip(prompt, prefixes: ["new project called", "new project:", "new project", "create a project called", "create a project", "start a project called", "start a project"])
            return ParsedIntent(tool: "createProject", arguments: ["name": sentenceCase(name)])
        }

        // Default: the agenda, with an honest note about the floor mode.
        return ParsedIntent(tool: "agenda", isDefault: true)
    }

    /// "undo", "undo that", "revert the last step", "take that back".
    static func parseUndo(_ lower: String) -> ParsedIntent? {
        let trimmed = lower.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let starts = ["undo", "revert", "take that back", "take it back", "roll that back",
                      "roll it back", "roll back", "nevermind, undo", "scratch that"]
        guard starts.contains(where: { trimmed == $0 || trimmed.hasPrefix($0 + " ") }) else { return nil }
        let scope = UndoEngine.Scope.from(trimmed)
        return ParsedIntent(tool: "undo", arguments: ["scope": scope.rawValue])
    }

    /// "what do my notes say about X", "ask my notes X", "according to my
    /// notes, X?", "do my notes mention X", "what did I write about X".
    static func askNotesQuestion(_ prompt: String) -> String? {
        let lower = prompt.lowercased()
        let prefixes = ["what do my notes say about", "what do my notes say", "what did my notes say about",
                        "what do my notes tell me about", "ask my notes about", "ask my notes",
                        "according to my notes,", "according to my notes", "do my notes mention",
                        "do my notes say", "what did i write about", "what have i written about",
                        "what did i note about", "check my notes for", "from my notes,"]
        guard let prefix = prefixes.first(where: { lower.hasPrefix($0) }) else { return nil }
        let rest = String(prompt.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return rest.isEmpty ? nil : rest
    }

    // MARK: - Helpers

    static func strip(_ text: String, prefixes: [String]) -> String {
        var out = text
        for p in prefixes where out.lowercased().hasPrefix(p) {
            out = String(out.dropFirst(p.count))
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    /// The date phrase to excise from a task title. Mirrors the phrases
    /// NaturalDateParser understands, so "in 3 days" never leaks into titles.
    static func dueText(in prompt: String) -> String {
        let lower = prompt.lowercased()
        if let range = lower.range(of: #"in \d+ days?"#, options: .regularExpression) {
            return String(lower[range])
        }
        let candidates = ["today", "tomorrow", "next week", "monday", "tuesday", "wednesday",
                          "thursday", "friday", "saturday", "sunday"]
        for c in candidates where lower.contains(c) { return c }
        return prompt // NSDataDetector path will find the explicit date
    }

    static func removeSuffix(_ text: String, _ words: String) -> String {
        // Match on a lowercased copy, excise by distance from the original —
        // String.Index values must never cross string instances.
        let lowerText = text.lowercased()
        let lowerWords = words.lowercased()
        for token in [" on \(lowerWords)", " by \(lowerWords)", " \(lowerWords)"] {
            guard let range = lowerText.range(of: token) else { continue }
            let start = lowerText.distance(from: lowerText.startIndex, to: range.lowerBound)
            let length = lowerText.distance(from: range.lowerBound, to: range.upperBound)
            guard let from = text.index(text.startIndex, offsetBy: start, limitedBy: text.endIndex),
                  let to = text.index(from, offsetBy: length, limitedBy: text.endIndex)
            else { continue }
            var out = text
            out.removeSubrange(from..<to)
            return out.trimmingCharacters(in: .whitespaces)
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    static func sentenceCase(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
