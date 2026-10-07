import Foundation
import Testing
@testable import PocketBrains

/// The prompted-tool-call envelope used by the MLX/Qwen3 backend.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ToolCallParserTests {
    @Test func parsesWellFormedCall() throws {
        let call = try #require(ToolCallParser.parse(
            #"<tool_call>{"name": "createTask", "arguments": {"title": "Send the invoice", "due": "Friday"}}</tool_call>"#))
        #expect(call.name == "createTask")
        #expect(call.arguments == ["title": "Send the invoice", "due": "Friday"])
    }

    @Test func ignoresProseAroundTheEnvelope() throws {
        let call = try #require(ToolCallParser.parse(
            "Sure, let me check.\n<tool_call>{\"name\": \"agenda\"}</tool_call>\nOne moment."))
        #expect(call.name == "agenda")
        #expect(call.arguments.isEmpty)
    }

    @Test func stringifiesScalarsAndDropsNullsAndNesting() throws {
        let call = try #require(ToolCallParser.parse(
            #"<tool_call>{"name": "queryTasks", "arguments": {"filter": "all", "limit": 5, "flag": true, "project": null, "extra": {"a": 1}}}</tool_call>"#))
        #expect(call.arguments == ["filter": "all", "limit": "5", "flag": "true"])
    }

    @Test(arguments: [
        "No tool call here.",
        "<tool_call>{not json}</tool_call>",
        #"<tool_call>{"arguments": {"title": "x"}}</tool_call>"#,
        #"<tool_call>{"name": "", "arguments": {}}</tool_call>"#,
        #"<tool_call>{"name": "agenda"}"#,
        #"</tool_call> stray <tool_call>{"name": "agenda"}"#,
    ])
    func rejectsMalformedOutput(_ text: String) {
        #expect(ToolCallParser.parse(text) == nil)
    }
}
