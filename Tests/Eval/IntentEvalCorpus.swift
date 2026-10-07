import Foundation

/// SYNTHETIC evaluation corpus for the deterministic intent router (the
/// fallback brain). Every utterance was written for this eval; none comes
/// from real users or personal data. Entity names refer to the synthetic
/// fixture seeded by `IntentRouterEval.seed(_:)`.
///
/// - `canonical`: phrasings the fallback documents or teaches in-app
///   ("remind me to…", "what's blocking…", "summarize my notes…").
/// - `paraphrase`: natural rewordings outside that grammar. These measure
///   how far the floor degrades when the language model is unavailable.
struct IntentEvalCase {
    enum Category: String, CaseIterable { case canonical, paraphrase }
    enum Due: Equatable { case undated, daysFromToday(Int), nextWeekday(Int) } // weekday: 1 = Sunday

    let utterance: String
    let category: Category
    let tool: String
    /// Expected created title (createTask / createProject), compared case-insensitively.
    var title: String? = nil
    /// Expected due date for createTask.
    var due: Due? = nil
    /// Fixture task that must be marked done (completeTask).
    var completes: String? = nil
}

enum IntentEvalCorpus {
    static let cases: [IntentEvalCase] = [
        // MARK: Canonical: tasks
        .init(utterance: "Remind me to send the invoice Friday", category: .canonical,
              tool: "createTask", title: "Send the invoice", due: .nextWeekday(6)),
        .init(utterance: "Remind me to call the bank tomorrow", category: .canonical,
              tool: "createTask", title: "Call the bank", due: .daysFromToday(1)),
        .init(utterance: "Remind me to water the plants today", category: .canonical,
              tool: "createTask", title: "Water the plants", due: .daysFromToday(0)),
        .init(utterance: "Remind me to back up the laptop in 3 days", category: .canonical,
              tool: "createTask", title: "Back up the laptop", due: .daysFromToday(3)),
        .init(utterance: "Remind me to finish the quarterly deck by Thursday", category: .canonical,
              tool: "createTask", title: "Finish the quarterly deck", due: .nextWeekday(5)),
        .init(utterance: "Remind me to check the status of the website", category: .canonical,
              tool: "createTask", title: "Check the status of the website", due: .undated),
        .init(utterance: "Add a task to renew the car insurance", category: .canonical,
              tool: "createTask", title: "Renew the car insurance", due: .undated),
        .init(utterance: "Todo: order new business cards", category: .canonical,
              tool: "createTask", title: "Order new business cards", due: .undated),
        .init(utterance: "I need to email the landlord on Monday", category: .canonical,
              tool: "createTask", title: "Email the landlord", due: .nextWeekday(2)),

        // MARK: Canonical: completion
        .init(utterance: "Finish book flights", category: .canonical,
              tool: "completeTask", completes: "Book flights for the offsite"),
        .init(utterance: "Complete write launch copy", category: .canonical,
              tool: "completeTask", completes: "Write launch copy"),
        .init(utterance: "Check off renew passport", category: .canonical,
              tool: "completeTask", completes: "Renew passport"),

        // MARK: Canonical: agenda, status, blockers
        .init(utterance: "What's on my agenda?", category: .canonical, tool: "agenda"),
        .init(utterance: "What needs my attention today?", category: .canonical, tool: "agenda"),
        .init(utterance: "What do I have due today?", category: .canonical, tool: "agenda"),
        .init(utterance: "What's blocking the website redesign?", category: .canonical, tool: "projectStatus"),
        .init(utterance: "Status of Q3 planning", category: .canonical, tool: "projectStatus"),
        .init(utterance: "What's blocked?", category: .canonical, tool: "queryTasks"),

        // MARK: Canonical: notes and knowledge
        .init(utterance: "Note: the vendor prefers invoices as PDF", category: .canonical, tool: "createNote"),
        .init(utterance: "Jot down that the offsite venue holds 40 people", category: .canonical, tool: "createNote"),
        .init(utterance: "Take a note: pricing page needs an annual toggle", category: .canonical, tool: "createNote"),
        .init(utterance: "Summarize my notes from yesterday", category: .canonical, tool: "notesFrom"),
        .init(utterance: "Give me a summary of today's notes", category: .canonical, tool: "notesFrom"),
        .init(utterance: "Find notes about pricing", category: .canonical, tool: "searchNotes"),
        .init(utterance: "Search for brand voice", category: .canonical, tool: "searchNotes"),
        .init(utterance: "Link brand voice to website redesign", category: .canonical, tool: "linkItems"),
        .init(utterance: "When did I book flights?", category: .canonical, tool: "recall"),

        // MARK: Canonical: projects
        .init(utterance: "New project called Kitchen renovation", category: .canonical,
              tool: "createProject", title: "Kitchen renovation"),
        .init(utterance: "Start a project called Home gym", category: .canonical,
              tool: "createProject", title: "Home gym"),

        // MARK: Paraphrases outside the documented grammar
        .init(utterance: "Can you add buy groceries to my list for tomorrow?", category: .paraphrase,
              tool: "createTask", title: "Buy groceries", due: .daysFromToday(1)),
        .init(utterance: "Don't let me forget to pay rent on Friday", category: .paraphrase,
              tool: "createTask", title: "Pay rent", due: .nextWeekday(6)),
        .init(utterance: "I finished the launch copy", category: .paraphrase,
              tool: "completeTask", completes: "Write launch copy"),
        .init(utterance: "Done with renew passport", category: .paraphrase,
              tool: "completeTask", completes: "Renew passport"),
        .init(utterance: "Show me everything that's overdue", category: .paraphrase, tool: "queryTasks"),
        .init(utterance: "How is the website redesign going?", category: .paraphrase, tool: "projectStatus"),
        .init(utterance: "Notes about pricing", category: .paraphrase, tool: "searchNotes"),
        .init(utterance: "Write down that the client wants a demo next week", category: .paraphrase, tool: "createNote"),
        .init(utterance: "Connect pricing research to Q3 planning", category: .paraphrase, tool: "linkItems"),
        .init(utterance: "Push send the invoice to Monday", category: .paraphrase, tool: "updateTask"),
        .init(utterance: "Add a milestone Beta launch to website redesign", category: .paraphrase, tool: "addMilestone"),
    ]
}
