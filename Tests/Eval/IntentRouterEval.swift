import Foundation
import SwiftData
import Testing
@testable import PocketBrains

/// Reproducible tool-calling eval for the deterministic fallback router.
/// Each case runs against a fresh in-memory store seeded with the same
/// synthetic fixture, then is scored on:
///   - tool accuracy: the router chose the expected tool;
///   - end-to-end accuracy: right tool, the tool succeeded, and the parsed
///     arguments (title, due date, completed task) match the expectation.
/// Results print as `EVAL` lines, which CI copies into the job summary.
/// Any miss on canonical phrasing fails the test.
/// This measures the deterministic floor only; it says nothing about the
/// Foundation Models or MLX backends, which need real hardware.
@Suite(.serialized, .timeLimit(.minutes(3)))
@MainActor
struct IntentRouterEval {
    struct Outcome {
        let testCase: IntentEvalCase
        let routedTool: String?
        let toolCorrect: Bool
        let endToEnd: Bool
        let note: String
        let latency: Duration
    }

    static func seed(_ box: ToolBox) {
        let services = box.services
        let website = services.projects.create(name: "Website Redesign", summary: "Synthetic fixture project")
        _ = services.projects.create(name: "Q3 Planning", summary: "Synthetic fixture project")
        let copy = services.tasks.create(title: "Write launch copy", project: website)
        let page = services.tasks.create(title: "Build landing page", project: website)
        services.tasks.addDependency(page, blockedBy: copy)
        services.tasks.create(title: "Book flights for the offsite")
        services.tasks.create(title: "Send the invoice")
        services.tasks.create(title: "Renew passport")
        _ = box.createNote(title: "Brand voice", body: "Confident, plain, never loud.")
        _ = box.createNote(title: "Pricing research", body: "Annual plans convert better than monthly.")
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
        }
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
        var routed: (tool: String?, activity: String, result: ToolResult?, reply: String)!
        let latency = clock.measure {
            routed = IntentFallbackBackend.routeIntent(testCase.utterance, toolbox: box)
        }

        let toolCorrect = routed.tool == testCase.tool
        var problems: [String] = []
        if !toolCorrect { problems.append("routed to \(routed.tool ?? "nil")") }
        if routed.result?.succeeded != true { problems.append("tool did not succeed") }

        if testCase.title != nil || testCase.due != nil {
            if testCase.tool == "createProject" {
                let created = services.projects.all().first { !beforeProjects.contains($0.id) }
                if created?.name.lowercased() != testCase.title?.lowercased() {
                    problems.append("project name \"\(created?.name ?? "none")\"")
                }
            } else {
                let created = services.tasks.all(includeDone: true).first { !before.contains($0.id) }
                if let title = testCase.title, created?.title.lowercased() != title.lowercased() {
                    problems.append("title \"\(created?.title ?? "none")\"")
                }
                if let due = testCase.due {
                    let want = expectedDay(due)
                    let got = created?.dueDate.map { Calendar.current.startOfDay(for: $0) }
                    if want != got { problems.append("due \(got.map { "\($0)" } ?? "none")") }
                }
            }
        }
        if let completes = testCase.completes {
            let task = services.tasks.all(includeDone: true).first { $0.title == completes }
            if task?.isDone != true { problems.append("\"\(completes)\" not completed") }
        }

        return Outcome(testCase: testCase, routedTool: routed.tool, toolCorrect: toolCorrect,
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
        for testCase in IntentEvalCorpus.cases {
            #expect(toolNames.contains(testCase.tool), "unknown tool \(testCase.tool)")
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
            return "EVAL " + pad(label, 10) + " | " + pad(String(subset.count), 2) + " | " + pad(tool, 13) + " | " + e2e
        }

        print("EVAL Deterministic intent router, synthetic corpus (\(outcomes.count) utterances)")
        print("EVAL " + pad("category", 10) + " | n  | tool accuracy | end-to-end")
        for category in IntentEvalCase.Category.allCases {
            print(row(category.rawValue, outcomes.filter { $0.testCase.category == category }))
        }
        print(row("overall", outcomes))

        let micros: [Double] = outcomes.map { outcome in
            let parts = outcome.latency.components
            return Double(parts.seconds) * 1e6 + Double(parts.attoseconds) / 1e12
        }.sorted()
        let p50 = micros[micros.count / 2]
        let p95 = micros[min(micros.count - 1, Int(Double(micros.count) * 0.95))]
        print(String(format: "EVAL routing + tool execution latency (in-memory store, CI simulator): p50 %.2f ms, p95 %.2f ms",
                     p50 / 1000, p95 / 1000))

        // Regression gate. Canonical phrasing is the router's contract and
        // scored 100% when this gate was added, so any canonical miss fails
        // CI. Paraphrases are reported, not gated: tuning rules until they
        // pass would overfit the corpus, and paraphrase is the model's job.
        let canonical = outcomes.filter { $0.testCase.category == .canonical }
        for miss in canonical where !miss.endToEnd {
            Issue.record("Canonical eval regression: \"\(miss.testCase.utterance)\" -> \(miss.note)")
        }

        for miss in outcomes where !miss.endToEnd {
            let label = miss.testCase.category.rawValue
            print("EVAL miss [\(label)] expected \(miss.testCase.tool): \"\(miss.testCase.utterance)\" -> \(miss.note)")
        }
    }
}
