import Foundation

/// Parses the JSON tool-call envelope that prompted (non-native) backends
/// emit, e.g. the MLX/Qwen3 path:
///
///     <tool_call>{"name": "createTask", "arguments": {"title": "…"}}</tool_call>
///
/// Lives outside the `POCKETBRAINS_MLX` flag so it is compiled and tested in
/// every build, not only when the optional MLX package is linked.
enum ToolCallParser {
    struct Call: Equatable {
        let name: String
        let arguments: [String: String]
    }

    static func parse(_ text: String) -> Call? {
        guard let open = text.range(of: "<tool_call>"),
              let close = text.range(of: "</tool_call>", range: open.upperBound..<text.endIndex)
        else { return nil }
        return decode(text[open.upperBound..<close.lowerBound])
    }

    /// Every well-formed envelope, in order. Several calls in one reply are
    /// executed as a multi-step plan; `$N` in an argument refers to what call
    /// N created. Malformed envelopes are skipped, not fatal.
    static func parseAll(_ text: String) -> [Call] {
        var calls: [Call] = []
        var searchStart = text.startIndex
        while let open = text.range(of: "<tool_call>", range: searchStart..<text.endIndex),
              let close = text.range(of: "</tool_call>", range: open.upperBound..<text.endIndex) {
            if let call = decode(text[open.upperBound..<close.lowerBound]) { calls.append(call) }
            searchStart = close.upperBound
        }
        return calls
    }

    /// The calls as a plan when there are two or more.
    static func plan(from text: String, goal: String) -> AgentPlan? {
        let calls = parseAll(text)
        guard calls.count >= 2 else { return nil }
        return AgentPlan(goal: goal, steps: calls.map { PlanStep(tool: $0.name, arguments: $0.arguments) })
    }

    private static func decode(_ json: Substring) -> Call? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["name"] as? String,
              !name.isEmpty
        else { return nil }
        let rawArgs = object["arguments"] as? [String: Any] ?? [:]
        // Models sometimes emit numbers or booleans for string parameters;
        // stringify scalars, drop nulls and nested structures.
        let args = rawArgs.compactMapValues { value -> String? in
            switch value {
            case let string as String: return string
            case let number as NSNumber:
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    return number.boolValue ? "true" : "false"
                }
                return number.stringValue
            default: return nil
            }
        }
        return Call(name: name, arguments: args)
    }
}
