import Foundation
@testable import PocketBrains

/// SYNTHETIC evaluation corpus for the deterministic intent router (the
/// fallback brain). Every utterance was written for this eval; none comes
/// from real users or personal data. Entity names refer to the synthetic
/// fixture seeded by `IntentRouterEval.seed(_:)`.
///
/// Splits:
/// - `canonical`: phrasings the fallback documents or teaches in-app
///   ("remind me to…", "what's blocking…", "reschedule X to…"). Gated at
///   100% in CI.
/// - `compound`: multi-step requests ("create a project…, add 3 tasks… and
///   link it…"), scored on the exact tool sequence plus state checks.
/// - `paraphrase`: natural rewordings outside that grammar. The router's
///   rules MAY be tuned against these ("dev" paraphrases).
/// - `heldout`: paraphrases written in one sitting and committed before the
///   router work of their release, never used to tune rules. Their misses
///   are not printed individually, so they can't leak into rule-writing.
///   Two held-out splits exist: "v0.2 held-out (reported)" (origin v2; its
///   score was published with v0.2, so it is frozen but no longer a clean
///   test) and "v0.3 held-out (frozen)" (origin v3, `HeldOutV3.swift`),
///   the honest generalization number from v0.3 on.
///
/// `origin` separates the original 40 utterances (v0.1), the v0.2 additions
/// and the v0.3 additions, so before/after can be reported per set.
struct IntentEvalCase {
    enum Category: String, CaseIterable { case canonical, compound, paraphrase, heldout }
    enum Origin: String { case v1, v2, v3 }
    enum Due: Equatable {
        case undated, daysFromToday(Int), nextWeekday(Int) // weekday: 1 = Sunday
        case endOfMonth
    }

    let utterance: String
    let category: Category
    let tool: String
    var origin: Origin = .v2
    /// Expected created title (createTask / createProject), compared case-insensitively.
    var title: String? = nil
    /// Expected due date for createTask.
    var due: Due? = nil
    /// Expected repeat rule (`Recurrence.raw`) of the created task.
    var repeats: String? = nil
    /// Fixture task that must be marked done (completeTask).
    var completes: String? = nil
    /// Fixture task whose state the request changes, and what it must become.
    var target: String? = nil
    var targetDue: Due? = nil
    /// Qualified: Swift Concurrency also declares a `TaskPriority`.
    var targetPriority: PocketBrains.TaskPriority? = nil
    /// `Recurrence.raw`, or "none" for no rule.
    var targetRepeats: String? = nil
    /// Compound requests: the exact tool sequence.
    var steps: [String]? = nil
    /// Compound requests: project every created task must be filed under.
    var createdIn: String? = nil
    /// Note (by title words) whose body must contain the text afterwards.
    var noteContains: (note: String, text: String)? = nil
}

enum IntentEvalCorpus {
    static let cases: [IntentEvalCase] = v1 + canonicalV2 + compound + paraphraseV2 + heldout + devV3 + heldoutV3

    // MARK: - v0.1 corpus (unchanged utterances and expectations)

