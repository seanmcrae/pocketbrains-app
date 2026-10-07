import Foundation

// MARK: - Protocols (EventKit stays behind these, so mapping logic is testable)

/// A calendar event, reduced to what the agent may read.
struct CalendarEventInfo: Equatable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool = false
    var calendarName: String = ""
    var location: String? = nil
}

@MainActor
protocol CalendarReading: AnyObject {
    var isAuthorized: Bool { get }
    func requestAccess() async -> Bool
    func events(from start: Date, to end: Date) -> [CalendarEventInfo]
}

/// What PocketBrains writes into Reminders for one task.
struct ReminderDraft: Equatable {
    var title: String
    var notes: String?
    var due: DateComponents?
    /// EventKit priority: 0 none, 1 high … 5 medium … 9 low.
    var priority: Int
}

@MainActor
protocol RemindersWriting: AnyObject {
    var isAuthorized: Bool { get }
    func requestAccess() async -> Bool
    /// Returns the new reminder's identifier.
    func save(_ draft: ReminderDraft) throws -> String
    func remove(identifier: String) throws
}

/// The integrations the toolbox can use. Live EventKit by default; tests
/// inject mocks. Both are opt-in: nothing is read or written unless the user
/// switched the integration on in Settings and granted the OS permission.
@MainActor
final class Integrations {
    private var calendarOverride: CalendarReading?
    private var remindersOverride: RemindersWriting?
    let settings: IntegrationSettings

    init(calendar: CalendarReading? = nil, reminders: RemindersWriting? = nil,
         settings: IntegrationSettings = .standard) {
        self.calendarOverride = calendar
        self.remindersOverride = reminders
        self.settings = settings
    }

    // The EventKit bridges are created lazily, on first opt-in use, never at launch.
    private lazy var liveCalendar: CalendarReading = EventKitCalendar()
    private lazy var liveReminders: RemindersWriting = EventKitReminders()

    var calendar: CalendarReading { calendarOverride ?? liveCalendar }
    var reminders: RemindersWriting { remindersOverride ?? liveReminders }

    /// Usable only when switched on in Settings AND authorized by the OS.
    var calendarReady: Bool { settings.calendarEnabled && calendar.isAuthorized }
    var remindersReady: Bool { settings.remindersEnabled && reminders.isAuthorized }
}

/// Opt-in switches, stored locally.
struct IntegrationSettings {
    var defaults: UserDefaults

    static var standard: IntegrationSettings { IntegrationSettings(defaults: .standard) }

    static let calendarKey = "pb.integrations.calendar"
    static let remindersKey = "pb.integrations.reminders"

    var calendarEnabled: Bool {
        get { defaults.bool(forKey: Self.calendarKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.calendarKey) }
    }
    var remindersEnabled: Bool {
        get { defaults.bool(forKey: Self.remindersKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.remindersKey) }
    }
}

// MARK: - Day windows

/// "this afternoon", "tomorrow morning", "today" → a concrete interval.
struct DayWindow: Equatable {
    enum Part: String { case day, morning, afternoon, evening }

    var dayOffset: Int
    var part: Part

    static func parse(_ text: String?) -> DayWindow {
        let lower = (text ?? "").lowercased()
        var offset = 0
        if lower.contains("tomorrow") { offset = 1 }
        let part: Part
        if lower.contains("morning") { part = .morning }
        else if lower.contains("afternoon") { part = .afternoon }
        else if lower.contains("evening") || lower.contains("tonight") || lower.contains("night") { part = .evening }
        else { part = .day }
        return DayWindow(dayOffset: offset, part: part)
    }

    func interval(now: Date = .now, calendar: Calendar = .current) -> DateInterval {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now))!
        func at(_ hour: Int) -> Date { calendar.date(byAdding: .hour, value: hour, to: day)! }
        let range: (Int, Int)
        switch part {
        case .day: range = (0, 24)
        case .morning: range = (6, 12)
        case .afternoon: range = (12, 17)
        case .evening: range = (17, 24)
        }
        var start = at(range.0)
        // "What's my afternoon look like" at 3pm means the rest of it.
        if dayOffset == 0, now > start, now < at(range.1) { start = now }
        return DateInterval(start: start, end: at(range.1))
    }

    var label: String {
        let day = dayOffset == 1 ? "tomorrow" : "today"
        switch part {
        case .day: return day
        case .morning, .afternoon, .evening:
            return dayOffset == 1 ? "tomorrow \(part.rawValue)" : "this \(part.rawValue)"
        }
    }
}

// MARK: - Mapping (pure, unit-tested)

enum AgendaComposer {
    /// Lines describing the events of a window, earliest first. All-day
    /// events come first; events are clipped to the window.
    static func describe(_ events: [CalendarEventInfo], in window: DateInterval,
                         calendar: Calendar = .current) -> [String] {
        let relevant = events
            .filter { $0.end > window.start && $0.start < window.end }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
        return relevant.map { event in
            if event.isAllDay { return "All day: \(event.title)" }
            let start = event.start.formatted(.dateTime.hour().minute())
            let end = event.end.formatted(.dateTime.hour().minute())
            var line = "\(start)–\(end) \(event.title)"
            if let location = event.location, !location.isEmpty { line += " (\(location))" }
            return line
        }
    }

    /// Free stretches of at least `minimum` between timed events.
    static func freeGaps(_ events: [CalendarEventInfo], in window: DateInterval,
                         minimum: TimeInterval = 30 * 60) -> [DateInterval] {
        let busy = events.filter { !$0.isAllDay && $0.end > window.start && $0.start < window.end }
            .map { DateInterval(start: max($0.start, window.start), end: min($0.end, window.end)) }
            .sorted { $0.start < $1.start }
        var gaps: [DateInterval] = []
        var cursor = window.start
        for block in busy {
            if block.start.timeIntervalSince(cursor) >= minimum {
                gaps.append(DateInterval(start: cursor, end: block.start))
            }
            cursor = max(cursor, block.end)
        }
        if window.end.timeIntervalSince(cursor) >= minimum {
            gaps.append(DateInterval(start: cursor, end: window.end))
        }
        return gaps
    }

    /// One-line calendar context for the Morning Brief.
    static func briefLine(_ events: [CalendarEventInfo], now: Date = .now) -> String? {
        let timed = events.filter { !$0.isAllDay }.sorted { $0.start < $1.start }
        guard !events.isEmpty else { return nil }
        var line = "\(events.count) event\(events.count == 1 ? "" : "s") today"
        if let next = timed.first(where: { $0.start >= now }) {
            line += " · next: \(next.title) at \(next.start.formatted(.dateTime.hour().minute()))"
        }
        return line
    }
}

enum ReminderMapper {
    static func priority(_ priority: TaskPriority) -> Int {
        switch priority {
        case .urgent: return 1
        case .high: return 3
        case .normal: return 0
        case .low: return 9
        }
    }

    static func draft(for task: TaskItem, calendar: Calendar = .current) -> ReminderDraft {
        var notes: [String] = []
        if let project = task.project { notes.append("Project: \(project.name)") }
        if !task.details.isEmpty { notes.append(task.details) }
        notes.append("From PocketBrains")
        return ReminderDraft(
            title: task.title,
            notes: notes.joined(separator: "\n"),
            due: task.dueDate.map { calendar.dateComponents([.year, .month, .day], from: $0) },
            priority: priority(task.priority))
    }
}
