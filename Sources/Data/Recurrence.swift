import Foundation
import SwiftData

/// A repeat rule attached to a task. Kept beside TaskItem rather than as a
/// new TaskItem attribute: TaskItem is the model that historically trapped
/// on insert (see AAStoreDiagnostics), and a separate entity needs no
/// migration of existing rows. When a recurring task is completed, the next
/// occurrence is created and the rule moves to it.
@Model
final class RecurrenceRule {
    @Attribute(.unique) var taskID: UUID
    /// `Recurrence.raw`, e.g. "daily", "weekdays", "weekly:2", "days:3".
    var ruleRaw: String
    var createdAt: Date

    init(taskID: UUID, rule: Recurrence) {
        self.taskID = taskID
        self.ruleRaw = rule.raw
        self.createdAt = .now
    }

    var rule: Recurrence? { Recurrence(raw: ruleRaw) }
}

/// Daily, weekdays, every N weeks, or every N days.
struct Recurrence: Equatable {
    enum Kind: String { case daily, weekdays, weekly, days }

    var kind: Kind
    /// Weeks for `.weekly`, days for `.days`; 1 otherwise.
    var every: Int = 1

    var raw: String {
        switch kind {
        case .daily, .weekdays: return kind.rawValue
        case .weekly, .days: return "\(kind.rawValue):\(every)"
        }
    }

    init(kind: Kind, every: Int = 1) {
        self.kind = kind
        self.every = max(1, every)
    }

    init?(raw: String) {
        let parts = raw.split(separator: ":").map(String.init)
        guard let kind = parts.first.flatMap(Kind.init(rawValue:)) else { return nil }
        let n = parts.count > 1 ? Int(parts[1]) ?? 1 : 1
        self.init(kind: kind, every: n)
    }

    var label: String {
        switch kind {
        case .daily: return "every day"
        case .weekdays: return "every weekday"
        case .weekly: return every == 1 ? "every week" : every == 2 ? "every other week" : "every \(every) weeks"
        case .days: return every == 1 ? "every day" : "every \(every) days"
        }
    }

    /// The next due date strictly after `date`.
    func next(after date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        switch kind {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: day)!
        case .days:
            return calendar.date(byAdding: .day, value: every, to: day)!
        case .weekly:
            return calendar.date(byAdding: .day, value: 7 * every, to: day)!
        case .weekdays:
            var candidate = calendar.date(byAdding: .day, value: 1, to: day)!
            while calendar.isDateInWeekend(candidate) {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate)!
            }
            return candidate
        }
    }

    /// Next occurrence after completing an instance due `due` (or undated),
    /// never in the past: a daily task finished three days late comes back
    /// today, not three days ago.
    func nextOccurrence(afterCompleting due: Date?, now: Date = .now,
                        calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        var next = self.next(after: due ?? today, calendar: calendar)
        var guardCount = 0
        while next < today && guardCount < 3660 {
            next = self.next(after: next, calendar: calendar)
            guardCount += 1
        }
        return next
    }

    // MARK: Parsing

    /// The words that expressed a repeat rule, lowercased, so the router can
    /// cut them out of a task title ("take out the bins every other
    /// Thursday" → "take out the bins").
    static func phrase(in text: String) -> String? {
        let lower = text.lowercased()
        let days = "sunday|monday|tuesday|wednesday|thursday|friday|saturday"
        let parts = #"(?:\s+(?:morning|afternoon|evening|night))?"#
        let patterns = [
            #"\bevery (?:other|second) (?:week|"# + days + #")s?\b"# + parts,
            #"\b(?:bi-?weekly|fortnightly|every fortnight)\b"#,
            #"\bevery (?:\d+|two|three|four|five|six) (?:days?|weeks?)\b"#,
            #"\b(?:every|each) (?:weekday|work ?day)\b|\b(?:on )?weekdays\b"#,
            #"\b(?:every|each) (?:day|morning|evening|night)\b|\b(?:daily|nightly)\b"#,
            #"\b(?:every|each) week\b|\bweekly\b"#,
            #"\b(?:every|each) (?:"# + days + #")s?\b"# + parts,
            #"\b(?:on )?(?:sundays|mondays|tuesdays|wednesdays|thursdays|fridays|saturdays)\b"#,
        ]
        for pattern in patterns {
            if let r = lower.range(of: pattern, options: .regularExpression) {
                return String(lower[r])
            }
        }
        return nil
    }

    /// "every day", "daily", "every weekday", "weekdays", "weekly",
    /// "every week", "every other Monday", "every 3 days", "every 2 weeks",
    /// "every Monday", "biweekly", "fortnightly". Returns the rule and, for
    /// weekday-anchored phrases, the weekday (1 = Sunday) the first due
    /// date should fall on.
    static func parse(_ text: String) -> (rule: Recurrence, anchorWeekday: Int?)? {
        let lower = " " + text.lowercased() + " "
        func has(_ pattern: String) -> Bool {
            lower.range(of: pattern, options: .regularExpression) != nil
        }
        let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        var anchor: Int?
        for (i, name) in weekdays.enumerated() where has("\\b\(name)s?\\b") { anchor = i + 1 }

        if has(#"\bevery (other|second) (week|sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#)
            || has(#"\b(bi-?weekly|fortnightly)\b"#) || has(#"\bevery fortnight\b"#) {
            return (Recurrence(kind: .weekly, every: 2), anchor)
        }
        if let match = lower.range(of: #"\bevery (\d+|two|three|four|five|six) (day|days|week|weeks)\b"#,
                                   options: .regularExpression) {
            let words = lower[match].split(separator: " ").map(String.init)
            let n = Int(words[1]) ?? ["two": 2, "three": 3, "four": 4, "five": 5, "six": 6][words[1]] ?? 1
            let isWeeks = words[2].hasPrefix("week")
            return (Recurrence(kind: isWeeks ? .weekly : .days, every: n), isWeeks ? anchor : nil)
        }
        if has(#"\b(every|each) (weekday|work ?day)\b"#) || has(#"\bweekdays\b"#) || has(#"\bmonday to friday\b"#) {
            return (Recurrence(kind: .weekdays), nil)
        }
        if has(#"\b(every|each) (day|morning|evening|night)\b"#) || has(#"\bdaily\b"#) || has(#"\bnightly\b"#) {
            return (Recurrence(kind: .daily), nil)
        }
        if has(#"\b(every|each) week\b"#) || has(#"\bweekly\b"#) {
            return (Recurrence(kind: .weekly), anchor)
        }
        // "every Monday" / "on Mondays" — a bare "on Monday" is a one-off date.
        if has(#"\b(every|each) (sunday|monday|tuesday|wednesday|thursday|friday|saturday)s?\b"#)
            || has(#"\b(sundays|mondays|tuesdays|wednesdays|thursdays|fridays|saturdays)\b"#) {
            return (Recurrence(kind: .weekly), anchor)
        }
        return nil
    }
}