    static let v1: [IntentEvalCase] = [
        // Canonical: tasks
        .init(utterance: "Remind me to send the invoice Friday", category: .canonical,
              tool: "createTask", origin: .v1, title: "Send the invoice", due: .nextWeekday(6)),
        .init(utterance: "Remind me to call the bank tomorrow", category: .canonical,
              tool: "createTask", origin: .v1, title: "Call the bank", due: .daysFromToday(1)),
        .init(utterance: "Remind me to water the plants today", category: .canonical,
              tool: "createTask", origin: .v1, title: "Water the plants", due: .daysFromToday(0)),
        .init(utterance: "Remind me to back up the laptop in 3 days", category: .canonical,
              tool: "createTask", origin: .v1, title: "Back up the laptop", due: .daysFromToday(3)),
        .init(utterance: "Remind me to finish the quarterly deck by Thursday", category: .canonical,
              tool: "createTask", origin: .v1, title: "Finish the quarterly deck", due: .nextWeekday(5)),
        .init(utterance: "Remind me to check the status of the website", category: .canonical,
              tool: "createTask", origin: .v1, title: "Check the status of the website", due: .undated),
        .init(utterance: "Add a task to renew the car insurance", category: .canonical,
              tool: "createTask", origin: .v1, title: "Renew the car insurance", due: .undated),
        .init(utterance: "Todo: order new business cards", category: .canonical,
              tool: "createTask", origin: .v1, title: "Order new business cards", due: .undated),
        .init(utterance: "I need to email the landlord on Monday", category: .canonical,
              tool: "createTask", origin: .v1, title: "Email the landlord", due: .nextWeekday(2)),

        // Canonical: completion
        .init(utterance: "Finish book flights", category: .canonical,
              tool: "completeTask", origin: .v1, completes: "Book flights for the offsite"),
        .init(utterance: "Complete write launch copy", category: .canonical,
              tool: "completeTask", origin: .v1, completes: "Write launch copy"),
        .init(utterance: "Check off renew passport", category: .canonical,
              tool: "completeTask", origin: .v1, completes: "Renew passport"),

        // Canonical: agenda, status, blockers
        .init(utterance: "What's on my agenda?", category: .canonical, tool: "agenda", origin: .v1),
        .init(utterance: "What needs my attention today?", category: .canonical, tool: "agenda", origin: .v1),
        .init(utterance: "What do I have due today?", category: .canonical, tool: "agenda", origin: .v1),
        .init(utterance: "What's blocking the website redesign?", category: .canonical, tool: "projectStatus", origin: .v1),
        .init(utterance: "Status of Q3 planning", category: .canonical, tool: "projectStatus", origin: .v1),
        .init(utterance: "What's blocked?", category: .canonical, tool: "queryTasks", origin: .v1),

        // Canonical: notes and knowledge
        .init(utterance: "Note: the vendor prefers invoices as PDF", category: .canonical, tool: "createNote", origin: .v1),
        .init(utterance: "Jot down that the offsite venue holds 40 people", category: .canonical, tool: "createNote", origin: .v1),
        .init(utterance: "Take a note: pricing page needs an annual toggle", category: .canonical, tool: "createNote", origin: .v1),
        .init(utterance: "Summarize my notes from yesterday", category: .canonical, tool: "notesFrom", origin: .v1),
        .init(utterance: "Give me a summary of today's notes", category: .canonical, tool: "notesFrom", origin: .v1),
        .init(utterance: "Find notes about pricing", category: .canonical, tool: "searchNotes", origin: .v1),
        .init(utterance: "Search for brand voice", category: .canonical, tool: "searchNotes", origin: .v1),
        .init(utterance: "Link brand voice to website redesign", category: .canonical, tool: "linkItems", origin: .v1),
        .init(utterance: "When did I book flights?", category: .canonical, tool: "recall", origin: .v1),

        // Canonical: projects
        .init(utterance: "New project called Kitchen renovation", category: .canonical,
              tool: "createProject", origin: .v1, title: "Kitchen renovation"),
        .init(utterance: "Start a project called Home gym", category: .canonical,
              tool: "createProject", origin: .v1, title: "Home gym"),

        // Paraphrases outside the v0.1 grammar
        .init(utterance: "Can you add buy groceries to my list for tomorrow?", category: .paraphrase,
              tool: "createTask", origin: .v1, title: "Buy groceries", due: .daysFromToday(1)),
        .init(utterance: "Don't let me forget to pay rent on Friday", category: .paraphrase,
              tool: "createTask", origin: .v1, title: "Pay rent", due: .nextWeekday(6)),
        .init(utterance: "I finished the launch copy", category: .paraphrase,
              tool: "completeTask", origin: .v1, completes: "Write launch copy"),
        .init(utterance: "Done with renew passport", category: .paraphrase,
              tool: "completeTask", origin: .v1, completes: "Renew passport"),
        .init(utterance: "Show me everything that's overdue", category: .paraphrase, tool: "queryTasks", origin: .v1),
        .init(utterance: "How is the website redesign going?", category: .paraphrase, tool: "projectStatus", origin: .v1),
        .init(utterance: "Notes about pricing", category: .paraphrase, tool: "searchNotes", origin: .v1),
        .init(utterance: "Write down that the client wants a demo next week", category: .paraphrase, tool: "createNote", origin: .v1),
        .init(utterance: "Connect pricing research to Q3 planning", category: .paraphrase, tool: "linkItems", origin: .v1),
        // Expectation corrected in v0.3 (was updateTask). v0.1 had no
        // rescheduleTask, so a date move could only be an update. v0.2 added
        // rescheduleTask for exactly this job ("push X to <date>" is the
        // reschedule verb plus a date), and updateTask stays the tool for
        // changing several fields or the project at once. The router did not
        // change; the expectation was wrong for a 24-tool agent. The target
        // check now also verifies the task actually lands on Monday.
        .init(utterance: "Push send the invoice to Monday", category: .paraphrase, tool: "rescheduleTask", origin: .v1,
              target: "Send the invoice", targetDue: .nextWeekday(2)),
        .init(utterance: "Add a milestone Beta launch to website redesign", category: .paraphrase, tool: "addMilestone", origin: .v1),
    ]

