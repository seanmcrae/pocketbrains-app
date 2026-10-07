import Foundation

/// Turns "Friday", "tomorrow", "next Tues afternoon", "in a fortnight",
/// "end of month", "every other Monday", "June 20" into Dates.
/// Used by every brain to harden tool arguments, and by the deterministic
/// router, which also needs to know *which words* were the date so it can cut
/// exactly those out of a task title (`match(_:)` returns the phrase).
///
/// Conventions:
/// - Results are the start of the day unless a time of day is given
///   ("afternoon" → 15:00, "morning" → 9:00, "evening" → 18:00,
///   "tonight" → 20:00, "noon" → 12:00, "at 4pm" → 16:00).
/// - A bare, "this", "on", "by" or "next" weekday means its next occurrence
///   after today ("next Tuesday" on a Monday is tomorrow-plus-one, not a
///   week later); "every other Monday" resolves to the next Monday.
/// - "end of week" is the coming Friday; "end of month" its last day.
enum NaturalDateParser {
    struct Match: Equatable {
        let date: Date
        /// The lowercased words that expressed the date, including a leading
        /// "on/by/for/due/before/until" — exactly what to excise from a title.
        let phrase: String
    }

    static func parse(_ text: String, from reference: Date = .now) -> Date? {
        match(text, from: reference)?.date
    }

    // MARK: - Matching

