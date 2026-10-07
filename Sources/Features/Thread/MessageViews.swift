import SwiftUI
import UIKit

/// One settled turn from the transcript.
struct MessageRow: View {
    @Environment(AppModel.self) private var app
    let message: ChatMessage

    var body: some View {
        if message.role == .user {
            UserBubble(text: message.text)
        } else {
            AgentTurn(text: message.text, toolEvents: message.toolEvents,
                      runningTool: nil, isLive: false,
                      isUndone: { app.agent.isUndone($0) },
                      onUndo: { app.agent.undo($0) })
        }
    }
}

/// Quiet date marker between days in the transcript.
struct DayDivider: View {
    let date: Date

    var body: some View {
        HStack(spacing: Space.s) {
            hairline
            MicroLabel(text: NaturalDateParser.describe(date)
                .replacingOccurrences(of: " · overdue", with: ""))
                .fixedSize()
            hairline
        }
        .padding(.vertical, Space.xxs)
    }

    private var hairline: some View {
        LinearGradient(colors: [.clear, Paper.faint, .clear],
                       startPoint: .leading, endPoint: .trailing)
            .frame(height: 0.75)
    }
}

struct UserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: Space.vast)
            Text(text)
                .font(Type.body)
                .foregroundStyle(Paper.primary)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .glass(Radius.control, tint: lumen, depth: 0.5)
                .contextMenu {
                    Button("Copy", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = text
                    }
                }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Agent reply: tool cards first (the work, visible), then the prose —
/// carried on a thin thread of light, the agent's signature in the layout.
struct AgentTurn: View {
    let text: String
    let toolEvents: [ToolEventRecord]
    let runningTool: String?
    let isLive: Bool
    /// Settled turns pass these so cards can offer Undo.
    var isUndone: ((ToolEventRecord) -> Bool)? = nil
    var onUndo: ((ToolEventRecord) -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            // The thread of light.
            Capsule()
                .fill(LinearGradient(
                    colors: [lumen.opacity(0.55), lumen.opacity(0.06)],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: 2)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(toolEvents) { event in
                    let undoable = !isLive && (event.journalID != nil || event.undoGroup != nil)
                    if event.toolName == "plan" {
                        PlanCard(event: event,
                                 isUndone: undoable ? (isUndone?(event) ?? false) : false,
                                 onUndo: undoable ? undoAction(for: event) : nil)
                    } else {
                        ToolActivityCard(event: event,
                                         isRunning: isLive && event.toolName == runningTool && event.detail.isEmpty,
                                         isUndone: undoable ? (isUndone?(event) ?? false) : false,
                                         onUndo: undoable ? undoAction(for: event) : nil)
                    }
                }
                if !text.isEmpty {
                    StreamingText(text: text, isLive: isLive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, Space.xl)
                        .contextMenu {
                            if !isLive {
                                Button("Copy", systemImage: "doc.on.doc") {
                                    UIPasteboard.general.string = text
                                }
                            }
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func undoAction(for event: ToolEventRecord) -> (() -> Void)? {
        guard let onUndo else { return nil }
        return { onUndo(event) }
    }
}

/// A tool call made visible: a small glass card that slides out of the orb,
/// shows what's happening, and ticks to a check when done.
struct ToolActivityCard: View {
    let event: ToolEventRecord
    var isRunning: Bool = false
    var isUndone: Bool = false
    var onUndo: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: Self.icon(for: event.toolName))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Self.hue(for: event.toolName))
                .frame(width: 18)

            if let step = event.stepLabel {
                Text(step)
                    .font(Type.micro)
                    .monospacedDigit()
                    .foregroundStyle(Paper.tertiary)
            }

            Text(event.summary)
                .font(Type.caption)
                .foregroundStyle(isUndone ? Paper.tertiary : Paper.secondary)
                .strikethrough(isUndone)
                .lineLimit(2)

            Spacer(minLength: Space.xs)

            if let onUndo, !isRunning {
                UndoChip(isUndone: isUndone, action: onUndo)
            }

            if isRunning {
                AuroraOrb(energy: 0.8, tint: Self.hue(for: event.toolName), size: 18)
            } else {
                Image(systemName: event.succeeded ? "checkmark" : "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(event.succeeded ? DomainHue.note : DomainHue.task)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs + 2)
        .glass(Radius.control, tint: Self.hue(for: event.toolName), depth: 0.4)
        .frame(maxWidth: 320, alignment: .leading)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.85, anchor: .leading).combined(with: .opacity),
            removal: .opacity))
        .animation(Motion.snap, value: isRunning)
    }

    static func icon(for tool: String) -> String {
        switch tool {
        case "createTask", "updateTask": "circle.badge.plus"
        case "completeTask": "checkmark.circle"
        case "queryTasks", "agenda": "sun.horizon"
        case "createProject", "projectStatus", "addMilestone": "square.stack"
        case "createNote", "appendNote": "square.and.pencil"
        case "searchNotes", "notesFrom": "magnifyingglass"
        case "linkItems": "link"
        case "recall": "clock.arrow.circlepath"
        case "undo": "arrow.uturn.backward"
        case "plan": "list.number"
        default: "sparkle"
        }
    }

    static func hue(for tool: String) -> Color {
        switch tool {
        case "createTask", "updateTask", "completeTask", "queryTasks", "agenda": DomainHue.task
        case "createProject", "projectStatus", "addMilestone": lumen
        case "createNote", "appendNote", "searchNotes", "notesFrom": DomainHue.note
        case "linkItems", "recall": DomainHue.knowledge
        default: lumen
        }
    }
}

/// "Undo" on a settled card; reads "Undone" once reverted.
struct UndoChip: View {
    let isUndone: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.touch()
            action()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: isUndone ? "checkmark" : "arrow.uturn.backward")
                    .font(.system(size: 9, weight: .bold))
                Text(isUndone ? "Undone" : "Undo")
                    .font(Type.micro)
            }
            .foregroundStyle(isUndone ? Paper.tertiary : lumen)
            .padding(.horizontal, Space.xs)
            .padding(.vertical, 3)
            .glass(Radius.control, tint: lumen, depth: 0.3)
        }
        .buttonStyle(GlassPressStyle())
        .disabled(isUndone)
        .accessibilityLabel(isUndone ? "Undone" : "Undo this action")
    }
}

/// A multi-step plan made visible: the numbered steps, ticking as they run,
/// with one Undo that reverts the whole plan atomically.
struct PlanCard: View {
    let event: ToolEventRecord
    var isUndone: Bool = false
    var onUndo: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                Image(systemName: "list.number")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(lumen)
                    .frame(width: 18)
                Text(event.summary)
                    .font(Type.caption)
                    .foregroundStyle(Paper.primary)
                Spacer(minLength: Space.xs)
                if let onUndo {
                    UndoChip(isUndone: isUndone, action: onUndo)
                }
                Image(systemName: event.succeeded ? "checkmark" : "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(event.succeeded ? DomainHue.note : DomainHue.task)
            }
            ForEach(Array(event.detail.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(Type.caption)
                    .foregroundStyle(isUndone ? Paper.tertiary : Paper.secondary)
                    .strikethrough(isUndone)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs + 2)
        .glass(Radius.control, tint: lumen, depth: 0.45)
        .frame(maxWidth: 340, alignment: .leading)
        .transition(.scale(scale: 0.9, anchor: .leading).combined(with: .opacity))
    }
}