    // MARK: - v0.2 canonical phrasing for the new tools

    static let canonicalV2: [IntentEvalCase] = [
        .init(utterance: "Reschedule draft quarterly report to Friday", category: .canonical,
              tool: "rescheduleTask", target: "Draft quarterly report", targetDue: .nextWeekday(6)),
        .init(utterance: "Move draft quarterly report to next Tuesday", category: .canonical,
              tool: "rescheduleTask", target: "Draft quarterly report", targetDue: .nextWeekday(3)),
        .init(utterance: "Push clean the gutters by 2 days", category: .canonical,
              tool: "rescheduleTask", target: "Clean the gutters", targetDue: .daysFromToday(2)),
        .init(utterance: "Reschedule pay the water bill to end of month", category: .canonical,
              tool: "rescheduleTask", target: "Pay the water bill", targetDue: .endOfMonth),
        .init(utterance: "Snooze draft quarterly report", category: .canonical,
              tool: "snoozeTask", target: "Draft quarterly report", targetDue: .daysFromToday(1)),
        .init(utterance: "Snooze clean the gutters for 3 days", category: .canonical,
              tool: "snoozeTask", target: "Clean the gutters", targetDue: .daysFromToday(3)),
        .init(utterance: "Snooze pay the water bill until Monday", category: .canonical,
              tool: "snoozeTask", target: "Pay the water bill", targetDue: .nextWeekday(2)),
        .init(utterance: "Set priority of clean the gutters to high", category: .canonical,
              tool: "setPriority", target: "Clean the gutters", targetPriority: .high),
        .init(utterance: "Make draft quarterly report urgent", category: .canonical,
              tool: "setPriority", target: "Draft quarterly report", targetPriority: .urgent),
        .init(utterance: "Mark pay the water bill as low priority", category: .canonical,
              tool: "setPriority", target: "Pay the water bill", targetPriority: .low),
        .init(utterance: "Remind me to stretch every morning", category: .canonical,
              tool: "createTask", title: "Stretch", due: .daysFromToday(0), repeats: "daily"),
        .init(utterance: "Add a task to review the budget every Monday", category: .canonical,
              tool: "createTask", title: "Review the budget", due: .nextWeekday(2), repeats: "weekly:1"),
        .init(utterance: "Remind me to take out the bins every other Thursday", category: .canonical,
              tool: "createTask", title: "Take out the bins", due: .nextWeekday(5), repeats: "weekly:2"),
        .init(utterance: "Remind me to water the ferns every 3 days", category: .canonical,
              tool: "createTask", title: "Water the ferns", due: .daysFromToday(0), repeats: "days:3"),
        .init(utterance: "Add a task to check the inbox every weekday", category: .canonical,
              tool: "createTask", title: "Check the inbox", repeats: "weekdays"),
        .init(utterance: "Make clean the gutters repeat every week", category: .canonical,
              tool: "setRecurrence", target: "Clean the gutters", targetRepeats: "weekly:1"),
        .init(utterance: "Stop repeating morning pages", category: .canonical,
              tool: "setRecurrence", target: "Morning pages", targetRepeats: "none"),
        .init(utterance: "Complete morning pages", category: .canonical,
              tool: "completeTask", completes: "Morning pages",
              target: "Morning pages", targetDue: .daysFromToday(1), targetRepeats: "daily"),
        .init(utterance: "Add milestone Public beta to Q3 Planning by end of month", category: .canonical,
              tool: "addMilestone"),
        .init(utterance: "List milestones for Website Redesign", category: .canonical, tool: "listMilestones"),
        .init(utterance: "What are the milestones for Q3 Planning?", category: .canonical, tool: "listMilestones"),
        .init(utterance: "Append to meeting notes: Sam will send the deck", category: .canonical,
              tool: "appendNote", noteContains: ("Meeting notes", "Sam will send the deck")),
        .init(utterance: "Add to offsite plan note: book a minibus", category: .canonical,
              tool: "appendNote", noteContains: ("Offsite plan", "book a minibus")),
        .init(utterance: "Search everything for invoice", category: .canonical, tool: "searchEverything"),
        .init(utterance: "Search all for offsite", category: .canonical, tool: "searchEverything"),
        .init(utterance: "What do my notes say about the venue?", category: .canonical, tool: "askNotes"),
        .init(utterance: "Ask my notes who owns the feedback round", category: .canonical, tool: "askNotes"),
        .init(utterance: "Undo that", category: .canonical, tool: "undo"),
        .init(utterance: "What's on my calendar this afternoon?", category: .canonical, tool: "calendarAgenda"),
        .init(utterance: "Export today's tasks to Reminders", category: .canonical, tool: "exportToReminders"),
    ]

