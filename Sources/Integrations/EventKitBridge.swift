import EventKit
import Foundation

/// The only file that touches EventKit. Reads calendar events for agenda
/// context and writes reminders on explicit export. Everything stays in the
/// system's on-device stores; PocketBrains itself makes no network calls.
/// (If the user syncs those calendars or lists with iCloud, the system does
/// that syncing, under the user's own account settings.)
@MainActor
enum EventKitBridge {
    /// One store per process, created on first opt-in use.
    static let store = EKEventStore()
}

@MainActor
final class EventKitCalendar: CalendarReading {
    private var store: EKEventStore { EventKitBridge.store }

    var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func events(from start: Date, to end: Date) -> [CalendarEventInfo] {
        guard isAuthorized else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { event in
            CalendarEventInfo(title: event.title ?? "Untitled event",
                              start: event.startDate, end: event.endDate,
                              isAllDay: event.isAllDay,
                              calendarName: event.calendar?.title ?? "",
                              location: event.location)
        }
    }
}

@MainActor
final class EventKitReminders: RemindersWriting {
    enum BridgeError: Error { case noDefaultList, notFound }

    private var store: EKEventStore { EventKitBridge.store }

    var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    func save(_ draft: ReminderDraft) throws -> String {
        guard let list = store.defaultCalendarForNewReminders() else { throw BridgeError.noDefaultList }
        let reminder = EKReminder(eventStore: store)
        reminder.title = draft.title
        reminder.notes = draft.notes
        reminder.dueDateComponents = draft.due
        reminder.priority = draft.priority
        reminder.calendar = list
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func remove(identifier: String) throws {
        guard let item = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw BridgeError.notFound
        }
        try store.remove(item, commit: true)
    }
}
