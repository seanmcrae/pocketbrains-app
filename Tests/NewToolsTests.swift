import Foundation
import SwiftData
import Testing
@testable import PocketBrains

/// v0.2 tools: recurrence, reschedule/snooze, priority, milestones, append,
/// search-everything, and the fuzzy title fallback they rely on.
@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct NewToolsTests {
    private let cal = Calendar.current

    private func makeBox() -> (ToolBox, ModelContainer) {
        let container = Store.makeContainer(inMemory: true)
        let services = DataServices(context: container.mainContext)
        return (ToolBox(services: services, semanticIndex: SemanticIndex(context: container.mainContext)),
                container)
    }

    private func ymd(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private var today: Date { cal.startOfDay(for: .now) }
    private func days(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today)! }

    // MARK: Recurrence rules

    @Test func parsesRecurrencePhrases() {
        #expect(Recurrence.parse("every day")?.rule == Recurrence(kind: .daily))
        #expect(Recurrence.parse("daily")?.rule.raw == "daily")
        #expect(Recurrence.parse("every weekday")?.rule.raw == "weekdays")
        #expect(Recurrence.parse("weekly")?.rule.raw == "weekly:1")
        #expect(Recurrence.parse("every 3 days")?.rule.raw == "days:3")
        #expect(Recurrence.parse("every two weeks")?.rule.raw == "weekly:2")
        let otherMonday = Recurrence.parse("every other Monday")
        #expect(otherMonday?.rule.raw == "weekly:2")
        #expect(otherMonday?.anchorWeekday == 2)
        #expect(Recurrence.parse("every Friday")?.anchorWeekday == 6)
        #expect(Recurrence.parse("on Mondays")?.rule.raw == "weekly:1")
        // A one-off date is not a rule.
        #expect(Recurrence.parse("email the landlord on Monday") == nil)
        #expect(Recurrence.parse("tomorrow") == nil)
        #expect(Recurrence(raw: "days:3") == Recurrence(kind: .days, every: 3))
    }

    @Test func nextOccurrences() {
        let friday = ymd(2026, 6, 12) // a Friday
        #expect(Recurrence(kind: .daily).next(after: friday) == ymd(2026, 6, 13))
        #expect(Recurrence(kind: .weekdays).next(after: friday) == ymd(2026, 6, 15)) // skips the weekend
        #expect(Recurrence(kind: .weekly, every: 2).next(after: friday) == ymd(2026, 6, 26))
        #expect(Recurrence(kind: .days, every: 3).next(after: friday) == ymd(2026, 6, 15))
        // Completed late: never schedules into the past.
        let late = Recurrence(kind: .daily).nextOccurrence(afterCompleting: ymd(2026, 6, 1), now: friday)
        #expect(late == friday)
    }

    @Test func completingARecurringTaskSpawnsTheNextAndUndoRestores() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createTask(title: "Stretch", repeats: "every day")
        let original = try #require(box.services.tasks.all().first)
        #expect(original.dueDate == today)
        #expect(box.services.tasks.recurrence(of: original)?.raw == "daily")

        let result = box.completeTask(query: "stretch")
        #expect(result.summary.contains("next one"))
        let open = box.services.tasks.all()
        #expect(open.count == 1)
        let next = try #require(open.first)
        #expect(next.id != original.id)
        #expect(next.dueDate == days(1))
        #expect(box.services.tasks.recurrence(of: next)?.raw == "daily")
        #expect(box.services.tasks.recurrence(of: original) == nil)

        _ = box.undo(scope: "step")
        let restored = box.services.tasks.all()
        #expect(restored.map(\.id) == [original.id])
        #expect(box.services.tasks.recurrence(of: original)?.raw == "daily")
    }

    @Test func setAndClearRecurrenceWithUndo() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createTask(title: "Clean the gutters")
        let task = try #require(box.services.tasks.all().first)
        #expect(box.setRecurrence(query: "gutters", rule: "every other Saturday").succeeded)
        #expect(box.services.tasks.recurrence(of: task)?.raw == "weekly:2")
        #expect(task.dueDate.map { cal.component(.weekday, from: $0) } == 7)
        #expect(box.setRecurrence(query: "gutters", rule: "none").succeeded)
        #expect(box.services.tasks.recurrence(of: task) == nil)
        _ = box.undo(scope: "step")
        #expect(box.services.tasks.recurrence(of: task)?.raw == "weekly:2")
        #expect(!box.setRecurrence(query: "gutters", rule: "whenever I feel like it").succeeded)
    }

    // MARK: Dates

    @Test func rescheduleToADateOrByAShift() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createTask(title: "Pay the water bill", due: "in 2 days")
        let task = try #require(box.services.tasks.all().first)

        #expect(box.rescheduleTask(query: "water bill", by: "a week").succeeded)
        #expect(task.dueDate == days(9))
        #expect(box.rescheduleTask(query: "water bill", to: "tomorrow").succeeded)
        #expect(task.dueDate == days(1))
        #expect(!box.rescheduleTask(query: "water bill", to: "whenever").succeeded)
        _ = box.undo(scope: "step")
        #expect(task.dueDate == days(9))
    }

    @Test func snoozeCountsFromToday() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createTask(title: "Read the contract", due: "yesterday")
        let task = try #require(box.services.tasks.all().first)
        #expect(box.snoozeTask(query: "contract").succeeded)
        #expect(task.dueDate == days(1))
        #expect(box.snoozeTask(query: "contract", until: "3 days").succeeded)
        #expect(task.dueDate == days(3))
        #expect(box.snoozeTask(query: "contract", until: "until friday").succeeded)
        #expect(task.dueDate.map { cal.component(.weekday, from: $0) } == 6)
    }

    // MARK: Priority, milestones, notes, search

    @Test func setPriorityAndUndo() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createTask(title: "Draft quarterly report")
        let task = try #require(box.services.tasks.all().first)
        #expect(box.setPriority(query: "quarterly", priority: "top priority").succeeded)
        #expect(task.priority == .urgent)
        #expect(!box.setPriority(query: "quarterly", priority: "purple").succeeded)
        _ = box.undo(scope: "step")
        #expect(task.priority == .normal)
    }

    @Test func listsMilestonesSoonestFirst() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createProject(name: "Website Redesign")
        _ = box.addMilestone(projectName: "website", title: "Launch", target: "in 30 days")
        _ = box.addMilestone(projectName: "website", title: "Design locked", target: "in 10 days")
        let result = box.listMilestones(projectName: "website redesign")
        #expect(result.succeeded)
        let lines = result.detail.components(separatedBy: "\n")
        #expect(lines[1].contains("Design locked"))
        #expect(lines[2].contains("Launch"))
        #expect(!box.listMilestones(projectName: "nope").succeeded)
    }

    @Test func appendNoteThroughTheRegistry() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createNote(title: "Meeting notes", body: "Sarah owns feedback.")
        let spec = try #require(AgentToolRegistry.all(toolbox: box).first { $0.name == "appendNote" })
        let result = spec.run(["query": "meeting", "text": "Sam sends the deck."])
        #expect(result.succeeded)
        #expect(box.services.notes.all().first?.body == "Sarah owns feedback.\n\nSam sends the deck.")
    }

    @Test func searchEverythingSpansKinds() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createTask(title: "Send the invoice")
        _ = box.createProject(name: "Invoice automation")
        _ = box.createNote(title: "Billing", body: "Every invoice goes out as PDF.")
        let result = box.searchEverything(query: "invoice")
        #expect(result.detail.contains("Task: Send the invoice"))
        #expect(result.detail.contains("Project: Invoice automation"))
        #expect(result.detail.contains("Note: Billing"))
    }

    // MARK: Fuzzy titles

    @Test func fuzzyTitleFallbackMatchesContentWords() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createTask(title: "Write launch copy")
        _ = box.createTask(title: "Plan the launch party")
        #expect(box.services.tasks.find(matching: "the launch copy")?.title == "Write launch copy")
        #expect(box.services.tasks.find(matching: "launch party")?.title == "Plan the launch party")
        // Not enough overlap → no guess.
        #expect(box.services.tasks.find(matching: "quarterly budget review") == nil)
    }
}
