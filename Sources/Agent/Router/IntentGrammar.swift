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
    static func parse(_ rawPrompt: String) -> ParsedIntent {
        // "Wait, …", "Not now, …": interjections carry no intent.
        let prompt = CommandFrames.stripDiscourse(rawPrompt)
        let lower = prompt.lowercased()

        // Frames the capture rules below would mis-read (v0.2, then v0.3).
        if let early = CommandFrames.beforeCapture(prompt) { return early }
        if let early = CommandFrames.earlyV3(prompt) { return early }

        // Reminders / tasks
        if lower.hasPrefix("remind me") || lower.contains("add a task") || lower.contains("add task")
            || lower.hasPrefix("todo") || lower.hasPrefix("i need to") {
            var title = strip(prompt, prefixes: ["remind me to", "remind me", "add a task to", "add a task:", "add task", "todo:", "todo", "i need to"])
            var args: [String: String] = [:]
            // A repeat rule ("every other Thursday") leaves the title first,
            // then the one-off date phrase the parser actually used.
            if let rule = Recurrence.phrase(in: title) {
                args["repeats"] = rule
                title = removeSuffix(title, rule)
            }
            if let date = NaturalDateParser.match(title) {
                title = removeSuffix(title, date.phrase)
                args["due"] = date.phrase
            }
            args["title"] = sentenceCase(title.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)))
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

        // Reminders export (opt-in integration). Before the command frames,
        // so "push today's list to Apple Reminders" is not a reschedule.
        if lower.contains("reminders app") || lower.contains("to reminders") || lower.contains("into reminders")
            || lower.contains("to apple reminders") {
            let scope: String
            if lower.contains("overdue") { scope = "overdue" }
            else if lower.contains("week") || lower.contains("upcoming") { scope = "upcoming" }
            else if lower.contains("all ") || lower.contains("everything") || lower.contains("every task") { scope = "all" }
            else { scope = "today" }
            return ParsedIntent(tool: "exportToReminders", arguments: ["scope": scope])
        }

        // Command frames (v0.3 constructions first): new tools and rewordings.
        if let frame = CommandFrames.commands(prompt) { return frame }

        // Ask your notes (cited Q&A) — before the agenda's "what do i…".
        if let question = askNotesQuestion(prompt) {
            return ParsedIntent(tool: "askNotes", arguments: ["question": question])
        }

        // Calendar context (opt-in integration)
        if let window = calendarWindow(lower) {
            return ParsedIntent(tool: "calendarAgenda", arguments: ["window": window])
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

        // Lemma-driven fallback before giving up.
        if let paraphrase = CommandFrames.paraphrase(prompt) { return paraphrase }

        // A factual question nothing claimed is a question for the notes.
        if let question = CommandFrames.questionFallback(prompt) { return question }

        // Default: the agenda, with an honest note about the floor mode.
        return ParsedIntent(tool: "agenda", isDefault: true)
    }

    /// "undo", "undo that", "revert the last step", "take that back".
    static func parseUndo(_ lower: String) -> ParsedIntent? {
        let trimmed = lower.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let starts = ["undo", "revert", "take that back", "take it back", "roll that back",
                      "roll it back", "roll back", "nevermind, undo", "never mind, undo",
                      "never mind undo", "scratch that", "put that back", "put it back",
                      "change that back", "change it back", "set that back", "set it back"]
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
                        "what did i note about", "check my notes for", "from my notes,",
                        "what did we decide about", "what did i decide about", "what have we decided about"]
        guard let prefix = prefixes.first(where: { lower.hasPrefix($0) }) else { return nil }
        let rest = String(prompt.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return rest.isEmpty ? nil : rest
    }

    /// "what's my afternoon look like", "what's on my calendar tomorrow",
    /// "any meetings this morning", "my schedule today" → the window phrase.
    static func calendarWindow(_ lower: String) -> String? {
        let cues = ["calendar", "meeting", "my schedule", "look like", "looking like", "busy",
                    "am i free", "free time", "events today", "events tomorrow"]
        guard cues.contains(where: { lower.contains($0) }), !lower.contains("reschedule") else { return nil }
        var window = lower.contains("tomorrow") ? "tomorrow" : "today"
        for part in ["morning", "afternoon", "evening", "tonight"] where lower.contains(part) {
            window = window == "tomorrow" ? "tomorrow \(part)" : "this \(part)"
        }
        return window
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
        NaturalDateParser.match(prompt)?.phrase ?? prompt
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
