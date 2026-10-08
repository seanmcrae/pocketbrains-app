import Foundation
@testable import PocketBrains

/// v0.3 HELD-OUT paraphrase split. SYNTHETIC: written for this eval, no real
/// user data; entity names refer to the fixture in `IntentRouterEval.seed`.
///
/// FROZEN. Written in one sitting and committed before any v0.3 router
/// change, so its first CI run is the honest "before" number. Rules are
/// never tuned against it: the eval prints its score and a miss count, never
/// the individual misses. Do not edit utterances or expectations; if one is
/// ever found to be wrong, leave it, and document the error instead.
///
/// Expectations are what a person would want to happen, not what the router
/// can currently parse. Date moves are `rescheduleTask` (see the note on
/// "Push send the invoice to Monday" in `IntentEvalCorpus.v1`).
/// Caveat: the same author wrote this split and the router rules.
extension IntentEvalCorpus {
    static let heldoutV3: [IntentEvalCase] = [
        // Task capture
        .init(utterance: "Add pick up the dry cleaning for Thursday", category: .heldout,
              tool: "createTask", origin: .v3, title: "Pick up the dry cleaning", due: .nextWeekday(5)),
        .init(utterance: "I should probably call my accountant on Wednesday", category: .heldout,
              tool: "createTask", origin: .v3, title: "Call my accountant", due: .nextWeekday(4)),
        .init(utterance: "Create a task: submit the expense report by Friday", category: .heldout,
              tool: "createTask", origin: .v3, title: "Submit the expense report", due: .nextWeekday(6)),
        .init(utterance: "Remember to buy milk tomorrow", category: .heldout,
              tool: "createTask", origin: .v3, title: "Buy milk", due: .daysFromToday(1)),
        .init(utterance: "Please make a reminder to renew the domain in two weeks", category: .heldout,
              tool: "createTask", origin: .v3, title: "Renew the domain", due: .daysFromToday(14)),
        .init(utterance: "Could you set a task to order printer ink", category: .heldout,
              tool: "createTask", origin: .v3, title: "Order printer ink", due: .undated),
        .init(utterance: "Every Tuesday remind me to update the sprint board", category: .heldout,
              tool: "createTask", origin: .v3, title: "Update the sprint board", due: .nextWeekday(3),
              repeats: "weekly:1"),
        .init(utterance: "Daily reminder to take my vitamins", category: .heldout,
              tool: "createTask", origin: .v3, title: "Take my vitamins", repeats: "daily"),
        .init(utterance: "Make sure I back up my photos on Saturday", category: .heldout,
              tool: "createTask", origin: .v3, title: "Back up my photos", due: .nextWeekday(7)),

        // Completion
        .init(utterance: "Send the invoice is done", category: .heldout,
              tool: "completeTask", origin: .v3, completes: "Send the invoice"),
        .init(utterance: "Mark the passport renewal as complete", category: .heldout,
              tool: "completeTask", origin: .v3, completes: "Renew passport"),
        .init(utterance: "Got the flights booked", category: .heldout,
              tool: "completeTask", origin: .v3, completes: "Book flights for the offsite"),
        .init(utterance: "Finally finished the landing page", category: .heldout,
              tool: "completeTask", origin: .v3, completes: "Build landing page"),
        .init(utterance: "You can close out the water bill task", category: .heldout,
              tool: "completeTask", origin: .v3, completes: "Pay the water bill"),

        // Rescheduling
        .init(utterance: "Can we move the invoice to Wednesday?", category: .heldout,
              tool: "rescheduleTask", origin: .v3, target: "Send the invoice", targetDue: .nextWeekday(4)),
        .init(utterance: "Push back the gutters by three days", category: .heldout,
              tool: "rescheduleTask", origin: .v3, target: "Clean the gutters", targetDue: .daysFromToday(3)),
        .init(utterance: "Change the due date of the quarterly report to next Friday", category: .heldout,
              tool: "rescheduleTask", origin: .v3, target: "Draft quarterly report", targetDue: .nextWeekday(6)),
        .init(utterance: "Reschedule the water bill for Monday", category: .heldout,
              tool: "rescheduleTask", origin: .v3, target: "Pay the water bill", targetDue: .nextWeekday(2)),
        .init(utterance: "Let's do the passport renewal next week instead", category: .heldout,
              tool: "rescheduleTask", origin: .v3, target: "Renew passport", targetDue: .daysFromToday(7)),

        // Snoozing
        .init(utterance: "Snooze the invoice until Saturday", category: .heldout,
              tool: "snoozeTask", origin: .v3, target: "Send the invoice", targetDue: .nextWeekday(7)),
        .init(utterance: "Not today, the quarterly report can wait until tomorrow", category: .heldout,
              tool: "snoozeTask", origin: .v3, target: "Draft quarterly report", targetDue: .daysFromToday(1)),
        .init(utterance: "Remind me about the water bill in a few days", category: .heldout,
              tool: "snoozeTask", origin: .v3, target: "Pay the water bill", targetDue: .daysFromToday(3)),

        // Priority
        .init(utterance: "Bump the gutters up to high priority", category: .heldout,
              tool: "setPriority", origin: .v3, target: "Clean the gutters", targetPriority: .high),
        .init(utterance: "Lower the priority of the passport renewal", category: .heldout,
              tool: "setPriority", origin: .v3, target: "Renew passport", targetPriority: .low),
        .init(utterance: "Set the quarterly report to urgent", category: .heldout,
              tool: "setPriority", origin: .v3, target: "Draft quarterly report", targetPriority: .urgent),
        .init(utterance: "Make the landing page a high priority", category: .heldout,
              tool: "setPriority", origin: .v3, target: "Build landing page", targetPriority: .high),

        // Recurrence on existing tasks
        .init(utterance: "Repeat pay the water bill every 4 weeks", category: .heldout,
              tool: "setRecurrence", origin: .v3, target: "Pay the water bill", targetRepeats: "weekly:4"),
        .init(utterance: "Morning pages don't need to repeat anymore", category: .heldout,
              tool: "setRecurrence", origin: .v3, target: "Morning pages", targetRepeats: "none"),
        .init(utterance: "Set clean the gutters to recur every other week", category: .heldout,
              tool: "setRecurrence", origin: .v3, target: "Clean the gutters", targetRepeats: "weekly:2"),

        // Lists, status, agenda
        .init(utterance: "What's overdue right now?", category: .heldout, tool: "queryTasks", origin: .v3),
        .init(utterance: "Show me what's due this week", category: .heldout, tool: "queryTasks", origin: .v3),
        .init(utterance: "Is anything stuck?", category: .heldout, tool: "queryTasks", origin: .v3),
        .init(utterance: "How far along is Q3 planning?", category: .heldout, tool: "projectStatus", origin: .v3),
        .init(utterance: "Any blockers on the website redesign?", category: .heldout, tool: "projectStatus", origin: .v3),
        .init(utterance: "What should I focus on today?", category: .heldout, tool: "agenda", origin: .v3),

        // Notes
        .init(utterance: "Note to self: the office wifi password changes monthly", category: .heldout,
              tool: "createNote", origin: .v3),
        .init(utterance: "Capture this: Priya suggested a referral discount", category: .heldout,
              tool: "createNote", origin: .v3),
        .init(utterance: "Log that the client signed off on the mockups", category: .heldout,
              tool: "createNote", origin: .v3),
        .init(utterance: "Add to the brand voice note that we never use exclamation marks", category: .heldout,
              tool: "appendNote", origin: .v3, noteContains: ("Brand voice", "we never use exclamation marks")),
        .init(utterance: "Update the meeting notes with: budget approved", category: .heldout,
              tool: "appendNote", origin: .v3, noteContains: ("Meeting notes", "budget approved")),
        .init(utterance: "What did the pricing research conclude?", category: .heldout, tool: "askNotes", origin: .v3),
        .init(utterance: "Who owns the feedback round?", category: .heldout, tool: "askNotes", origin: .v3),
        .init(utterance: "When do the offsite flights land, according to my notes?", category: .heldout,
              tool: "askNotes", origin: .v3),
        .init(utterance: "Search my notes for venue", category: .heldout, tool: "searchNotes", origin: .v3),
        .init(utterance: "Is there anything about the invoice anywhere?", category: .heldout,
              tool: "searchEverything", origin: .v3),
        .init(utterance: "What did I write yesterday?", category: .heldout, tool: "notesFrom", origin: .v3),

        // Projects, milestones, links
        .init(utterance: "Show the website redesign milestones", category: .heldout, tool: "listMilestones", origin: .v3),
        .init(utterance: "Q3 planning needs a milestone called Board review on Friday", category: .heldout,
              tool: "addMilestone", origin: .v3),
        .init(utterance: "Attach the pricing research note to Q3 planning", category: .heldout,
              tool: "linkItems", origin: .v3),
        .init(utterance: "Set up a new project for the conference talk", category: .heldout,
              tool: "createProject", origin: .v3, title: "Conference talk"),

        // Undo and integrations
        .init(utterance: "Oops, revert that", category: .heldout, tool: "undo", origin: .v3),
        .init(utterance: "Do I have any meetings tomorrow?", category: .heldout, tool: "calendarAgenda", origin: .v3),
        .init(utterance: "Send this week's tasks over to Reminders", category: .heldout,
              tool: "exportToReminders", origin: .v3),
    ]
}
