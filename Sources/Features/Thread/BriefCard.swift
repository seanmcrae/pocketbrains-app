import SwiftUI

/// The Morning Brief, set like the day's front page: serif headline, the
/// counts as quiet chips, one suggested first move. Appears once per day at
/// the top of the thread; planning or dismissing puts it away.
struct BriefCard: View {
    let brief: DailyBrief
    let onPlan: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                MicroLabel(text: "\(brief.weekday) brief", color: lumen.opacity(0.9))
                Spacer()
                Button {
                    Haptics.touch()
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Paper.tertiary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(GlassPressStyle(scale: 0.85))
            }

            Text(brief.headline)
                .font(Type.display)
                .tracking(-0.5)
                .foregroundStyle(Paper.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(2)

            HStack(spacing: Space.xs) {
                if brief.overdue > 0 {
                    GlassChip(text: "\(brief.overdue) overdue", icon: "exclamationmark.circle",
                              tint: DomainHue.task)
                }
                if brief.dueToday > 0 {
                    GlassChip(text: "\(brief.dueToday) today", icon: "sun.horizon",
                              tint: Paper.secondary)
                }
                if brief.blocked > 0 {
                    GlassChip(text: "\(brief.blocked) blocked", icon: "hourglass",
                              tint: Paper.secondary)
                }
                if brief.doneYesterday > 0 {
                    GlassChip(text: "\(brief.doneYesterday) done yesterday", icon: "checkmark",
                              tint: DomainHue.note)
                }
                Spacer()
            }

            if let focus = brief.focus {
                Text(focus)
                    .font(Type.callout)
                    .foregroundStyle(Paper.secondary)
            }

            if !brief.isQuiet {
                Button {
                    Haptics.commit()
                    onPlan()
                } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Plan my day")
                            .font(Type.callout)
                    }
                    .foregroundStyle(Ink.l0)
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.xs + 2)
                    .background(RoundedRectangle.control().fill(lumen))
                }
                .buttonStyle(GlassPressStyle())
                .padding(.top, Space.xxs)
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(Radius.card, tint: lumen, depth: 0.9)
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .scale(scale: 0.96).combined(with: .opacity)))
    }
}
