import Foundation

/// v0.3 frames for the deterministic brain: general constructions people
/// use instead of commands, written against the v0.3 *dev* paraphrase split
/// (the held-out split is never itemized, so it cannot steer these).
///
/// Each frame is a construction rather than a sentence:
///   - statements of state: "the gutters are clean", "that's the passport
///     sorted", "the invoice is really important", "X is now due Monday";
///   - subject-first requests: "can the invoice slip to Thursday";
///   - a reminder asked for as a noun: "can I get a reminder to …";
///   - labelled captures: "Task: …", "Idea: …", "FYI: …";
///   - past-tense reports of work: "paid the water bill";
///   - quoted text placed into a named note: "tack 'X' onto the meeting notes".
extension CommandFrames {
    // MARK: - Discourse

    /// Drop leading interjections that carry no intent ("Wait, put that
    /// back", "Not now, remind me …", "Morning! What's on today?"). Only
    /// when followed by punctuation, so "so I need to…" is left alone.
    static func stripDiscourse(_ prompt: String) -> String {
        let pattern = #"^\s*(?:not now|wait|ok|okay|hey|hi|morning|good morning|so|um|actually|right)\s*[,!.:;]+\s*"#
        var text = prompt
        while let r = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            text = String(text[r.upperBound...])
        }
        return text.isEmpty ? prompt : text
    }

    // MARK: - Before the capture rules

    static func earlyV3(_ prompt: String) -> ParsedIntent? {
        let text = clean(prompt)

        // "Remind me what the brand voice guidelines say": a question, not a task.
        if let g = match(#"^remind me (what|who|when|where|which|how|why) (.+)$"#, text) {
            return ParsedIntent(tool: "askNotes", arguments: ["question": g[0] + " " + g[1]])
        }
        // "Remind me about the passport tomorrow": move an existing task;
        // if there is none, capture it instead.
        if let g = match(#"^remind me (?:about|of) (.+)$"#, text),
           let date = NaturalDateParser.match(g[0]) {
            let query = IntentGrammar.removeSuffix(g[0], date.phrase)
            if !query.isEmpty, query.count < g[0].count {
                return ParsedIntent(tool: "snoozeTask", arguments: ["query": stripArticle(query), "until": date.phrase],
                                    fallback: [ParsedIntent(tool: "createTask", arguments: taskSlots(g[0]))])
            }
        }
        // "Ping me tomorrow to chase the refund": a date between "me" and "to".
        if let g = match(#"^(?:remind|ping|nudge|buzz) me (.+?) to (.+)$"#, text),
           let date = NaturalDateParser.match(g[0]), date.phrase.count + 4 >= g[0].count {
            return ParsedIntent(tool: "createTask", arguments: taskSlots(g[1] + " " + g[0]))
        }
        if let g = match(#"^(?:ping|nudge|buzz) me (?:to|about) (.+)$"#, text) {
            return ParsedIntent(tool: "createTask", arguments: taskSlots(g[0]))
        }
        // "Can I get a reminder to cancel the trial in 5 days".
        if let g = match(#"^(?:can i (?:get|have)|could i (?:get|have)|give me|i'?d like|i want) (?:a |an )?(?:reminder|task|to-?do)(?: for me)? (?:to |about |for |: ?)(.+)$"#, text) {
            return ParsedIntent(tool: "createTask", arguments: taskSlots(g[0]))
        }
        // Labelled captures: "Task: renew the permit", "Idea: run a referral programme".
        if let g = match(#"^(?:task|to-?do|reminder)\s*:\s*(.+)$"#, text) {
            return ParsedIntent(tool: "createTask", arguments: taskSlots(g[0]))
        }
        if let g = match(#"^(?:idea|thought|memo|fyi|for later|fyi for later|for the record)\s*:\s*(.+)$"#, text) {
            return noteIntent(g[0])
        }
        // "Keep in mind the client is on holiday in August".
        if let g = match(#"^(?:keep|bear) in mind(?: that)?:? (.+)$"#, text) {
            return noteIntent(g[0])
        }
        return nil
    }

    static func noteIntent(_ body: String) -> ParsedIntent {
        ParsedIntent(tool: "createNote", arguments: [
            "title": IntentGrammar.sentenceCase(String(body.prefix(48))), "body": body])
    }

    // MARK: - Commands (run before the v0.2 command frames)

    static let pastTenseTaskVerbs: [String: String] = [
        "paid": "pay", "sent": "send", "booked": "book", "wrote": "write", "built": "build",
        "renewed": "renew", "cleaned": "clean", "drafted": "draft", "filed": "file",
        "submitted": "submit", "called": "call", "emailed": "email", "bought": "buy",
        "ordered": "order", "fixed": "fix", "finished": "", "completed": "",
    ]

    static func commandsV3(_ prompt: String) -> ParsedIntent? {
        let text = clean(prompt)
        let lower = text.lowercased()

        // Priority by target level: "raise the passport to high priority".
        if let g = match(politeness + #"(?:raise|move|set|change|put|drop) (?:(?:the )?priority (?:of|on|for) )?(.+?) to (?:an? )?(urgent|high|low|normal|medium|top)(?: priority)?$"#, text),
           let level = priorityWord(g[1]) {
            return ParsedIntent(tool: "setPriority", arguments: ["query": stripArticle(g[0]), "priority": level])
        }
        // Priority as a statement: "the invoice is really important",
        // "gutters aren't a priority".
        if let g = match(#"^(?:the |my )?(.+?) (?:is|are|'s|’s) (?:really |very |super |quite |now )?(important|critical|urgent)$"#, text),
           let level = priorityWord(g[1]) {
            return ParsedIntent(tool: "setPriority", arguments: ["query": g[0], "priority": level])
        }
        if let g = match(#"^(?:the |my )?(.+?) (?:isn'?t|aren'?t|is not|are not) (?:a |that |very |really )?(?:priority|important|urgent)$"#, text) {
            return ParsedIntent(tool: "setPriority", arguments: ["query": g[0], "priority": "low"])
        }

        // Rescheduling statements and subject-first requests.
        if let g = match(#"^(?:the |my )?(.+?) (?:is|'s|’s) (?:now )?due (?:on |by )?(.+)$"#, text),
           !["what", "which", "who", "anything", "everything", "nothing", "something", "when", "what's"]
               .contains(g[0].lowercased()) {
            return ParsedIntent(tool: "rescheduleTask", arguments: ["query": g[0], "to": g[1]])
        }
        if let g = match(#"^(?:can|could|should) (?:the |my )?(.+?) (?:slip|slide|shift|move|go) (?:back |out )?(?:to|until|till) (.+)$"#, text) {
            return ParsedIntent(tool: "rescheduleTask", arguments: ["query": g[0], "to": g[1]])
        }
        if let g = match(politeness + #"(?:bring|pull|move) (.+?) forward (?:to|until|till) (.+)$"#, text) {
            return ParsedIntent(tool: "rescheduleTask", arguments: ["query": stripArticle(g[0]), "to": g[1]])
        }
        // A shift with no preposition: "kick the report out a couple of days".
        if let g = match(politeness + #"(?:kick|push|move|shift|slide|delay|postpone) (.+?)(?: out| back| along| forward)?(?: by)? ((?:a couple of|couple of|a few|an?|one|two|three|four|five|six|seven|\d+) (?:days?|weeks?))$"#, text) {
            return ParsedIntent(tool: "rescheduleTask", arguments: ["query": stripArticle(g[0]), "by": g[1]])
        }

        // Completion as a statement: "that's the passport sorted",
        // "the gutters are clean", "launch copy's written".
        let finished = "done|finished|complete|completed|sorted|handled|taken care of"
        if let g = match(#"^(?:that'?s|that’s|that is) (?:the |my )?(.+?) (?:"# + finished + #")$"#, text) {
            return ParsedIntent(tool: "completeTask", arguments: ["query": g[0]])
        }
        if let g = match(#"^(?:the |my )?(.+?)(?:'s|’s| is| are|'re| has been| have been)(?: all| now)? (?:"# + finished + #"|clean|cleaned|written|paid|sent|booked|renewed|fixed|built)$"#, text) {
            return ParsedIntent(tool: "completeTask", arguments: ["query": g[0]])
        }
        // Past-tense report: "paid the water bill" → complete "pay the water bill".
        if let g = match(#"^(\w+) (.+)$"#, text), let base = pastTenseTaskVerbs[g[0].lowercased()] {
            let query = base.isEmpty ? stripArticle(g[1]) : base + " " + g[1]
            return ParsedIntent(tool: "completeTask", arguments: ["query": query])
        }

        // Recurrence on an existing task.
        if let g = match(#"^(?:the |my )?(.+?) (?:comes? (?:round|around|up)|recurs|repeats|happens|needs doing) (?:once )?((?:every|each) .+|daily|weekly|fortnightly|bi-?weekly|weekdays)$"#, text),
           Recurrence.parse(g[1]) != nil {
            return ParsedIntent(tool: "setRecurrence", arguments: ["query": g[0], "rule": g[1]])
        }
        if let g = match(politeness + #"(?:turn off|switch off|disable|remove|cancel|stop|drop) (?:the )?(?:repeats?|recurrence|repeating|recurring)(?: on| for| of| from)? (?:the )?(.+)$"#, text) {
            return ParsedIntent(tool: "setRecurrence", arguments: ["query": g[0], "rule": "none"])
        }
        if let g = match(#"^(?:make |can |could |should )?(?:the |my )?(.+?) (?:be |become )?an? (daily|weekly|fortnightly|bi-?weekly|weekday) (?:job|task|thing|chore|habit)$"#, text) {
            let rule = g[1].lowercased() == "weekday" ? "weekdays" : g[1]
            return ParsedIntent(tool: "setRecurrence", arguments: ["query": g[0], "rule": rule])
        }

        // Quoted text into a named note: "tack 'Ana joins in March' onto the
        // meeting notes", "put 'parking is free' in the offsite plan note".
        if let g = match(politeness + #"(?:add|append|tack|put|stick|pop|include|write) ['"‘“](.+?)['"’”] (?:on|onto|in|into|to|at the end of) (?:the |my )?(.+?)(?: note| notes)?$"#, text) {
            return ParsedIntent(tool: "appendNote", arguments: ["query": g[1], "text": g[0]])
        }
        if let g = match(politeness + #"(?:append|tack|stick|pop) (.+?) (?:on|onto|in|into|to) (?:the |my )?(.+?) (?:note|notes)$"#, text) {
            return ParsedIntent(tool: "appendNote", arguments: ["query": g[1], "text": g[0]])
        }

        // Project status without a verb: "Q3 planning progress?",
        // "Website redesign: where do things stand?".
        if let g = match(#"^(.+?)\s*[:,–—-]\s*(?:where do things stand|where are we|how'?s it going|status|progress|any updates?)$"#, text)
            ?? match(#"^where do things stand (?:on|with) (?:the )?(.+)$"#, text)
            ?? match(#"^(?:the )?(.+?) (?:progress|status)$"#, text) {
            return ParsedIntent(tool: "projectStatus", arguments: ["name": g[0]],
                                fallback: [ParsedIntent(tool: "agenda")])
        }

        // Task lists by state: "what's still open?", "show stuck tasks".
        let asksToList = ["show", "list", "which", "what", "any", "are there"].contains { lower.hasPrefix($0) }
        if asksToList {
            if ["stuck", "held up", "waiting on"].contains(where: { lower.contains($0) }) {
                return ParsedIntent(tool: "queryTasks", arguments: ["filter": "blocked"])
            }
            if ["still open", "open tasks", "outstanding", "remaining", "left to do", "still to do"].contains(where: { lower.contains($0) }) {
                return ParsedIntent(tool: "queryTasks", arguments: ["filter": "all"])
            }
        }

        // Notes: decisions, search, a day's notes.
        if match(#"^(?:did|have) (?:we|i) (?:decide|agree|settle|conclude)d?\b.*$"#, text) != nil {
            return ParsedIntent(tool: "askNotes", arguments: ["question": text])
        }
        if let g = match(politeness + #"(?:pull up|bring up|dig up|show me|get me) (?:everything|anything|all) (?:on|about|for|related to) (.+)$"#, text) {
            return ParsedIntent(tool: "searchEverything", arguments: ["query": g[0]])
        }
        if let g = match(politeness + #"(?:grep|scan|look through|dig through|go through|comb through|comb) (?:my |the |all (?:my )?)?notes (?:for|about|on) (.+)$"#, text) {
            return ParsedIntent(tool: "searchNotes", arguments: ["query": g[0]])
        }
        if let g = match(#"\b(yesterday|today)(?:'s|’s) notes\b"#, text) {
            return ParsedIntent(tool: "notesFrom", arguments: ["day": g[0].lowercased()])
        }

        // Milestones without a verb, and "put a <title> milestone on <project>".
        if let g = match(#"^(?:the )?milestones (?:for|of|on|in) (.+)$"#, text) {
            return ParsedIntent(tool: "listMilestones", arguments: ["project": g[0]])
        }
        if let g = match(politeness + #"(?:add|put|set|create) (?:a |an )?(.+?) milestone (?:on|to|for|in) (.+?)(?: (?:by|for|on|due) (.+))?$"#, text) {
            var args = ["title": IntentGrammar.sentenceCase(g[0]), "project": g[1]]
            if !g[2].isEmpty { args["target"] = g[2] }
            return ParsedIntent(tool: "addMilestone", arguments: args)
        }

        // Linking: "cross-reference brand voice with Q3 planning".
        if let g = match(politeness + #"(?:cross-?reference|cross reference|reference) (.+?) (?:with|to|against) (.+)$"#, text) {
            return ParsedIntent(tool: "linkItems", arguments: ["from": g[0], "to": g[1]])
        }

        // Projects: "spin up a project called Book club".
        if let g = match(politeness + #"(?:spin up|set up|start|create|make|kick off|open|begin) (?:a |an )?(?:new )?project (?:called|named) (.+)$"#, text) {
            return ParsedIntent(tool: "createProject", arguments: ["name": IntentGrammar.sentenceCase(g[0])])
        }

        // Capture with a modal of necessity: "gotta book the car in…",
        // "need to pick up the passports on friday".
        if let g = match(#"^(?:(?:i|we)(?:'ve| have)? )?(?:need to|gotta|got to|have to|must) (.+)$"#, text) {
            return ParsedIntent(tool: "createTask", arguments: taskSlots(g[0]))
        }
        return nil
    }

    // MARK: - Last resort before the agenda

    /// A factual wh-question nothing else claimed ("what's the venue
    /// capacity?") is a question for the notes; one scoped to today or this
    /// week is a question about the agenda.
    static func questionFallback(_ prompt: String) -> ParsedIntent? {
        let text = clean(prompt)
        let lower = text.lowercased()
        let opener = #"^(?:what|what's|whats|what’s|who|who's|when|where|which|how many|how much|how long|why)\b"#
        guard lower.range(of: opener, options: .regularExpression) != nil else { return nil }
        if ["today", "tonight", "this week"].contains(where: { lower.contains($0) }) {
            return ParsedIntent(tool: "agenda")
        }
        return ParsedIntent(tool: "askNotes", arguments: ["question": text])
    }
}
