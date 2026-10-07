import Foundation
import SwiftData
import Testing
@testable import PocketBrains

/// EventKit stays behind protocols; these mocks stand in for it.
@MainActor
final class MockCalendar: CalendarReading {
    var isAuthorized = true
    var stored: [CalendarEventInfo] = []
    private(set) var queries: [(Date, Date)] = []

    func requestAccess() async -> Bool { isAuthorized }
    func events(from start: Date, to end: Date) -> [CalendarEventInfo] {
        queries.append((start, end))
        return stored.filter { $0.end > start && $0.start < end }
    }
}

@MainActor
final class MockReminders: RemindersWriting {
    var isAuthorized = true
    var saved: [String: ReminderDraft] = [:]
    var failNext = false

    func requestAccess() async -> Bool { isAuthorized }
    func save(_ draft: ReminderDraft) throws -> String {
        if failNext { failNext = false; throw CocoaError(.fileWriteUnknown) }
        let id = "rem-\(saved.count + 1)"
        saved[id] = draft
        return id
    }
    func remove(identifier: String) throws { saved[identifier] = nil }
}

@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct IntegrationTests {
    private let cal = Calendar.current

    /// Settings live in a throwaway suite so tests never touch the user's defaults.
    private func makeBox(calendarOn: Bool = true, remindersOn: Bool = true)
        -> (ToolBox, ModelContainer, MockCalendar, MockReminders) {
        let container = Store.makeContainer(inMemory: true)
        let services = DataServices(context: container.mainContext)
        let box = ToolBox(services: services, semanticIndex: SemanticIndex(context: container.mainContext))
        let defaults = UserDefaults(suiteName: "pb.tests.\(UUID().uuidString)")!
        let settings = IntegrationSettings(defaults: defaults)
        settings.calendarEnabled = calendarOn
        settings.remindersEnabled = remindersOn
        let calendar = MockCalendar(), reminders = MockReminders()
        box.integrations = Integrations(calendar: calendar, reminders: reminders, settings: settings)
        return (box, container, calendar, reminders)
    }

    private func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0, from now: Date = .now) -> Date {
        let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: now))!
        return cal.date(byAdding: .minute, value: hour * 60 + minute, to: day)!
    }

    // MARK: Windows

    @Test func parsesDayWindows() {
        #expect(DayWindow.parse("what's my afternoon look like") == .init(dayOffset: 0, part: .afternoon))
        #expect(DayWindow.parse("tomorrow morning") == .init(dayOffset: 1, part: .morning))
        #expect(DayWindow.parse("tonight") == .init(dayOffset: 0, part: .evening))
        #expect(DayWindow.parse(nil) == .init(dayOffset: 0, part: .day))
        #expect(DayWindow.parse("tomorrow").label == "tomorrow")
    }

    @Test func afternoonWindowStartsNowWhenAlreadyUnderway() {
        let threePM = at(15)
        let window = DayWindow(dayOffset: 0, part: .afternoon).interval(now: threePM)
        #expect(window.start == threePM)
        #expect(window.end == at(17))
        let morning = DayWindow(dayOffset: 0, part: .afternoon).interval(now: at(9))
        #expect(morning.start == at(12))
    }

    // MARK: Agenda mapping

    @Test func agendaListsClippedEventsAllDayFirst() {
        let window = DateInterval(start: at(12), end: at(17))
        let events = [
            CalendarEventInfo(title: "Design review", start: at(14), end: at(15), location: "Room 2"),
            CalendarEventInfo(title: "Standup", start: at(9, 30), end: at(9, 45)),     // outside
            CalendarEventInfo(title: "Offsite", start: at(0), end: at(24), isAllDay: true),
            CalendarEventInfo(title: "Lunch", start: at(12, 30), end: at(13, 15)),
        ]
        let lines = AgendaComposer.describe(events, in: window)
        #expect(lines.count == 3)
        #expect(lines[0] == "All day: Offsite")
        #expect(lines[1].hasSuffix("Lunch"))
        #expect(lines[2].hasSuffix("Design review (Room 2)"))

        let gaps = AgendaComposer.freeGaps(events, in: window)
        // 13:15–14:00 and 15:00–17:00 are free; 12:00–12:30 too.
        #expect(gaps.count == 3)
        #expect(gaps.last?.start == at(15) && gaps.last?.end == at(17))
    }

    @Test func briefLineNamesTheNextEvent() {
        let events = [
            CalendarEventInfo(title: "Standup", start: at(9), end: at(9, 15)),
            CalendarEventInfo(title: "1:1 with Sam", start: at(11), end: at(11, 30)),
        ]
        let line = AgendaComposer.briefLine(events, now: at(10))
        #expect(line?.hasPrefix("2 events today · next: 1:1 with Sam") == true)
        #expect(AgendaComposer.briefLine([], now: at(10)) == nil)
    }

    @Test func calendarToolReadsTheRequestedWindow() {
        let (box, container, calendar, _) = makeBox()
        defer { withExtendedLifetime(container) {} }
        let now = at(10)
        calendar.stored = [CalendarEventInfo(title: "Design review", start: at(14, 0, from: now), end: at(15, 0, from: now))]
        _ = box.createTask(title: "Ship the deck", due: "today")
        let result = box.calendarAgenda(window: "this afternoon", now: now)
        #expect(result.succeeded)
        #expect(result.summary == "1 event this afternoon")
        #expect(result.detail.contains("Design review"))
        #expect(result.detail.contains("Tasks due: Ship the deck"))
        #expect(calendar.queries.first?.0 == at(12, 0, from: now))

        let routed = IntentFallbackBackend.routeIntent("What's my afternoon look like?", toolbox: box)
        #expect(routed.tool == "calendarAgenda")
    }

    @Test func calendarStaysOffUntilOptedIn() {
        let (box, container, calendar, _) = makeBox(calendarOn: false)
        defer { withExtendedLifetime(container) {} }
        let result = box.calendarAgenda(window: "today")
        #expect(!result.succeeded)
        #expect(result.detail.contains("Settings → Integrations"))
        #expect(calendar.queries.isEmpty) // never even asked EventKit

        let (box2, container2, calendar2, _) = makeBox()
        defer { withExtendedLifetime(container2) {} }
        calendar2.isAuthorized = false // switched on, but OS permission missing
        #expect(!box2.calendarAgenda(window: "today").succeeded)
    }

    // MARK: Reminders mapping & export

    @Test func reminderDraftMapsTitleDueProjectAndPriority() throws {
        let (box, container, _, _) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createProject(name: "Website Redesign")
        _ = box.createTask(title: "Approve hero photo", due: "tomorrow", priority: "urgent", projectName: "website")
        let task = try #require(box.services.tasks.all().first)
        let draft = ReminderMapper.draft(for: task)
        #expect(draft.title == "Approve hero photo")
        #expect(draft.priority == 1)
        #expect(draft.notes?.contains("Project: Website Redesign") == true)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now))!
        #expect(draft.due == cal.dateComponents([.year, .month, .day], from: tomorrow))
        #expect(ReminderMapper.priority(.low) == 9)
        #expect(ReminderMapper.priority(.normal) == 0)
    }

    @Test func exportIsIdempotentAndUndoable() {
        let (box, container, _, reminders) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createTask(title: "Pay rent", due: "today")
        _ = box.createTask(title: "Call the bank", due: "today")
        _ = box.createTask(title: "Someday idea")

        let first = box.exportToReminders(scope: "today")
        #expect(first.succeeded)
        #expect(first.outputs["count"] == "2")
        #expect(reminders.saved.count == 2)

        let again = box.exportToReminders(scope: "today")
        #expect(again.summary == "Already in Reminders")
        #expect(reminders.saved.count == 2)

        let undo = box.undo(scope: "step")
        #expect(undo.succeeded)
        #expect(reminders.saved.isEmpty)
        #expect(box.services.context.fetchAll(ReminderExport.self).isEmpty)
        // Tasks themselves are untouched by undoing the export.
        #expect(box.services.tasks.all().count == 3)

        let routed = IntentFallbackBackend.routeIntent("Send today's tasks to Reminders", toolbox: box)
        #expect(routed.tool == "exportToReminders")
        #expect(reminders.saved.count == 2)
    }

    @Test func exportStaysOffUntilOptedIn() {
        let (box, container, _, reminders) = makeBox(remindersOn: false)
        defer { withExtendedLifetime(container) {} }
        _ = box.createTask(title: "Pay rent", due: "today")
        #expect(!box.exportToReminders(scope: "today").succeeded)
        #expect(reminders.saved.isEmpty)
    }

    // MARK: Widget & intents

    @Test func widgetSnapshotOrdersOverdueThenDueThenUndated() throws {
        let (box, container, _, _) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createTask(title: "Undated")
        _ = box.createTask(title: "Friday thing", due: "in 4 days")
        _ = box.createTask(title: "Late thing", due: "yesterday", priority: "urgent")
        _ = box.createTask(title: "Today thing", due: "today")
        let brief = DailyBrief.compose(services: box.services)
        let snapshot = WidgetPublisher.makeSnapshot(brief: brief, tasks: box.services.tasks.all(), limit: 3)
        #expect(snapshot.items.map(\.title) == ["Late thing", "Today thing", "Friday thing"])
        #expect(snapshot.items.first?.isOverdue == true)
        #expect(snapshot.headline == brief.headline)

        // Round-trips through the JSON the widget reads.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pb-widget-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(snapshot.save(to: url))
        let loaded = try #require(WidgetSnapshot.load(from: url))
        #expect(loaded.items.map(\.title) == snapshot.items.map(\.title))
    }

    @Test func blockersDialogNamesWhatEachTaskWaitsOn() throws {
        let (box, container, _, _) = makeBox()
        defer { withExtendedLifetime(container) {} }
        _ = box.createProject(name: "Website Redesign")
        let project = try #require(box.services.projects.find(matching: "website"))
        let copy = box.services.tasks.create(title: "Write copy", project: project)
        let build = box.services.tasks.create(title: "Build site", project: project)
        box.services.tasks.addDependency(build, blockedBy: copy)
        #expect(IntentRuntime.blockersDialog(for: project) == "Website Redesign: “Build site” is waiting on Write copy.")
        box.services.tasks.complete(copy)
        #expect(IntentRuntime.blockersDialog(for: project).hasPrefix("Nothing is blocking Website Redesign"))
    }
}
