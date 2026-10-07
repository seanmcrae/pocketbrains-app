import Foundation
import SwiftData
import Testing
@testable import PocketBrains

/// Reproducible tool-calling eval for the deterministic fallback router.
/// Each case runs against a fresh in-memory store seeded with the same
/// synthetic fixture, through the same entry point the app uses
/// (`IntentFallbackBackend.routeTurn`, which plans compound requests), and is
/// scored on:
///   - tool accuracy: the router chose the expected tool (for compound
///     requests: the exact tool sequence);
///   - end-to-end accuracy: right tool(s), every call succeeded, and the
///     resulting state matches (title, due date, priority, repeat rule,
///     completion, filing, note text).
/// Results print as `EVAL` lines, which CI copies into the job summary.
/// Held-out misses are counted but never printed individually.
/// This measures the deterministic floor only; it says nothing about the
/// Foundation Models or MLX backends, which need real hardware.
@Suite(.serialized, .timeLimit(.minutes(3)))
@MainActor
struct IntentRouterEval {
    struct Outcome {
        let testCase: IntentEvalCase
        let routedTools: [String]
        let toolCorrect: Bool
        let endToEnd: Bool
        let note: String
        let latency: Duration
    }

    /// Splits that must score 100% end-to-end (the regression gate): the
    /// documented phrasing, single-step and multi-step.
    static func isGated(_ testCase: IntentEvalCase) -> Bool {
        testCase.category == .canonical || testCase.category == .compound
    }

    static func seed(_ box: ToolBox) {
        let services = box.services
        // v0.1 fixture (unchanged).
        let website = services.projects.create(name: "Website Redesign", summary: "Synthetic fixture project")
        let q3 = services.projects.create(name: "Q3 Planning", summary: "Synthetic fixture project")
        let copy = services.tasks.create(title: "Write launch copy", project: website)
        let page = services.tasks.create(title: "Build landing page", project: website)
        services.tasks.addDependency(page, blockedBy: copy)
        services.tasks.create(title: "Book flights for the offsite")
        services.tasks.create(title: "Send the invoice")
        services.tasks.create(title: "Renew passport")
        _ = box.createNote(title: "Brand voice", body: "Confident, plain, never loud.")
        _ = box.createNote(title: "Pricing research", body: "Annual plans convert better than monthly.")

        // v0.2 additions, distinct from every v0.1 title.
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        services.tasks.create(title: "Draft quarterly report",
                              due: cal.date(byAdding: .day, value: 1, to: today), project: q3)
        services.tasks.create(title: "Clean the gutters")
        services.tasks.create(title: "Pay the water bill", due: cal.date(byAdding: .day, value: 2, to: today))
        let pages = services.tasks.create(title: "Morning pages", due: today)
        services.tasks.setRecurrence(pages, Recurrence(kind: .daily))
        services.projects.addMilestone(to: website, title: "Design locked",
                                       target: cal.date(byAdding: .day, value: 10, to: today))
        _ = box.createNote(title: "Meeting notes", body: "Sarah owns the feedback round.")
        _ = box.createNote(title: "Offsite plan", body: "The venue holds 40 people. Flights land Thursday.")

        // Integrations: opted in, backed by mocks (no EventKit in the eval).
        let defaults = UserDefaults(suiteName: "pb.eval.\(UUID().uuidString)")!
        let settings = IntegrationSettings(defaults: defaults)
        settings.calendarEnabled = true
        settings.remindersEnabled = true
        let calendar = MockCalendar()
        calendar.stored = [CalendarEventInfo(
            title: "Design review",
            start: cal.date(byAdding: .hour, value: 14, to: today)!,
            end: cal.date(byAdding: .hour, value: 15, to: today)!)]
        box.integrations = Integrations(calendar: calendar, reminders: MockReminders(), settings: settings)
    }

