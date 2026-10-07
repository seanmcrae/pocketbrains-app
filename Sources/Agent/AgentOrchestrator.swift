import Foundation
import SwiftData
import SwiftUI

/// Owns the conversation: picks the brain, streams its events into UI state,
/// and persists every turn. The thread view renders only from this object.
@MainActor
@Observable
final class AgentOrchestrator {
    enum Phase: Equatable {
        case idle
        case thinking       // prompt sent, nothing back yet
        case acting         // a tool is running
        case streaming      // tokens flowing
    }

    private(set) var phase: Phase = .idle
    /// Cumulative text of the in-flight reply.
    private(set) var liveText: String = ""
    /// Tool cards for the in-flight reply (running + finished).
    private(set) var liveToolEvents: [ToolEventRecord] = []
    private(set) var runningToolName: String?
    private(set) var messages: [ChatMessage] = []
    private(set) var backendName: String = ""

    /// Marker prefix for failed turns, so the UI can offer a retry.
    static let snagText = "I hit a snag generating that — try once more, or rephrase."

    private let context: ModelContext
    private let toolbox: ToolBox
    private var backend: ModelBackend
    private var currentTurn: Task<Void, Never>?
    private var lastPrompt: String?

    init(context: ModelContext, toolbox: ToolBox) {
        self.context = context
        self.toolbox = toolbox
        self.backend = AgentVoice.selectBackend(toolbox: toolbox)
        self.backendName = backend.displayName
        self.messages = context.fetchAll(ChatMessage.self, sortBy: [.init(\.createdAt)])
    }

    var isBusy: Bool { phase != .idle }

    /// Re-pick the brain after the user changes the Settings preference.
    func applyBrainPreference() {
        backend = AgentVoice.selectBackend(toolbox: toolbox)
        backendName = backend.displayName
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }

        let userMessage = ChatMessage(role: .user, text: trimmed)
        context.insert(userMessage)
        try? context.save()
        messages.append(userMessage)
        lastPrompt = trimmed

        phase = .thinking
        liveText = ""
        liveToolEvents = []
        runningToolName = nil

        toolbox.turnGroupID = UUID().uuidString
        currentTurn = Task { @MainActor in
            await runTurn(trimmed, allowBrainSwap: true)
        }
    }

    private func runTurn(_ prompt: String, allowBrainSwap: Bool) async {
        do {
            for try await event in backend.reply(to: prompt) {
                handle(event)
            }
        } catch {
            guard !Task.isCancelled else { return }
            // A model can advertise availability yet fail to generate (e.g.
            // Apple Intelligence enabled but assets not downloaded). Swap to
            // the deterministic brain and answer anyway — never a dead end.
            if allowBrainSwap, liveText.isEmpty, !(backend is IntentFallbackBackend) {
                backend = IntentFallbackBackend(toolbox: toolbox)
                backendName = backend.displayName
                await runTurn(prompt, allowBrainSwap: false)
            } else {
                finishTurn(with: liveText.isEmpty ? Self.snagText : liveText)
            }
        }
    }

    /// Re-run the last prompt without re-posting the user's bubble —
    /// offered under a failed turn so errors never dead-end.
    func retryLast() {
        guard let lastPrompt, !isBusy else { return }
        phase = .thinking
        liveText = ""
        liveToolEvents = []
        runningToolName = nil
        toolbox.turnGroupID = UUID().uuidString
        currentTurn = Task { @MainActor in
            await runTurn(lastPrompt, allowBrainSwap: true)
        }
    }

    /// True when the most recent turn ended in the snag message.
    var lastTurnFailed: Bool {
        messages.last?.role == .agent && messages.last?.text == Self.snagText
    }

    func cancel() {
        currentTurn?.cancel()
        if !liveText.isEmpty { finishTurn(with: liveText) } else { phase = .idle }
    }

    func clearHistory() {
        for message in messages { context.delete(message) }
        try? context.save()
        messages = []
        backend.resetConversation()
    }

    // MARK: - Event handling

    private func handle(_ event: AgentEvent) {
        switch event {
        case .toolStarted(let name, let summary):
            phase = .acting
            runningToolName = name
            liveToolEvents.append(.init(toolName: name, summary: summary,
                                        detail: "", succeeded: true))
        case .toolFinished(let record):
            runningToolName = nil
            if let index = liveToolEvents.firstIndex(where: { $0.id == record.id }) {
                // Same card updating in place (a plan card's final state).
                liveToolEvents[index] = record
            } else if let index = liveToolEvents.lastIndex(where: { $0.toolName == record.toolName && $0.detail.isEmpty }) {
                liveToolEvents[index] = record
            } else {
                liveToolEvents.append(record)
            }
            Haptics.tick()
        case .text(let snapshot):
            phase = .streaming
            liveText = snapshot
        case .done(let finalText):
            finishTurn(with: finalText)
        }
    }

    // MARK: - Undo

    /// Bumped after every undo so cards re-read their journal state.
    private(set) var undoRevision = 0

    /// True when the card's action (or whole plan) has already been reverted.
    func isUndone(_ record: ToolEventRecord) -> Bool {
        _ = undoRevision
        if let group = record.undoGroup {
            return toolbox.services.journal.pending(inGroup: group).isEmpty
        }
        if let id = record.journalID {
            return toolbox.services.journal.entry(id: id)?.isUndone ?? true
        }
        return false
    }

    /// The Undo button on a tool or plan card. Reverts that action (or the
    /// whole plan, atomically) and posts the result as its own agent turn.
    func undo(_ record: ToolEventRecord) {
        guard !isBusy else { return }
        let result: ToolResult
        if let group = record.undoGroup {
            result = toolbox.undo(group: group)
        } else if let id = record.journalID {
            result = toolbox.undo(entryID: id)
        } else {
            return
        }
        undoRevision += 1
        Haptics.commit()
        let reply = ChatMessage(role: .agent, text: result.detail)
        reply.toolEvents = [result.record(toolName: "undo")]
        context.insert(reply)
        try? context.save()
        messages.append(reply)
    }

    private func finishTurn(with text: String) {
        let reply = ChatMessage(role: .agent, text: text)
        reply.toolEvents = liveToolEvents
        context.insert(reply)
        try? context.save()
        messages.append(reply)
        liveText = ""
        liveToolEvents = []
        runningToolName = nil
        toolbox.turnGroupID = ""
        undoRevision += 1
        phase = .idle
    }
}