    // MARK: - v0.2 compound (multi-step) requests

    static let compound: [IntentEvalCase] = [
        .init(utterance: "Create a project Launch, add 3 tasks for Friday and link it to brand voice",
              category: .compound, tool: "createProject",
              steps: ["createProject", "createTask", "createTask", "createTask", "linkItems"], createdIn: "Launch"),
        .init(utterance: "Add tasks: book venue, send invites and order catering for next Friday",
              category: .compound, tool: "createTask",
              steps: ["createTask", "createTask", "createTask"]),
        .init(utterance: "Create a project Garden and remind me to buy seeds tomorrow",
              category: .compound, tool: "createProject",
              steps: ["createProject", "createTask"], createdIn: "Garden"),
        .init(utterance: "Remind me to call the plumber tomorrow, then mark renew passport done",
              category: .compound, tool: "createTask", completes: "Renew passport",
              steps: ["createTask", "completeTask"]),
        .init(utterance: "Finish renew passport and complete write launch copy",
              category: .compound, tool: "completeTask", completes: "Write launch copy",
              steps: ["completeTask", "completeTask"]),
        .init(utterance: "Start a project called Podcast, add a milestone First episode by end of month and add 2 tasks",
              category: .compound, tool: "createProject",
              steps: ["createProject", "addMilestone", "createTask", "createTask"], createdIn: "Podcast"),
        .init(utterance: "Note: the venue wants a deposit by June, then link it to website redesign",
              category: .compound, tool: "createNote",
              steps: ["createNote", "linkItems"]),
        .init(utterance: "Reschedule draft quarterly report to Monday and make it urgent",
              category: .compound, tool: "rescheduleTask",
              target: "Draft quarterly report", targetDue: .nextWeekday(2), targetPriority: .urgent,
              steps: ["rescheduleTask", "setPriority"]),
        .init(utterance: "Create a project Move house, add tasks: pack books, cancel internet and book a van",
              category: .compound, tool: "createProject",
              steps: ["createProject", "createTask", "createTask", "createTask"], createdIn: "Move house"),
        .init(utterance: "What's blocking website redesign and what's due today?",
              category: .compound, tool: "projectStatus",
              steps: ["projectStatus", "agenda"]),
        .init(utterance: "Remind me to pay the council tax on Friday and snooze clean the gutters until Monday",
              category: .compound, tool: "createTask",
              target: "Clean the gutters", targetDue: .nextWeekday(2),
              steps: ["createTask", "snoozeTask"]),
        .init(utterance: "Set priority of pay the water bill to high, then reschedule it to tomorrow",
              category: .compound, tool: "setPriority",
              target: "Pay the water bill", targetDue: .daysFromToday(1), targetPriority: .high,
              steps: ["setPriority", "rescheduleTask"]),
    ]

