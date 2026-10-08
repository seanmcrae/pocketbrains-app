import Foundation
import SwiftData
import Testing
@testable import PocketBrains

/// Per-request tool trimming for the Foundation Models brain.
@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct ToolSelectorTests {
    private func allTools() -> [String] {
        let container = Store.makeContainer(inMemory: true)
        defer { withExtendedLifetime(container) {} }
        let box = ToolBox(services: DataServices(context: container.mainContext),
                          semanticIndex: SemanticIndex(context: container.mainContext))
        return AgentToolRegistry.all(toolbox: box).map(\.name)
    }

    @Test func alwaysIncludesCoreToolsAndRespectsTheLimit() {
        let available = allTools()
        for request in ["Snooze clean the gutters for 3 days", "What's blocking the website redesign?",
                        "asdf qwerty", ""] {
            let selection = ToolSelector.select(request, available: available)
            #expect(selection.tools.count <= ToolSelector.defaultLimit)
            for core in ToolSelector.coreTools {
                #expect(selection.tools.contains(core), "\(core) missing for \"\(request)\"")
            }
        }
    }

    @Test func picksTheToolTheGrammarChooses() {
        let available = allTools()
        let cases: [(String, String)] = [
            ("Snooze clean the gutters for 3 days", "snoozeTask"),
            ("Make draft quarterly report urgent", "setPriority"),
            ("List milestones for Website Redesign", "listMilestones"),
            ("What do my notes say about the venue?", "askNotes"),
            ("Export today's tasks to Reminders", "exportToReminders"),
        ]
        for (request, tool) in cases {
            #expect(ToolSelector.select(request, available: available, limit: 6).tools.contains(tool),
                    "\(tool) not selected for \"\(request)\"")
        }
    }

    @Test func coversEveryStepOfACompoundRequest() {
        let selection = ToolSelector.select(
            "Create a project Launch, add 3 tasks for Friday and link it to brand voice",
            available: allTools())
        #expect(Set(["createProject", "createTask", "linkItems"]).isSubset(of: Set(selection.tools)))
    }

    @Test func neverOffersAToolThatIsNotAvailable() {
        // Integrations off: the Foundation Models brain does not offer them.
        let available = allTools().filter { $0 != "calendarAgenda" && $0 != "exportToReminders" }
        let selection = ToolSelector.select("What's on my calendar this afternoon?", available: available)
        #expect(!selection.tools.contains("calendarAgenda"))
        #expect(selection.tools.allSatisfy { available.contains($0) })
    }

    @Test func isDeterministicAndKeepsRegistryOrder() {
        let available = allTools()
        let request = "Move draft quarterly report to next Tuesday and make it urgent"
        let first = ToolSelector.select(request, available: available)
        #expect(first == ToolSelector.select(request, available: available))
        let positions = first.tools.compactMap { available.firstIndex(of: $0) }
        #expect(positions == positions.sorted())
    }

    @Test func cuesScoreWithoutAGrammarMatch() {
        // No grammar rule reads this, but its words point at milestones.
        let scores = ToolSelector.score("milestone dates please")
        #expect((scores["listMilestones"] ?? 0) > 0)
        #expect(ToolSelector.normalized("What's late?") == "what's late ")
    }
}
