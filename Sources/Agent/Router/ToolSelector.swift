import Foundation

/// Per-request tool trimming for the Foundation Models brain.
///
/// The on-device model is offered every tool's schema on every request
/// (22, or 24 with both integrations on). `ToolSelector` picks a small,
/// relevant subset instead, deterministically and without a model:
///
/// 1. The intent grammar's own parse of the request (and of each clause of
///    a compound request) scores highest, with its fallbacks next.
/// 2. Lexicon verbs (matched on lemmas) vote for the tools of their action.
/// 3. Cue words (nouns and question forms such as "milestone", "overdue",
///    "according to my notes") vote for the tools they usually belong to.
/// 4. A date phrase votes for the date-taking tools.
///
/// The core tools are always offered, so a bad trim can still capture a
/// task, search, show the agenda or undo. Ties break by registry order, so
/// the same request always yields the same set.
enum ToolSelector {
    /// Always offered, whatever the request: capture, broad search, the
    /// agenda as a safe answer, and undo.
    static let coreTools: [String] = ["createTask", "searchEverything", "agenda", "undo"]

    /// Default number of tools offered per request, core tools included.
    static let defaultLimit = 8

    struct Selection: Equatable {
        /// Selected tool names, in `available` order.
        let tools: [String]
        /// Non-zero relevance scores, for tests and diagnostics.
        let scores: [String: Double]
    }

    static func select(_ request: String, available: [String], limit: Int = defaultLimit) -> Selection {
        let scores = score(request).filter { available.contains($0.key) }
        let core = coreTools.filter { available.contains($0) }
        let order = Dictionary(uniqueKeysWithValues: available.enumerated().map { ($1, $0) })
        let ranked = available
            .filter { !core.contains($0) && (scores[$0] ?? 0) > 0 }
            .sorted { lhs, rhs in
                let (a, b) = (scores[lhs] ?? 0, scores[rhs] ?? 0)
                return a != b ? a > b : order[lhs, default: 0] < order[rhs, default: 0]
            }
        let room = max(0, limit - core.count)
        let chosen = Set(core + ranked.prefix(room))
        return Selection(tools: available.filter { chosen.contains($0) }, scores: scores)
    }

    // MARK: - Scoring

    static func score(_ request: String) -> [String: Double] {
        var scores: [String: Double] = [:]
        func vote(_ tools: [String], _ weight: Double) {
            for tool in tools { scores[tool, default: 0] += weight }
        }

        // 1. Grammar: the deterministic brain's reading of the request.
        if let plan = CompoundPlanner.plan(request) {
            vote(plan.steps.map(\.tool), 10)
        }
        let parsed = IntentGrammar.parse(request)
        if !parsed.isDefault {
            vote([parsed.tool], 10)
            vote(parsed.fallback.map(\.tool), 5)
        }

        // 2. Lexicon verbs.
        let tokens = Lexicon.tokens(request)
        var actions = Set<Lexicon.Action>()
        for token in tokens {
            if let action = Lexicon.verbs[token.lemma] ?? Lexicon.verbs[token.word] {
                actions.insert(action)
            }
        }
        for action in actions { vote(tools(for: action), 3) }

        // 3. Cue words.
        let lower = " " + normalized(request) + " "
        for (cues, tools) in cueTable where cues.contains(where: { lower.contains($0) }) {
            vote(tools, 2)
        }

        // 4. Dates.
        if NaturalDateParser.match(request) != nil {
            vote(["createTask", "rescheduleTask", "snoozeTask"], 1)
        }
        return scores
    }

    /// Lowercased, with punctuation other than apostrophes and hyphens
    /// turned into spaces, so cues can match whole words at a sentence end.
    static func normalized(_ text: String) -> String {
        String(text.lowercased().map { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "-" ? $0 : " " })
    }

    static func tools(for action: Lexicon.Action) -> [String] {
        switch action {
        case .complete: return ["completeTask"]
        case .reschedule: return ["rescheduleTask", "updateTask"]
        case .snooze: return ["snoozeTask"]
        case .prioritize, .deprioritize: return ["setPriority"]
        case .create: return ["createTask", "createProject", "addMilestone"]
        case .note: return ["createNote", "appendNote"]
        case .search: return ["searchNotes", "searchEverything", "askNotes"]
        case .link: return ["linkItems"]
        case .undo: return ["undo"]
        }
    }

    /// Lowercased substrings (padded with spaces where a whole word is
    /// meant) and the tools they suggest. Ordinary vocabulary of each tool's
    /// job, not phrasings taken from the eval corpus.
    static let cueTable: [([String], [String])] = [
        ([" task", " todo", " to-do", " remind"], ["createTask", "queryTasks"]),
        ([" done", " finished", " complete", " tick", " cross"], ["completeTask"]),
        ([" due ", " deadline", " date "], ["rescheduleTask", "updateTask"]),
        ([" later", " snooze", " until "], ["snoozeTask"]),
        ([" priority", " urgent", " important", " critical"], ["setPriority"]),
        ([" repeat", " recur", " every ", " daily", " weekly", " weekdays", " fortnightly"],
         ["setRecurrence", "createTask"]),
        ([" overdue", " late ", " blocked", " stuck", " upcoming", " coming up", " open tasks", " still have"],
         ["queryTasks"]),
        ([" project"], ["createProject", "projectStatus"]),
        ([" status", " progress", " blocking", " blocker", " going", " stand", " update on"],
         ["projectStatus"]),
        ([" milestone"], ["listMilestones", "addMilestone"]),
        ([" note", " jot", " write down"], ["createNote", "appendNote", "searchNotes", "askNotes"]),
        ([" append", " add to the", " add to my"], ["appendNote"]),
        ([" my notes", " according to", " what did", " who ", " how many", " decide", " say about", " why "],
         ["askNotes"]),
        ([" find", " search", " look for", " look up", " anything about", " mention"],
         ["searchNotes", "searchEverything"]),
        ([" yesterday", " today's notes", " notes from"], ["notesFrom"]),
        ([" link", " connect", " relate", " attach", " tie "], ["linkItems"]),
        ([" agenda", " today", " attention", " focus", " my day"], ["agenda"]),
        ([" calendar", " meeting", " free ", " busy", " schedule", " afternoon", " morning", " evening"],
         ["calendarAgenda"]),
        ([" reminders"], ["exportToReminders"]),
        ([" when did", " did i", " have i", " remember when", " last time"], ["recall"]),
        ([" undo", " revert", " take that back", " scratch that"], ["undo"]),
    ]
}

/// Settings switch for per-request tool trimming on the Foundation Models
/// brain. Off by default until the trimmed set is measured on device.
enum ToolTrimming {
    static let defaultsKey = "pb.trimTools"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }
}