    // MARK: - v0.2 dev paraphrases (rules may be tuned on these)

    static let paraphraseV2: [IntentEvalCase] = [
        .init(utterance: "Push draft quarterly report back to next week", category: .paraphrase,
              tool: "rescheduleTask", target: "Draft quarterly report", targetDue: .daysFromToday(7)),
        .init(utterance: "Can you move the quarterly report to Thursday?", category: .paraphrase,
              tool: "rescheduleTask", target: "Draft quarterly report", targetDue: .nextWeekday(5)),
        .init(utterance: "Bump the water bill to the end of the month", category: .paraphrase,
              tool: "rescheduleTask", target: "Pay the water bill", targetDue: .endOfMonth),
        .init(utterance: "Hold off on clean the gutters until next week", category: .paraphrase,
              tool: "snoozeTask", target: "Clean the gutters", targetDue: .daysFromToday(7)),
        .init(utterance: "Remind me about the gutters later", category: .paraphrase,
              tool: "snoozeTask", target: "Clean the gutters", targetDue: .daysFromToday(1)),
        .init(utterance: "The quarterly report is top priority", category: .paraphrase,
              tool: "setPriority", target: "Draft quarterly report", targetPriority: .urgent),
        .init(utterance: "Deprioritize clean the gutters", category: .paraphrase,
              tool: "setPriority", target: "Clean the gutters", targetPriority: .low),
        .init(utterance: "I want to meditate every morning", category: .paraphrase,
              tool: "createTask", title: "Meditate", repeats: "daily"),
        .init(utterance: "Every Friday I need to send the timesheet", category: .paraphrase,
              tool: "createTask", title: "Send the timesheet", due: .nextWeekday(6), repeats: "weekly:1"),
        .init(utterance: "The gutters should be cleaned every 2 weeks", category: .paraphrase,
              tool: "setRecurrence", target: "Clean the gutters", targetRepeats: "weekly:2"),
        .init(utterance: "I'm done with the quarterly report", category: .paraphrase,
              tool: "completeTask", completes: "Draft quarterly report"),
        .init(utterance: "Crossed off pay the water bill", category: .paraphrase,
              tool: "completeTask", completes: "Pay the water bill"),
        .init(utterance: "Which tasks are overdue?", category: .paraphrase, tool: "queryTasks"),
        .init(utterance: "What's coming up this week?", category: .paraphrase, tool: "queryTasks"),
        .init(utterance: "How's Q3 planning coming along?", category: .paraphrase, tool: "projectStatus"),
        .init(utterance: "Make a note that Sarah prefers Tuesday syncs", category: .paraphrase, tool: "createNote"),
        .init(utterance: "Add the minibus idea to the offsite plan note", category: .paraphrase,
              tool: "appendNote", noteContains: ("Offsite plan", "minibus idea")),
        .init(utterance: "Look up anything about invoices", category: .paraphrase, tool: "searchEverything"),
        .init(utterance: "What did we decide about the venue?", category: .paraphrase, tool: "askNotes"),
        .init(utterance: "Tie pricing research to website redesign", category: .paraphrase, tool: "linkItems"),
        .init(utterance: "Never mind, undo that", category: .paraphrase, tool: "undo"),
        .init(utterance: "What milestones does website redesign have?", category: .paraphrase, tool: "listMilestones"),
        .init(utterance: "Put renew the lease on my list for the end of the month", category: .paraphrase,
              tool: "createTask", title: "Renew the lease", due: .endOfMonth),
    ]

    // MARK: - v0.2 held-out (reported): frozen, never used to tune rules.
    // Published with v0.2, so kept as a secondary signal, not the headline.

