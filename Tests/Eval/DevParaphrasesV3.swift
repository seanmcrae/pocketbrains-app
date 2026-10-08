import Foundation
@testable import PocketBrains

/// v0.3 DEV paraphrase split. SYNTHETIC: written for this eval, no real user
/// data; entity names refer to the fixture in `IntentRouterEval.seed`.
///
/// This is the only paraphrase split the v0.3 router work may be tuned on:
/// its misses are printed in full. It was written after the v0.3 held-out
/// split was committed, deliberately in a different register (terse,
/// chatty, mobile-typed) rather than as a mirror of it, so that tuning here
/// does not quietly fit the held-out phrasings.
extension IntentEvalCorpus {
    static let devV3: [IntentEvalCase] = [
        // Task capture
        .init(utterance: "need to pick up the kids' passports on friday", category: .paraphrase,
              tool: "createTask", origin: .v3, title: "Pick up the kids' passports", due: .nextWeekday(6)),
        .init(utterance: "Gotta book the car in for its MOT next week", category: .paraphrase,
              tool: "createTask", origin: .v3, title: "Book the car in for its MOT", due: .daysFromToday(7)),
        .init(utterance: "Stick 'buy a birthday present for Ana' on the list", category: .paraphrase,
              tool: "createTask", origin: .v3, title: "Buy a birthday present for Ana", due: .undated),
        .init(utterance: "Can I get a reminder to cancel the trial in 5 days", category: .paraphrase,
              tool: "createTask", origin: .v3, title: "Cancel the trial", due: .daysFromToday(5)),
        .init(utterance: "Pencil in dinner with Jo on Saturday", category: .paraphrase,
              tool: "createTask", origin: .v3, title: "Dinner with Jo", due: .nextWeekday(7)),
        .init(utterance: "I'd like to journal every evening", category: .paraphrase,
              tool: "createTask", origin: .v3, title: "Journal", repeats: "daily"),
        .init(utterance: "Task: renew the parking permit by end of month", category: .paraphrase,
              tool: "createTask", origin: .v3, title: "Renew the parking permit", due: .endOfMonth),
        .init(utterance: "Ping me tomorrow to chase the refund", category: .paraphrase,
              tool: "createTask", origin: .v3, title: "Chase the refund", due: .daysFromToday(1)),

        // Completion
        .init(utterance: "Gutters are clean", category: .paraphrase,
              tool: "completeTask", origin: .v3, completes: "Clean the gutters"),
        .init(utterance: "Paid the water bill", category: .paraphrase,
              tool: "completeTask", origin: .v3, completes: "Pay the water bill"),
        .init(utterance: "Launch copy's written", category: .paraphrase,
              tool: "completeTask", origin: .v3, completes: "Write launch copy"),
        .init(utterance: "Tick the invoice off", category: .paraphrase,
              tool: "completeTask", origin: .v3, completes: "Send the invoice"),
        .init(utterance: "That's the passport sorted", category: .paraphrase,
              tool: "completeTask", origin: .v3, completes: "Renew passport"),

        // Rescheduling
        .init(utterance: "Can the invoice slip to Thursday?", category: .paraphrase,
              tool: "rescheduleTask", origin: .v3, target: "Send the invoice", targetDue: .nextWeekday(5)),
        .init(utterance: "Kick the quarterly report out a couple of days", category: .paraphrase,
              tool: "rescheduleTask", origin: .v3, target: "Draft quarterly report", targetDue: .daysFromToday(3)),
        .init(utterance: "The water bill is now due Monday", category: .paraphrase,
              tool: "rescheduleTask", origin: .v3, target: "Pay the water bill", targetDue: .nextWeekday(2)),
        .init(utterance: "Bring the gutters forward to tomorrow", category: .paraphrase,
              tool: "rescheduleTask", origin: .v3, target: "Clean the gutters", targetDue: .daysFromToday(1)),

        // Snoozing
        .init(utterance: "Park the gutters for a week", category: .paraphrase,
              tool: "snoozeTask", origin: .v3, target: "Clean the gutters", targetDue: .daysFromToday(7)),
        .init(utterance: "Not now, remind me about the passport tomorrow", category: .paraphrase,
              tool: "snoozeTask", origin: .v3, target: "Renew passport", targetDue: .daysFromToday(1)),
        .init(utterance: "Hide the water bill until Friday", category: .paraphrase,
              tool: "snoozeTask", origin: .v3, target: "Pay the water bill", targetDue: .nextWeekday(6)),

        // Priority
        .init(utterance: "The invoice is really important", category: .paraphrase,
              tool: "setPriority", origin: .v3, target: "Send the invoice", targetPriority: .high),
        .init(utterance: "Gutters aren't a priority", category: .paraphrase,
              tool: "setPriority", origin: .v3, target: "Clean the gutters", targetPriority: .low),
        .init(utterance: "Raise the passport to high priority", category: .paraphrase,
              tool: "setPriority", origin: .v3, target: "Renew passport", targetPriority: .high),

        // Recurrence on existing tasks
        .init(utterance: "The water bill comes round every 4 weeks", category: .paraphrase,
              tool: "setRecurrence", origin: .v3, target: "Pay the water bill", targetRepeats: "weekly:4"),
        .init(utterance: "Turn off repeats for morning pages", category: .paraphrase,
              tool: "setRecurrence", origin: .v3, target: "Morning pages", targetRepeats: "none"),
        .init(utterance: "Can the gutters be a fortnightly job?", category: .paraphrase,
              tool: "setRecurrence", origin: .v3, target: "Clean the gutters", targetRepeats: "weekly:2"),

        // Lists, status, agenda
        .init(utterance: "Anything overdue?", category: .paraphrase, tool: "queryTasks", origin: .v3),
        .init(utterance: "What's still open?", category: .paraphrase, tool: "queryTasks", origin: .v3),
        .init(utterance: "Show stuck tasks", category: .paraphrase, tool: "queryTasks", origin: .v3),
        .init(utterance: "Website redesign: where do things stand?", category: .paraphrase,
              tool: "projectStatus", origin: .v3),
        .init(utterance: "Q3 planning progress?", category: .paraphrase, tool: "projectStatus", origin: .v3),
        .init(utterance: "Morning! What's on today?", category: .paraphrase, tool: "agenda", origin: .v3),

        // Notes
        .init(utterance: "Idea: run a referral programme in spring", category: .paraphrase,
              tool: "createNote", origin: .v3),
        .init(utterance: "Keep in mind the client is on holiday in August", category: .paraphrase,
              tool: "createNote", origin: .v3),
        .init(utterance: "FYI for later: the boiler was serviced in May", category: .paraphrase,
              tool: "createNote", origin: .v3),
        .init(utterance: "Tack 'Ana joins in March' onto the meeting notes", category: .paraphrase,
              tool: "appendNote", origin: .v3, noteContains: ("Meeting notes", "Ana joins in March")),
        .init(utterance: "Put 'parking is free after 6' in the offsite plan note", category: .paraphrase,
              tool: "appendNote", origin: .v3, noteContains: ("Offsite plan", "parking is free after 6")),
        .init(utterance: "Remind me what the brand voice guidelines say", category: .paraphrase,
              tool: "askNotes", origin: .v3),
        .init(utterance: "What's the venue capacity?", category: .paraphrase, tool: "askNotes", origin: .v3),
        .init(utterance: "Did we decide anything on pricing?", category: .paraphrase, tool: "askNotes", origin: .v3),
        .init(utterance: "Pull up everything on Q3", category: .paraphrase, tool: "searchEverything", origin: .v3),
        .init(utterance: "Grep my notes for Sarah", category: .paraphrase, tool: "searchNotes", origin: .v3),
        .init(utterance: "Show me yesterday's notes", category: .paraphrase, tool: "notesFrom", origin: .v3),
        .init(utterance: "Did I already send the invoice?", category: .paraphrase, tool: "recall", origin: .v3),

        // Projects, milestones, links
        .init(utterance: "Milestones for the website redesign?", category: .paraphrase,
              tool: "listMilestones", origin: .v3),
        .init(utterance: "Put a Launch review milestone on Website Redesign for end of month", category: .paraphrase,
              tool: "addMilestone", origin: .v3),
        .init(utterance: "Cross-reference brand voice with Q3 planning", category: .paraphrase,
              tool: "linkItems", origin: .v3),
        .init(utterance: "Spin up a project called Book club", category: .paraphrase,
              tool: "createProject", origin: .v3, title: "Book club"),

        // Undo and integrations
        .init(utterance: "Wait, put that back how it was", category: .paraphrase, tool: "undo", origin: .v3),
        .init(utterance: "Busy tomorrow morning?", category: .paraphrase, tool: "calendarAgenda", origin: .v3),
        .init(utterance: "Push today's list to Apple Reminders", category: .paraphrase,
              tool: "exportToReminders", origin: .v3),
    ]
}
