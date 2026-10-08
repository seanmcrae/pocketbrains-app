import Foundation
import Testing
@testable import PocketBrains

/// v0.3 constructions in the deterministic grammar, checked at parse level
/// (no store). Sentences here are new, not taken from any eval split.
@Suite(.timeLimit(.minutes(1)))
struct ParaphraseFrameTests {
    @Test func interjectionsAreDropped() {
        #expect(CommandFrames.stripDiscourse("Wait, undo that") == "undo that")
        #expect(CommandFrames.stripDiscourse("Not now! snooze it") == "snooze it")
        #expect(CommandFrames.stripDiscourse("So I need to call Ana") == "So I need to call Ana")
    }

    @Test func subjectFirstAndStatementReschedules() {
        let slip = IntentGrammar.parse("Can the report slip to Friday?")
        #expect(slip.tool == "rescheduleTask")
        #expect(slip.arguments["query"] == "report")
        #expect(slip.arguments["to"] == "Friday")

        let due = IntentGrammar.parse("The rent is now due Tuesday")
        #expect(due.tool == "rescheduleTask")
        #expect(due.arguments["query"] == "rent")

        let shift = IntentGrammar.parse("Kick the deck out three days")
        #expect(shift.tool == "rescheduleTask")
        #expect(shift.arguments["query"] == "deck")
        #expect(shift.arguments["by"] == "three days")
    }

    @Test func completionStatementsAndPastTense() {
        let state = IntentGrammar.parse("The deck is finished")
        #expect(state.tool == "completeTask")
        #expect(state.arguments["query"] == "deck")

        let past = IntentGrammar.parse("Paid the electricity bill")
        #expect(past.tool == "completeTask")
        #expect(past.arguments["query"] == "pay the electricity bill")
    }

    @Test func priorityTargetsKeepTheDocumentedForm() {
        let documented = IntentGrammar.parse("Set priority of clean the gutters to high")
        #expect(documented.tool == "setPriority")
        #expect(documented.arguments["query"] == "clean the gutters")
        #expect(documented.arguments["priority"] == "high")

        let statement = IntentGrammar.parse("The deck isn't a priority")
        #expect(statement.tool == "setPriority")
        #expect(statement.arguments["priority"] == "low")
    }

    @Test func capturesAskedForAsNounsOrLabels() {
        let ping = IntentGrammar.parse("Ping me on Monday to renew the lease")
        #expect(ping.tool == "createTask")
        #expect(ping.arguments["title"] == "Renew the lease")
        #expect(ping.arguments["due"] != nil)

        #expect(IntentGrammar.parse("Idea: a quarterly newsletter").tool == "createNote")
        #expect(IntentGrammar.parse("Task: book the venue").arguments["title"] == "Book the venue")
    }

    @Test func questionsGoToNotesOrTheAgenda() {
        #expect(IntentGrammar.parse("What's the deposit amount?").tool == "askNotes")
        #expect(IntentGrammar.parse("Did we agree on the venue?").tool == "askNotes")
        #expect(IntentGrammar.parse("What's happening today?").tool == "agenda")
        let status = IntentGrammar.parse("Where do things stand with the launch?")
        #expect(status.tool == "projectStatus")
        #expect(status.arguments["name"] == "launch")
    }
}