    private func expectedDay(_ due: IntentEvalCase.Due) -> Date? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        switch due {
        case .undated: return nil
        case .daysFromToday(let n): return cal.date(byAdding: .day, value: n, to: today)
        case .nextWeekday(let weekday):
            return (1...7).lazy
                .compactMap { cal.date(byAdding: .day, value: $0, to: today) }
                .first { cal.component(.weekday, from: $0) == weekday }
        case .endOfMonth:
            let interval = cal.dateInterval(of: .month, for: today)!
            return cal.date(byAdding: .day, value: -1, to: interval.end)
        }
    }

    private func day(_ date: Date?) -> Date? {
        date.map { Calendar.current.startOfDay(for: $0) }
    }

    private func run(_ testCase: IntentEvalCase) -> Outcome {
        let container = Store.makeContainer(inMemory: true)
        defer { withExtendedLifetime(container) {} }
        let services = DataServices(context: container.mainContext)
        let box = ToolBox(services: services, semanticIndex: SemanticIndex(context: container.mainContext))
        Self.seed(box)
        let before = Set(services.tasks.all(includeDone: true).map(\.id))
        let beforeProjects = Set(services.projects.all().map(\.id))

        let clock = ContinuousClock()
        var turn: IntentFallbackBackend.Turn!
        let latency = clock.measure {
            turn = IntentFallbackBackend.routeTurn(testCase.utterance, toolbox: box)
        }

        let routed = turn.tools
        let toolCorrect: Bool
        if let steps = testCase.steps {
            toolCorrect = routed == steps
        } else {
            toolCorrect = routed.count == 1 && routed.first == testCase.tool
        }
        var problems: [String] = []
        if !toolCorrect { problems.append("routed to \(routed.isEmpty ? "nil" : routed.joined(separator: "+"))") }
        if turn.results.isEmpty || turn.results.contains(where: { !$0.succeeded }) {
            problems.append("tool did not succeed")
        }

        let created = services.tasks.all(includeDone: true).filter { !before.contains($0.id) }
        if testCase.title != nil || testCase.due != nil || testCase.repeats != nil {
            if testCase.tool == "createProject" && testCase.steps == nil {
                let project = services.projects.all().first { !beforeProjects.contains($0.id) }
                if project?.name.lowercased() != testCase.title?.lowercased() {
                    problems.append("project name \"\(project?.name ?? "none")\"")
                }
            } else {
                let task = created.first
                if let title = testCase.title, task?.title.lowercased() != title.lowercased() {
                    problems.append("title \"\(task?.title ?? "none")\"")
                }
                if let due = testCase.due, expectedDay(due) != day(task?.dueDate) {
                    problems.append("due \(day(task?.dueDate).map { "\($0)" } ?? "none")")
                }
                if let repeats = testCase.repeats {
                    let raw = task.flatMap { services.tasks.recurrence(of: $0)?.raw } ?? "none"
                    if raw != repeats { problems.append("repeats \(raw)") }
                }
            }
        }
        if let completes = testCase.completes {
            let task = services.tasks.all(includeDone: true).first { $0.title == completes && before.contains($0.id) }
            if task?.isDone != true { problems.append("\"\(completes)\" not completed") }
        }
        if let target = testCase.target {
            // The open task with that title (for a completed recurring task,
            // that is its freshly spawned next occurrence).
            let task = services.tasks.all().first { $0.title == target }
            if task == nil { problems.append("no open \"\(target)\"") }
            if let due = testCase.targetDue, expectedDay(due) != day(task?.dueDate) {
                problems.append("\(target) due \(day(task?.dueDate).map { "\($0)" } ?? "none")")
            }
            if let priority = testCase.targetPriority, task?.priority != priority {
                problems.append("\(target) priority \(task?.priority.label ?? "none")")
            }
            if let repeats = testCase.targetRepeats {
                let raw = task.flatMap { services.tasks.recurrence(of: $0)?.raw } ?? "none"
                if raw != repeats { problems.append("\(target) repeats \(raw)") }
            }
        }
        if let projectName = testCase.createdIn {
            let project = services.projects.all().first { $0.name == projectName && !beforeProjects.contains($0.id) }
            if project == nil { problems.append("project \(projectName) not created") }
            if created.isEmpty || created.contains(where: { $0.project?.id != project?.id }) {
                problems.append("tasks not filed under \(projectName)")
            }
        }
        if let check = testCase.noteContains {
            let note = services.notes.find(matching: check.note)
            if note?.body.contains(check.text) != true { problems.append("note \(check.note) lacks text") }
        }

        return Outcome(testCase: testCase, routedTools: routed, toolCorrect: toolCorrect,
                       endToEnd: problems.isEmpty, note: problems.joined(separator: "; "),
                       latency: latency)
    }

    static func percent(_ part: Int, _ whole: Int) -> String {
        whole == 0 ? "n/a" : String(format: "%.1f%%", 100 * Double(part) / Double(whole))
    }

    @Test func corpusIsWellFormed() {
        let container = Store.makeContainer(inMemory: true)
        defer { withExtendedLifetime(container) {} }
        let box = ToolBox(services: DataServices(context: container.mainContext),
                          semanticIndex: SemanticIndex(context: container.mainContext))
        let toolNames = Set(AgentToolRegistry.all(toolbox: box).map(\.name))
        let utterances = IntentEvalCorpus.cases.map(\.utterance)
        #expect(Set(utterances).count == utterances.count, "duplicate utterances")
        #expect(IntentEvalCorpus.cases.count >= 120)
        #expect(IntentEvalCorpus.v1.count == 40)
        for testCase in IntentEvalCorpus.cases {
            #expect(toolNames.contains(testCase.tool), "unknown tool \(testCase.tool)")
            for step in testCase.steps ?? [] {
                #expect(toolNames.contains(step), "unknown step tool \(step)")
            }
        }
    }

    @Test func routerEval() {
        let outcomes = IntentEvalCorpus.cases.map { run($0) }
        #expect(outcomes.count == IntentEvalCorpus.cases.count)

        func pad(_ text: String, _ width: Int) -> String {
            text.padding(toLength: max(width, text.count), withPad: " ", startingAt: 0)
        }
        func row(_ label: String, _ subset: [Outcome]) -> String {
            let tool = Self.percent(subset.filter(\.toolCorrect).count, subset.count)
            let e2e = Self.percent(subset.filter(\.endToEnd).count, subset.count)
            return "EVAL " + pad(label, 20) + " | " + pad(String(subset.count), 3) + " | " + pad(tool, 13) + " | " + e2e
        }
        let v1 = outcomes.filter { $0.testCase.origin == .v1 }
        let v2 = outcomes.filter { $0.testCase.origin == .v2 }

        print("EVAL Deterministic intent router, synthetic corpus (\(outcomes.count) utterances)")
        print("EVAL " + pad("split", 20) + " | n   | tool accuracy | end-to-end")
        print(row("v1 canonical", v1.filter { $0.testCase.category == .canonical }))
        print(row("v1 paraphrase", v1.filter { $0.testCase.category == .paraphrase }))
        print(row("v1 all (original 40)", v1))
        print(row("v2 canonical", v2.filter { $0.testCase.category == .canonical }))
        print(row("v2 compound", v2.filter { $0.testCase.category == .compound }))
        print(row("v2 paraphrase (dev)", v2.filter { $0.testCase.category == .paraphrase }))
        print(row("v2 held-out", v2.filter { $0.testCase.category == .heldout }))
        print(row("overall", outcomes))

        let micros: [Double] = outcomes.map { outcome in
            let parts = outcome.latency.components
            return Double(parts.seconds) * 1e6 + Double(parts.attoseconds) / 1e12
        }.sorted()
        let p50 = micros[micros.count / 2]
        let p95 = micros[min(micros.count - 1, Int(Double(micros.count) * 0.95))]
        print(String(format: "EVAL routing + tool execution latency (in-memory store, CI simulator): p50 %.2f ms, p95 %.2f ms",
                     p50 / 1000, p95 / 1000))

        // Regression gate: canonical phrasing (and the documented compound
        // forms) is the router's contract.
        // Paraphrases are reported, not gated: tuning rules until they pass
        // would overfit, and paraphrase is the language model's job.
        for miss in outcomes where Self.isGated(miss.testCase) && !miss.endToEnd {
            Issue.record("Canonical eval regression: \"\(miss.testCase.utterance)\" -> \(miss.note)")
        }

        for miss in outcomes where !miss.endToEnd && miss.testCase.category != .heldout {
            let label = "\(miss.testCase.origin.rawValue) \(miss.testCase.category.rawValue)"
            print("EVAL miss [\(label)] expected \(miss.testCase.steps?.joined(separator: "+") ?? miss.testCase.tool): \"\(miss.testCase.utterance)\" -> \(miss.note)")
        }
        let heldoutMisses = outcomes.filter { $0.testCase.category == .heldout && !$0.endToEnd }.count
        print("EVAL held-out misses: \(heldoutMisses) (not itemized, by design)")
    }
}