    static let heldout: [IntentEvalCase] = [
        .init(utterance: "Could you remind me to book a dentist appointment next Tues afternoon?", category: .heldout,
              tool: "createTask", title: "Book a dentist appointment", due: .nextWeekday(3)),
        .init(utterance: "I have to renew my passport in a fortnight", category: .heldout,
              tool: "createTask", title: "Renew my passport", due: .daysFromToday(14)),
        .init(utterance: "Put 'file taxes' on my to-do list for end of month", category: .heldout,
              tool: "createTask", title: "File taxes", due: .endOfMonth),
        .init(utterance: "Need to call the plumber tomorrow morning", category: .heldout,
              tool: "createTask", title: "Call the plumber", due: .daysFromToday(1)),
        .init(utterance: "Set up a reminder to pay the electricity bill on Friday", category: .heldout,
              tool: "createTask", title: "Pay the electricity bill", due: .nextWeekday(6)),
        .init(utterance: "Water the plants every other day", category: .heldout,
              tool: "createTask", title: "Water the plants", repeats: "days:2"),
        .init(utterance: "Every Sunday evening, remind me to plan the week", category: .heldout,
              tool: "createTask", title: "Plan the week", due: .nextWeekday(1), repeats: "weekly:1"),
        .init(utterance: "I wrapped up the quarterly report", category: .heldout,
              tool: "completeTask", completes: "Draft quarterly report"),
        .init(utterance: "Tick off book flights", category: .heldout,
              tool: "completeTask", completes: "Book flights for the offsite"),
        .init(utterance: "Renew passport is finished", category: .heldout,
              tool: "completeTask", completes: "Renew passport"),
        .init(utterance: "Delay pay the water bill by a week", category: .heldout,
              tool: "rescheduleTask", target: "Pay the water bill", targetDue: .daysFromToday(9)),
        .init(utterance: "Postpone the gutters to Saturday", category: .heldout,
              tool: "rescheduleTask", target: "Clean the gutters", targetDue: .nextWeekday(7)),
        .init(utterance: "Shift draft quarterly report to the day after tomorrow", category: .heldout,
              tool: "rescheduleTask", target: "Draft quarterly report", targetDue: .daysFromToday(2)),
        .init(utterance: "Snooze the gutters till next week", category: .heldout,
              tool: "snoozeTask", target: "Clean the gutters", targetDue: .daysFromToday(7)),
        .init(utterance: "Defer pay the water bill for two days", category: .heldout,
              tool: "snoozeTask", target: "Pay the water bill", targetDue: .daysFromToday(2)),
        .init(utterance: "Flag the quarterly report as high priority", category: .heldout,
              tool: "setPriority", target: "Draft quarterly report", targetPriority: .high),
        .init(utterance: "The water bill isn't urgent, make it low priority", category: .heldout,
              tool: "setPriority", target: "Pay the water bill", targetPriority: .low),
        .init(utterance: "Have morning pages repeat every weekday", category: .heldout,
              tool: "setRecurrence", target: "Morning pages", targetRepeats: "weekdays"),
        .init(utterance: "What's late?", category: .heldout, tool: "queryTasks"),
        .init(utterance: "List everything I still have to do", category: .heldout, tool: "queryTasks"),
        .init(utterance: "Where are we with the website redesign?", category: .heldout, tool: "projectStatus"),
        .init(utterance: "Give me an update on Q3 planning", category: .heldout, tool: "projectStatus"),
        .init(utterance: "Remember that the client's fiscal year starts in April", category: .heldout, tool: "createNote"),
        .init(utterance: "Save a note: whiteboard photos are in the shared drive", category: .heldout, tool: "createNote"),
        .init(utterance: "Add 'Sam will send the deck' to the meeting notes", category: .heldout,
              tool: "appendNote", noteContains: ("Meeting notes", "Sam will send the deck")),
        .init(utterance: "Find anything mentioning flights", category: .heldout, tool: "searchEverything"),
        .init(utterance: "According to my notes, how many people fit in the venue?", category: .heldout, tool: "askNotes"),
        .init(utterance: "What did I jot down about Sarah?", category: .heldout, tool: "askNotes"),
        .init(utterance: "When is the next milestone for website redesign?", category: .heldout, tool: "listMilestones"),
        .init(utterance: "Relate the brand voice note to Q3 planning", category: .heldout, tool: "linkItems"),
        .init(utterance: "Scratch that last change", category: .heldout, tool: "undo"),
        .init(utterance: "Am I free this afternoon?", category: .heldout, tool: "calendarAgenda"),
        .init(utterance: "Copy my overdue tasks into Reminders", category: .heldout, tool: "exportToReminders"),
        .init(utterance: "Look for notes on pricing", category: .heldout, tool: "searchNotes"),
    ]
}
