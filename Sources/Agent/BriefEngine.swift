import Foundation

/// The Morning Brief: the day, composed. Deterministic, warm, and honest —
/// the ritual that makes opening the app twice a day worth it.
struct DailyBrief {
    let weekday: String
    let dateLine: String
    let headline: String
    let focus: String?
    let overdue: Int
    let dueToday: Int
    let blocked: Int
    let doneYesterday: Int
    /// Opt-in calendar context, e.g. "3 events today · next: Standup at 10:00".
    var calendarLine: String? = nil

    var isQuiet: Bool { overdue + dueToday + blocked == 0 }

    /// Brief with calendar context when the Calendar integration is ready.
    @MainActor
    static func compose(services: DataServices, integrations: Integrations) -> DailyBrief {
        var brief = compose(services: services)
        if integrations.calendarReady {
            let today = DayWindow(dayOffset: 0, part: .day).interval(now: Calendar.current.startOfDay(for: .now))
            let events = integrations.calendar.events(from: today.start, to: today.end)
            brief.calendarLine = AgendaComposer.briefLine(events)
        }
        return brief
    }

    @MainActor
    static func compose(services: DataServices) -> DailyBrief {
        let cal = Calendar.current
        let open = services.tasks.all()
        let overdue = open.filter(\.isOverdue)
        let dueToday = open.filter {
            $0.dueDate.map { cal.isDateInToday($0) } ?? false && !$0.isOverdue
        }
        let blocked = open.filter { $0.isBlocked && !$0.isOverdue }
        let doneYesterday = services.tasks.all(includeDone: true).filter {
            $0.completedAt.map { cal.isDateInYesterday($0) } ?? false
        }.count

        let headline: String
        let pressing = overdue.count + dueToday.count
        switch (pressing, doneYesterday) {
        case (0, 0):  headline = "A clear morning."
        case (0, _):  headline = "Momentum, carried over."
        case (1, _):  headline = "One thing wants closing."
        case (2...3, _): headline = "\(spelled(pressing).capitalized) things want closing."
        default:      headline = "A full plate — start small."
        }

        // The single best next action: most urgent overdue, else today's
        // highest priority. One suggestion, never a lecture.
        let candidate = overdue.max { $0.priorityRaw < $1.priorityRaw }
            ?? dueToday.max { $0.priorityRaw < $1.priorityRaw }

        return DailyBrief(
            weekday: Date.now.formatted(.dateTime.weekday(.wide)),
            dateLine: Date.now.formatted(.dateTime.month(.wide).day()),
            headline: headline,
            focus: candidate.map { "Start with “\($0.title)”." },
            overdue: overdue.count,
            dueToday: dueToday.count,
            blocked: blocked.count,
            doneYesterday: doneYesterday)
    }

    private static func spelled(_ n: Int) -> String {
        switch n {
        case 2: return "two"
        case 3: return "three"
        default: return "\(n)"
        }
    }

    /// Day key for once-per-day gating, e.g. "2026-06-12".
    static var todayKey: String {
        Date.now.formatted(.iso8601.year().month().day())
    }
}

/// The evening pair to the Morning Brief: what got closed, and a quiet
/// invitation to capture loose ends before tomorrow.
struct EveningReflection {
    let doneCount: Int
    let highlights: [String]

    @MainActor
    static func compose(services: DataServices) -> EveningReflection {
        let cal = Calendar.current
        let done = services.tasks.all(includeDone: true)
            .filter { $0.completedAt.map { cal.isDateInToday($0) } ?? false }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        return EveningReflection(doneCount: done.count,
                                 highlights: done.prefix(3).map(\.title))
    }
}
