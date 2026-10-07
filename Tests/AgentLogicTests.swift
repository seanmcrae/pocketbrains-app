import Foundation
import SwiftData
import Testing
@testable import PocketBrains

/// Tests the routing table directly. (Iterating the paced reply stream from
/// a @MainActor test deadlocks under the test harness — the stream's pacing
/// is presentation-only and stays untested by design.)
@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct IntentFallbackBackendTests {
    /// See ToolBoxTests.makeBox — the container must outlive the test.
    private func makeBox() -> (ToolBox, ModelContainer) {
        let container = Store.makeContainer(inMemory: true)
        let services = DataServices(context: container.mainContext)
        return (ToolBox(services: services, semanticIndex: SemanticIndex(context: container.mainContext)),
                container)
    }

    @Test func reminderPhraseCreatesTaskWithDueDate() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        let routed = IntentFallbackBackend.routeIntent(
            "Remind me to send the invoice on Friday", toolbox: box)
        #expect(routed.tool == "createTask")
        #expect(routed.result?.succeeded == true)
        #expect(!routed.reply.isEmpty)
        let task = try #require(box.services.tasks.all().first)
        #expect(task.title.lowercased().contains("send the invoice"))
        #expect(task.dueDate != nil)
    }

    @Test func finishPhraseCompletesTask() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createTask(title: "Book flights for the offsite")
        let routed = IntentFallbackBackend.routeIntent("finish book flights", toolbox: box)
        #expect(routed.tool == "completeTask")
        #expect(box.services.tasks.all(includeDone: true).first?.isDone == true)
    }

    @Test func agendaPhraseRoutesToAgenda() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        let routed = IntentFallbackBackend.routeIntent("What needs my attention today?", toolbox: box)
        #expect(routed.tool == "agenda")
        #expect(routed.result != nil)
    }

    @Test func reminderContainingCompletionVerbCreatesTask() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createTask(title: "Finish the quarterly deck draft")
        let routed = IntentFallbackBackend.routeIntent(
            "Remind me to finish the quarterly deck by Thursday", toolbox: box)
        #expect(routed.tool == "createTask")
        #expect(box.services.tasks.all(includeDone: true).allSatisfy { !$0.isDone })
        let created = try #require(box.services.tasks.all().first { $0.title == "Finish the quarterly deck" })
        #expect(created.dueDate.map { Calendar.current.component(.weekday, from: $0) } == 5)
    }

    @Test func reminderMentioningStatusCreatesTask() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        let routed = IntentFallbackBackend.routeIntent(
            "Remind me to check the status of the website", toolbox: box)
        #expect(routed.tool == "createTask")
        #expect(box.services.tasks.all().first?.title == "Check the status of the website")
    }

    @Test func relativeDayPhraseStaysOutOfTitle() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = IntentFallbackBackend.routeIntent("Remind me to back up the laptop in 3 days", toolbox: box)
        let task = try #require(box.services.tasks.all().first)
        #expect(task.title == "Back up the laptop")
        let expected = Calendar.current.date(byAdding: .day, value: 3,
                                             to: Calendar.current.startOfDay(for: .now))
        #expect(task.dueDate == expected)
    }

    @Test func notesAboutSearchesInsteadOfCapturing() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createNote(title: "Pricing research", body: "Annual plans convert better.")
        let routed = IntentFallbackBackend.routeIntent("Notes about pricing", toolbox: box)
        #expect(routed.tool == "searchNotes")
        #expect(box.services.notes.all().count == 1)
    }

    @Test func framesFillSlots() {
        let reschedule = IntentGrammar.parse("Move draft quarterly report to next Tuesday")
        #expect(reschedule.tool == "rescheduleTask")
        #expect(reschedule.arguments == ["query": "draft quarterly report", "to": "next Tuesday"])
        let recurring = IntentGrammar.parse("Remind me to take out the bins every other Thursday")
        #expect(recurring.tool == "createTask")
        #expect(recurring.arguments["title"] == "Take out the bins")
        #expect(recurring.arguments["repeats"] == "every other thursday")
        let milestone = IntentGrammar.parse("Add milestone Public beta to Q3 Planning by end of month")
        #expect(milestone.arguments == ["title": "Public beta", "project": "Q3 Planning", "target": "end of month"])
        let snooze = IntentGrammar.parse("Snooze clean the gutters for 3 days")
        #expect(snooze.arguments == ["query": "clean the gutters", "until": "3 days"])
    }

    @Test func lemmaFallbackHandlesInflections() {
        #expect(Lexicon.fallbackLemma("finished") == "finish")
        #expect(Lexicon.fallbackLemma("pushed") == "push")
        #expect(Lexicon.fallbackLemma("moved") == "move")
        #expect(Lexicon.fallbackLemma("postponing") == "postpon" || Lexicon.fallbackLemma("postponing") == "postpone")
        #expect(Lexicon.fallbackLemma("did") == "do")
        let tokens = Lexicon.tokens("I postponed the dentist to Friday")
        #expect(Lexicon.firstAction(in: tokens)?.0 == .reschedule)
    }

    @Test func dueTextMatchesParserPhrases() {
        #expect(IntentFallbackBackend.dueText(in: "back up the laptop in 3 days") == "in 3 days")
        #expect(IntentFallbackBackend.dueText(in: "call mum in 1 day") == "in 1 day")
        #expect(IntentFallbackBackend.dueText(in: "Send it Friday") == "friday")
    }
}

@Suite(.serialized, .timeLimit(.minutes(1)))
struct ChunkClockTests {
    @Test func mapsGlyphIndexesToArrivalChunks() {
        var clock = ChunkClock()
        clock.record(count: 5)
        let first = clock.marks[0].at
        clock.record(count: 12)

        #expect(clock.marks.count == 2)
        #expect(clock.arrival(forGlyph: 3).at == first)
        #expect(clock.arrival(forGlyph: 3).indexInChunk == 3)
        #expect(clock.arrival(forGlyph: 7).indexInChunk == 2) // 7 - 5
    }

    @Test func duplicateCountIsIgnored() {
        var clock = ChunkClock()
        clock.record(count: 5)
        clock.record(count: 5)
        #expect(clock.marks.count == 1)
    }

    @Test func shrinkingCountStartsNewTurn() {
        var clock = ChunkClock()
        clock.record(count: 20)
        clock.record(count: 3)
        #expect(clock.marks.count == 1)
        #expect(clock.marks[0].chars == 3)
    }
}
