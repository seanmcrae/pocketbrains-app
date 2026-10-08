import Foundation

/// Slot-based intent frames for the deterministic brain (v0.2).
///
/// A frame is a pattern over the lowercased clause with named slots (task,
/// date, shift, priority, rule, project, text). Matching happens on a
/// lowercased copy; slot values are cut from the ORIGINAL text by offset so
/// titles keep their capitalization. Frames run in three tiers:
///   1. `beforeCapture` — phrasings the v0.1 capture rules would mis-read
///      ("remind me about X later" is a snooze, not a new task);
///   2. `commands` — the documented grammar of the v0.2 tools plus common
///      rewordings of v0.1 intents;
///   3. `paraphrase` — a lemma-driven fallback: the first verb whose lemma
///      is in the `Lexicon` decides the intent, and the slots around it are
///      filled the same way.
enum CommandFrames {
    // MARK: - Regex helper

    /// Match `pattern` against the lowercased text; return capture groups cut
    /// from the original text (trimmed), "" for groups that didn't take part.
    static func match(_ pattern: String, _ text: String) -> [String]? {
        let lower = text.lowercased()
        guard (lower as NSString).length == (text as NSString).length,
              let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = lower as NSString
        guard let m = regex.firstMatch(in: lower, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let original = text as NSString
        return (1..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            guard r.location != NSNotFound else { return "" }
            return original.substring(with: r)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "?!.,;:'\"‘’“”")))
        }
    }

    static func clean(_ prompt: String) -> String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "?!.")))
    }

    static let politeness = #"^(?:(?:hey|ok|okay|so),?\s+)?(?:(?:can|could|would) you\s+|please\s+)?"#

    // MARK: - Slots

    /// Title, due phrase and repeat phrase from free text such as
    /// "take out the bins every other Thursday" or "'file taxes' for end of month".
    static func taskSlots(_ raw: String) -> [String: String] {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var args: [String: String] = [:]
        if let rule = Recurrence.phrase(in: title) {
            args["repeats"] = rule
            title = IntentGrammar.removeSuffix(title, rule)
        }
        if let date = NaturalDateParser.match(title) {
            args["due"] = date.phrase
            title = IntentGrammar.removeSuffix(title, date.phrase)
        }
        for filler in [" to my list", " on my list", " to my to-do list", " on my to-do list",
                       " to my todo list", " on my todo list", " please", " for me"]
        where title.lowercased().hasSuffix(filler) {
            title = String(title.dropLast(filler.count))
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "?!.,'\"‘’“”")))
        args["title"] = IntentGrammar.sentenceCase(title)
        return args
    }

    static func priorityWord(_ text: String) -> String? {
        TaskPriority.parse(text).map { $0.label.lowercased() }
    }

    // MARK: - Tier 1: before the capture rules

    static func beforeCapture(_ prompt: String) -> ParsedIntent? {
        let text = clean(prompt)
        if let g = match(#"^remind me (?:about|of) (.+?) (?:later|another time|some other time)$"#, text) {
            return ParsedIntent(tool: "snoozeTask", arguments: ["query": g[0]])
        }
        if let g = match(politeness + #"don'?t let me forget (?:to )?(.+)$"#, text) {
            return ParsedIntent(tool: "createTask", arguments: taskSlots(g[0]))
        }
        // "Every Friday I need to send the timesheet"
        if let g = match(#"^((?:every|each) (?:other )?\w+(?: (?:morning|afternoon|evening))?),? (?:i|we) (?:need|have|want|ought|should|must)(?: to)? (.+)$"#, text) {
            var args = taskSlots(g[1])
            args["repeats"] = g[0]
            if args["due"] == nil, let date = NaturalDateParser.match(g[0]) { args["due"] = date.phrase }
            return ParsedIntent(tool: "createTask", arguments: args)
        }
        return nil
    }

    // MARK: - Tier 2: commands

    static func commands(_ prompt: String) -> ParsedIntent? {
        if let v3 = commandsV3(prompt) { return v3 }
        let text = clean(prompt)
        let lower = text.lowercased()

        // Snooze
        if let g = match(politeness + #"(?:snooze|hold off on|defer) (.+?)(?:\s+(for|until|till)\s+(.+))?$"#, text) {
            var args = ["query": g[0]]
            if !g[2].isEmpty { args["until"] = g[1] == "for" ? g[2] : "until " + g[2] }
            return ParsedIntent(tool: "snoozeTask", arguments: args)
        }

        // Reschedule: "<verb> X to <date>" / "<verb> X by <shift>"
        if let g = match(politeness + #"(?:reschedule|move|push|postpone|delay|bump|shift|slide) (.+?)(?: back| forward| out)? (to|until|till|by|for) (.+)$"#, text) {
            if g[1] == "by" || (g[1] == "for" && NaturalDateParser.shift(in: g[2]) != nil && NaturalDateParser.match(g[2]) == nil) {
                return ParsedIntent(tool: "rescheduleTask", arguments: ["query": g[0], "by": g[2]])
            }
            return ParsedIntent(tool: "rescheduleTask", arguments: ["query": g[0], "to": g[2]])
        }

        // Priority
        if let g = match(politeness + #"(?:set|change) (?:the )?priority (?:of|for|on) (.+?) to (.+)$"#, text),
           let level = priorityWord(g[1]) {
            return ParsedIntent(tool: "setPriority", arguments: ["query": g[0], "priority": level])
        }
        if let g = match(politeness + #"(?:make|mark) (.+?) (?:as )?(?:an? )?((?:urgent|important|critical)|(?:top|high|low|normal|medium) priority)$"#, text),
           let level = priorityWord(g[1]) {
            return ParsedIntent(tool: "setPriority", arguments: ["query": g[0], "priority": level])
        }
        if let g = match(#"^(?:the )?(.+?) is (?:now )?(?:a |the )?(top|high|low|normal|urgent)(?: priority)?$"#, text),
           let level = priorityWord(g[1]) {
            return ParsedIntent(tool: "setPriority", arguments: ["query": g[0], "priority": level])
        }
        if let g = match(politeness + #"de-?prioriti[sz]e (.+)$"#, text) {
            return ParsedIntent(tool: "setPriority", arguments: ["query": g[0], "priority": "low"])
        }
        if let g = match(politeness + #"prioriti[sz]e (.+)$"#, text) {
            return ParsedIntent(tool: "setPriority", arguments: ["query": g[0], "priority": "high"])
        }

        // Recurrence on an existing task
        if let g = match(politeness + #"make (.+?) (?:repeat|recur)(?: itself)? (.+)$"#, text) {
            return ParsedIntent(tool: "setRecurrence", arguments: ["query": g[0], "rule": g[1]])
        }
        if let g = match(politeness + #"stop (?:repeating|recurring) (.+)$"#, text) {
            return ParsedIntent(tool: "setRecurrence", arguments: ["query": g[0], "rule": "none"])
        }
        if let g = match(#"^(?:the )?(.+?) should (?:be \w+ |repeat |recur |happen )?((?:every|each) .+|daily|weekly|weekdays)$"#, text),
           Recurrence.parse(g[1]) != nil {
            return ParsedIntent(tool: "setRecurrence", arguments: ["query": g[0], "rule": g[1]])
        }
        if let g = match(#"^i(?:'d| would)? (?:want|need|have|like|love) to (.+)$"#, text),
           Recurrence.phrase(in: g[0]) != nil {
            return ParsedIntent(tool: "createTask", arguments: taskSlots(g[0]))
        }

        // Milestones
        if let g = match(politeness + #"add (?:a |another )?milestone (?:called |named )?(.+?) (?:to|for) (.+?)(?: (?:by|due|on|for) (.+))?$"#, text) {
            var args = ["title": IntentGrammar.sentenceCase(g[0]), "project": g[1]]
            if !g[2].isEmpty { args["target"] = g[2] }
            return ParsedIntent(tool: "addMilestone", arguments: args)
        }
        if let g = match(politeness + #"add (?:a |another )?milestone (?:called |named )?(.+?)(?: (?:by|due|on) (.+))?$"#, text) {
            var args = ["title": IntentGrammar.sentenceCase(g[0]), "project": ""]
            if !g[1].isEmpty { args["target"] = g[1] }
            return ParsedIntent(tool: "addMilestone", arguments: args)
        }
        if let g = match(politeness + #"(?:list|show)(?: me)? (?:the |all )?milestones (?:for|of|in|on) (.+)$"#, text)
            ?? match(#"^what are (?:the )?milestones (?:for|of|in|on) (.+)$"#, text)
            ?? match(#"^what milestones (?:does|do|has) (.+?) (?:have|got)$"#, text) {
            return ParsedIntent(tool: "listMilestones", arguments: ["project": g[0]])
        }

        // Append to a note
        if let g = match(politeness + #"(?:append|add) to (?:the |my )?(.+?)(?: note)?: (.+)$"#, text) {
            return ParsedIntent(tool: "appendNote", arguments: ["query": g[0], "text": g[1]])
        }
        if let g = match(politeness + #"add (?:the |this |that )?(.+?) to (?:the |my )?(.+?) note$"#, text) {
            return ParsedIntent(tool: "appendNote", arguments: ["query": g[1], "text": g[0]])
        }

        // Search across everything
        if let g = match(politeness + #"search (?:everything|all|across everything|my whole library) for (.+)$"#, text)
            ?? match(politeness + #"look up (?:anything |everything )?(?:about |on |for )?(.+)$"#, text) {
            return ParsedIntent(tool: "searchEverything", arguments: ["query": g[0]])
        }

        // Completion rewordings
        if let g = match(#"^(?:i'?m |i am |we'?re )?(?:all )?done with (.+)$"#, text)
            ?? match(#"^(?:i |we )(?:'ve |have )?(?:just )?(?:finished|completed|crossed off|closed out) (.+)$"#, text)
            ?? match(#"^crossed off (.+)$"#, text)
            ?? match(politeness + #"mark (.+?) (?:as )?(?:done|complete|completed|finished)$"#, text) {
            return ParsedIntent(tool: "completeTask", arguments: ["query": stripArticle(g[0])])
        }

        // Task capture rewordings: "add X to my list", "put X on my list"
        if let g = match(politeness + #"(?:add|put|stick|pop|throw|chuck) (.+?) (?:to|on|onto) (?:my |the )?(?:list|to-?do list|todo list|todos|tasks)(.*)$"#, text) {
            return ParsedIntent(tool: "createTask", arguments: taskSlots(g[0] + " " + g[1]))
        }

        // Task lists by filter
        let asksToList = lower.hasPrefix("show") || lower.hasPrefix("list") || lower.hasPrefix("which")
            || lower.hasPrefix("what") || lower.hasPrefix("any") || lower.hasPrefix("are there")
        if asksToList, !lower.contains("calendar"), !lower.contains("meeting") {
            if lower.contains("overdue") || lower.contains("past due") {
                return ParsedIntent(tool: "queryTasks", arguments: ["filter": "overdue"])
            }
            if lower.contains("coming up") || lower.contains("upcoming") || lower.contains("this week") {
                return ParsedIntent(tool: "queryTasks", arguments: ["filter": "upcoming"])
            }
        }

        // Project progress: "how is X going", "how's X coming along"
        if let g = match(#"^how(?:'s| is| are) (?:the |my |our )?(.+?) (?:going|coming along|doing|progressing|looking)$"#, text),
           !["morning", "afternoon", "evening", "day", "week", "today", "tomorrow"].contains(where: { g[0].lowercased().contains($0) }) {
            return ParsedIntent(tool: "projectStatus", arguments: ["name": g[0]],
                                fallback: [ParsedIntent(tool: "agenda")])
        }

        // Note capture rewordings
        if let g = match(politeness + #"(?:write down|make a note|note down)(?: that)?:? (.+)$"#, text) {
            let body = g[0]
            return ParsedIntent(tool: "createNote", arguments: [
                "title": IntentGrammar.sentenceCase(String(body.prefix(48))), "body": body])
        }

        // Linking rewordings
        if let g = match(politeness + #"(?:tie|associate|connect) (.+?) (?:to|with) (.+)$"#, text) {
            return ParsedIntent(tool: "linkItems", arguments: ["from": g[0], "to": g[1]])
        }
        return nil
    }

    static func stripArticle(_ text: String) -> String {
        for article in ["the ", "my ", "our "] where text.lowercased().hasPrefix(article) {
            return String(text.dropFirst(article.count))
        }
        return text
    }

    // MARK: - Tier 3: lemma-driven paraphrase fallback

    /// Decide by the first verb whose lemma is in the lexicon, then fill the
    /// slots around it. Returns nil when no lexicon verb is present.
    static func paraphrase(_ prompt: String) -> ParsedIntent? {
        let text = clean(prompt)
        let tokens = Lexicon.tokens(text)
        guard case let (action, index)? = Lexicon.firstAction(in: tokens) else { return nil }
        // Everything after the verb (and a following particle) is the object.
        var start = tokens[index].range.upperBound
        if index + 1 < tokens.count, ["off", "up", "out", "back", "down", "about", "in"].contains(tokens[index + 1].word) {
            start = tokens[index + 1].range.upperBound
        }
        let object = String(text[start...]).trimmingCharacters(in: .whitespaces)
        guard !object.isEmpty || action == .undo else { return nil }

        func split(_ object: String, on preps: [String]) -> (String, String, String)? {
            let lower = object.lowercased()
            for prep in preps {
                if let r = lower.range(of: " \(prep) ") {
                    let offset = lower.distance(from: lower.startIndex, to: r.lowerBound)
                    let end = lower.distance(from: lower.startIndex, to: r.upperBound)
                    let head = String(object.prefix(offset))
                    let tail = String(object.dropFirst(end))
                    return (head, prep, tail)
                }
            }
            return nil
        }

        switch action {
        case .complete:
            // "tick the invoice off": a particle after the object is not part of it.
            var query = object
            for particle in [" off", " out", " up"] where query.lowercased().hasSuffix(particle) {
                query = String(query.dropLast(particle.count))
            }
            return ParsedIntent(tool: "completeTask", arguments: ["query": stripArticle(query)])
        case .reschedule:
            if case let (head, prep, tail)? = split(object, on: ["to", "until", "till", "by", "for"]) {
                let key = prep == "by" ? "by" : "to"
                return ParsedIntent(tool: "rescheduleTask", arguments: ["query": head, key: tail])
            }
            return nil
        case .snooze:
            if case let (head, prep, tail)? = split(object, on: ["until", "till", "for"]) {
                return ParsedIntent(tool: "snoozeTask",
                                    arguments: ["query": head, "until": prep == "for" ? tail : "until " + tail])
            }
            return ParsedIntent(tool: "snoozeTask", arguments: ["query": object])
        case .prioritize:
            return ParsedIntent(tool: "setPriority", arguments: ["query": object, "priority": "high"])
        case .deprioritize:
            return ParsedIntent(tool: "setPriority", arguments: ["query": object, "priority": "low"])
        case .create:
            let body = object.lowercased().hasPrefix("me to ") ? String(object.dropFirst(6))
                : object.lowercased().hasPrefix("to ") ? String(object.dropFirst(3)) : object
            return ParsedIntent(tool: "createTask", arguments: taskSlots(body))
        case .note:
            var body = object
            for lead in ["down that ", "down ", "that "] where body.lowercased().hasPrefix(lead) {
                body = String(body.dropFirst(lead.count)); break
            }
            return ParsedIntent(tool: "createNote", arguments: [
                "title": IntentGrammar.sentenceCase(String(body.prefix(48))), "body": body])
        case .search:
            var query = object
            for lead in ["for ", "up ", "everything about ", "anything about "] where query.lowercased().hasPrefix(lead) {
                query = String(query.dropFirst(lead.count))
            }
            return ParsedIntent(tool: "searchEverything", arguments: ["query": query])
        case .link:
            if case let (head, _, tail)? = split(object, on: ["to", "with"]) {
                return ParsedIntent(tool: "linkItems", arguments: ["from": head, "to": tail])
            }
            return nil
        case .undo:
            return ParsedIntent(tool: "undo", arguments: ["scope": "turn"])
        }
    }
}
