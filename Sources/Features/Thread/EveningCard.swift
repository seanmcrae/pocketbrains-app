import SwiftUI

/// Day's end, acknowledged. Shows only after 6pm on days where something
/// actually got closed — earned, never nagging.
struct EveningCard: View {
    let reflection: EveningReflection
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                MicroLabel(text: "Day's end", color: DomainHue.note.opacity(0.9))
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

            Text(reflection.doneCount == 1
                ? "You closed one thing today."
                : "You closed \(reflection.doneCount) things today.")
                .font(Type.heading)
                .foregroundStyle(Paper.primary)

            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(reflection.highlights, id: \.self) { title in
                    HStack(spacing: Space.xs) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(DomainHue.note)
                        Text(title)
                            .font(Type.callout)
                            .foregroundStyle(Paper.secondary)
                            .lineLimit(1)
                    }
                }
                if reflection.doneCount > reflection.highlights.count {
                    Text("and \(reflection.doneCount - reflection.highlights.count) more")
                        .font(Type.caption)
                        .foregroundStyle(Paper.tertiary)
                }
            }

            Text("Anything worth capturing before tomorrow?")
                .font(Type.caption)
                .foregroundStyle(Paper.tertiary)
                .padding(.top, Space.xxs)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(Radius.card, tint: DomainHue.note, depth: 0.8)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .scale(scale: 0.96).combined(with: .opacity)))
    }
}