    static let weekdayPatterns: [(pattern: String, weekday: Int)] = [
        // Full names anywhere; short forms (except ambiguous sat/sun) on
        // word boundaries; sat/sun only after a date preposition.
        (#"sundays?|(?:(?<=on |next |this |by |until )sun\b)"#, 1),
        (#"mondays?|\bmon\b"#, 2),
        (#"tuesdays?|\btues?\b"#, 3),
        (#"wednesdays?|\bweds?\b"#, 4),
        (#"thursdays?|\bthu(?:rs?)?\b"#, 5),
        (#"fridays?|\bfri\b"#, 6),
        (#"saturdays?|(?:(?<=on |next |this |by |until )sat\b)"#, 7),
    ]

    static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "a couple of": 2, "a few": 3, "couple of": 2,
    ]

    private static let count = #"(\d+|an?|one|two|three|four|five|six|seven|eight|nine|ten|a couple of|couple of|a few)"#
    private static let lead = #"(?:(?:on|by|for|due|before|until|till|starting|from)\s+)?"#

    static func match(_ text: String, from reference: Date = .now) -> Match? {
        let lower = text.lowercased()
        let cal = Calendar.current
        let today = cal.startOfDay(for: reference)
        func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today)! }

        var found: (Date, Range<String.Index>)?

        // Fixed relative words (most specific first).
        let fixed: [(String, () -> Date)] = [
            (#"\bthe day after tomorrow\b|\bday after tomorrow\b"#, { day(2) }),
            (#"\btoday\b|\btonight\b|\bthis (?:morning|afternoon|evening)\b|\bend of (?:the )?day\b|\beod\b"#, { day(0) }),
            (#"\byesterday\b"#, { day(-1) }),
            (#"\btomorrow\b"#, { day(1) }),
        ]
        for (pattern, make) in fixed where found == nil {
            if let r = lower.range(of: pattern, options: .regularExpression) { found = (make(), r) }
        }

        // "in a fortnight", "in 3 days", "in two weeks", "in a month".
        if found == nil, let r = lower.range(of: #"\bin (?:a )?fortnight\b"#, options: .regularExpression) {
            found = (day(14), r)
        }
        if found == nil, let r = lower.range(of: #"\bin \#(count) (days?|weeks?|months?)\b"#, options: .regularExpression),
           let shift = shift(in: String(lower[r])) {
            found = (cal.date(byAdding: shift, to: today)!, r)
        }
        // "a week from today", "two weeks from now".
        if found == nil, let r = lower.range(of: #"\b\#(count) (days?|weeks?) from (?:today|now)\b"#, options: .regularExpression),
           let shift = shift(in: String(lower[r])) {
            found = (cal.date(byAdding: shift, to: today)!, r)
        }

        // End of week / month / year.
        if found == nil, let r = lower.range(of: #"\b(?:the )?end of (?:the |this )?(week|month|year)\b"#, options: .regularExpression) {
            let unit = String(lower[r])
            if unit.hasSuffix("week") {
                found = (nextWeekday(6, from: reference, includingToday: true), r)
            } else if unit.hasSuffix("month") {
                let interval = cal.dateInterval(of: .month, for: today)!
                found = (cal.date(byAdding: .day, value: -1, to: interval.end)!, r)
            } else {
                let interval = cal.dateInterval(of: .year, for: today)!
                found = (cal.date(byAdding: .day, value: -1, to: interval.end)!, r)
            }
        }

        // Next week / month / weekend.
        if found == nil, let r = lower.range(of: #"\bnext week\b"#, options: .regularExpression) {
            found = (day(7), r)
        }
        if found == nil, let r = lower.range(of: #"\bnext month\b"#, options: .regularExpression) {
            let start = cal.dateInterval(of: .month, for: today)!.end
            found = (start, r)
        }
        if found == nil, let r = lower.range(of: #"\b(?:this|next|the) weekend\b|\bweekend\b"#, options: .regularExpression) {
            let isNext = lower[r].hasPrefix("next")
            var saturday = nextWeekday(7, from: reference, includingToday: true)
            if isNext, cal.isDate(saturday, equalTo: today, toGranularity: .weekOfYear) {
                saturday = cal.date(byAdding: .day, value: 7, to: saturday)!
            }
            found = (saturday, r)
        }

        // Weekdays: "friday", "next tues", "on Monday", "every other Monday".
        if found == nil {
            var best: (Int, Range<String.Index>)?
            for (pattern, weekday) in weekdayPatterns {
                guard let r = lower.range(of: pattern, options: .regularExpression) else { continue }
                if best == nil || r.lowerBound < best!.1.lowerBound { best = (weekday, r) }
            }
            if case let (weekday, r)? = best {
                var range = r
                // Absorb the modifier so it leaves the title too.
                let prefix = lower[..<range.lowerBound]
                if let m = prefix.range(of: #"(?:every other |every second |every |this |next )$"#, options: .regularExpression) {
                    range = m.lowerBound..<range.upperBound
                }
                found = (nextWeekday(weekday, from: reference), range)
            }
        }

        // Explicit dates ("June 20", "2026-07-01") via the system detector.
        if found == nil,
           let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
           let result = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let date = result.date,
           let r = Range(result.range, in: text) {
            // Map the original-string range onto `lower` by offsets.
            let start = text.distance(from: text.startIndex, to: r.lowerBound)
            let length = text.distance(from: r.lowerBound, to: r.upperBound)
            if let lo = lower.index(lower.startIndex, offsetBy: start, limitedBy: lower.endIndex),
               let hi = lower.index(lo, offsetBy: length, limitedBy: lower.endIndex) {
                return Match(date: date, phrase: expandLead(lower, lo..<hi))
            }
            return Match(date: date, phrase: String(lower[...].prefix(0)))
        }

        guard case let (date, range)? = found else { return nil }

        // Time of day right after (or before) the date: "next Tues afternoon",
        // "tomorrow at 4pm", "Friday morning".
        var span = range
        var result = date
        let after = lower[span.upperBound...]
        if let t = after.range(of: #"^\s*(?:at\s+)?(?:in the\s+)?(morning|afternoon|evening|night|noon|midday|\d{1,2}(?::\d{2})?\s*(?:am|pm)|\d{1,2}:\d{2})\b"#,
                               options: .regularExpression) {
            if let time = timeOfDay(String(after[t])) {
                result = cal.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: date) ?? date
            }
            span = span.lowerBound..<t.upperBound
        } else if let time = timeOfDay(String(lower[range])), time.hour > 0 {
            // "tonight", "this afternoon" carry their own time.
            result = cal.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: date) ?? date
        }
        return Match(date: result, phrase: expandLead(lower, span))
    }

    /// Include a preceding "on/by/for/due/before/until" in the phrase.
    private static func expandLead(_ lower: String, _ range: Range<String.Index>) -> String {
        let prefix = lower[..<range.lowerBound]
        if let m = prefix.range(of: #"\b(?:on|by|for|due|before|until|till|starting|from)\s+$"#, options: .regularExpression) {
            return String(lower[m.lowerBound..<range.upperBound]).trimmingCharacters(in: .whitespaces)
        }
        return String(lower[range]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Pieces

    /// Next occurrence of a weekday (1 = Sunday) strictly after `reference`'s
    /// day, or including it when `includingToday`.
    static func nextWeekday(_ weekday: Int, from reference: Date = .now, includingToday: Bool = false) -> Date {
        let cal = Calendar.current
        var date = cal.startOfDay(for: reference)
        if includingToday, cal.component(.weekday, from: date) == weekday { return date }
        for _ in 0..<8 {
            date = cal.date(byAdding: .day, value: 1, to: date)!
            if cal.component(.weekday, from: date) == weekday { return date }
        }
        return date
    }

    /// "2 days", "a week", "three weeks", "a fortnight", "a month" → offset.
    static func shift(in text: String) -> DateComponents? {
        let lower = text.lowercased()
        if lower.range(of: #"\b(?:a |one )?fortnight\b"#, options: .regularExpression) != nil {
            return DateComponents(day: 14)
        }
        guard let r = lower.range(of: #"\#(count) (days?|weeks?|months?)\b"#, options: .regularExpression) else {
            return nil
        }
        let phrase = String(lower[r])
        let unitWord = phrase.split(separator: " ").last.map(String.init) ?? "days"
        let countText = String(phrase.dropLast(unitWord.count)).trimmingCharacters(in: .whitespaces)
        guard let n = Int(countText) ?? numberWords[countText] else { return nil }
        if unitWord.hasPrefix("week") { return DateComponents(day: 7 * n) }
        if unitWord.hasPrefix("month") { return DateComponents(month: n) }
        return DateComponents(day: n)
    }

    /// Whole days in a shift ("2 days" → 2, "a week" → 7); months count 30.
    static func days(in text: String) -> Int? {
        guard let shift = shift(in: text) else { return nil }
        return (shift.day ?? 0) + 30 * (shift.month ?? 0)
    }

    static func timeOfDay(_ text: String) -> (hour: Int, minute: Int)? {
        let lower = text.lowercased()
        if lower.contains("morning") { return (9, 0) }
        if lower.contains("afternoon") { return (15, 0) }
        if lower.contains("evening") { return (18, 0) }
        if lower.contains("tonight") || lower.contains("night") { return (20, 0) }
        if lower.contains("noon") || lower.contains("midday") { return (12, 0) }
        guard let r = lower.range(of: #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#, options: .regularExpression) else { return nil }
        let token = String(lower[r])
        let digits = token.prefix { $0.isNumber }
        guard var hour = Int(digits) else { return nil }
        var minute = 0
        if let colon = token.firstIndex(of: ":") {
            minute = Int(token[token.index(after: colon)...].prefix { $0.isNumber }) ?? 0
        }
        if token.contains("pm"), hour < 12 { hour += 12 }
        if token.contains("am"), hour == 12 { hour = 0 }
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        // A bare number with neither am/pm nor a colon isn't a time.
        if !token.contains("am") && !token.contains("pm") && !token.contains(":") { return nil }
        return (hour, minute)
    }

    /// Human phrasing for the UI: "Today", "Tomorrow", "Friday", "Jun 24".
    static func describe(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        if date < .now { return date.formatted(.dateTime.month(.abbreviated).day()) + " · overdue" }
        if let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: date).day,
           days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
