import Foundation
import Testing
@testable import PocketBrains

@Suite(.serialized, .timeLimit(.minutes(1)))
struct NaturalDateParserTests {
    private let cal = Calendar.current

    @Test func parsesToday() throws {
        let date = try #require(NaturalDateParser.parse("today"))
        #expect(cal.isDateInToday(date))
    }

    @Test func parsesTomorrow() throws {
        let date = try #require(NaturalDateParser.parse("tomorrow"))
        #expect(cal.isDateInTomorrow(date))
    }

    @Test func parsesYesterday() throws {
        let date = try #require(NaturalDateParser.parse("yesterday"))
        #expect(cal.isDateInYesterday(date))
    }

    @Test func parsesWeekdayAsNextOccurrence() throws {
        let date = try #require(NaturalDateParser.parse("send the invoice on Friday"))
        #expect(cal.component(.weekday, from: date) == 6) // Friday
        #expect(date > Date.now.addingTimeInterval(-86400))
        #expect(date < Date.now.addingTimeInterval(8 * 86400))
    }

    @Test func parsesRelativeDays() throws {
        let date = try #require(NaturalDateParser.parse("in 3 days"))
        let expected = cal.date(byAdding: .day, value: 3, to: cal.startOfDay(for: .now))!
        #expect(cal.isDate(date, inSameDayAs: expected))
    }

    @Test func describesRelativeDates() {
        #expect(NaturalDateParser.describe(.now) == "Today")
        let tomorrow = cal.date(byAdding: .day, value: 1, to: .now)!
        #expect(NaturalDateParser.describe(tomorrow) == "Tomorrow")
        let lastWeek = cal.date(byAdding: .day, value: -8, to: .now)!
        #expect(NaturalDateParser.describe(lastWeek).contains("overdue"))
    }

    @Test func unparseableReturnsNil() {
        #expect(NaturalDateParser.parse("the heat death of the universe") == nil)
    }
}

/// Deterministic cases against a fixed reference: Wednesday 10 June 2026, noon.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct NaturalDateParserReferenceTests {
    private let cal = Calendar.current
    private var reference: Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 12))!
    }

    private func day(_ text: String) -> DateComponents? {
        NaturalDateParser.parse(text, from: reference)
            .map { cal.dateComponents([.year, .month, .day], from: $0) }
    }

    private func ymd(_ y: Int, _ m: Int, _ d: Int) -> DateComponents {
        DateComponents(year: y, month: m, day: d)
    }

    @Test func weekdayResolvesToNextOccurrence() {
        #expect(day("friday") == ymd(2026, 6, 12))
        #expect(day("Monday") == ymd(2026, 6, 15))
    }

    @Test func sameWeekdayMeansNextWeekNotToday() {
        #expect(day("wednesday") == ymd(2026, 6, 17))
    }

    @Test func relativePhrases() {
        #expect(day("today") == ymd(2026, 6, 10))
        #expect(day("tomorrow") == ymd(2026, 6, 11))
        #expect(day("yesterday") == ymd(2026, 6, 9))
        #expect(day("next week") == ymd(2026, 6, 17))
        #expect(day("in 1 day") == ymd(2026, 6, 11))
        #expect(day("in 10 days") == ymd(2026, 6, 20))
    }

    @Test func relativeDatesCrossMonthBoundaries() {
        #expect(day("in 25 days") == ymd(2026, 7, 5))
    }

    @Test func resultsAreStartOfDay() throws {
        let date = try #require(NaturalDateParser.parse("tomorrow", from: reference))
        #expect(cal.component(.hour, from: date) == 0)
        #expect(cal.component(.minute, from: date) == 0)
    }

    @Test func explicitCalendarDateUsesSystemDetector() {
        #expect(day("June 20, 2026") == ymd(2026, 6, 20))
    }
}
