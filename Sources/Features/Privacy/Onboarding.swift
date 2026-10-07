import SwiftUI

/// First run: three quiet beats before the thread appears. No carousel, no
/// skip-button clutter — the product explains itself in one breath.
struct OnboardingOverlay: View {
    let onBegin: () -> Void
    @State private var stage = 0

    var body: some View {
        ZStack {
            InkBackdrop()
            VStack(spacing: 0) {
                Spacer()

                AuroraOrb(energy: stage >= 3 ? 0.55 : 0.35, size: 96)
                    .padding(.bottom, Space.xl)

                Text("PocketBrains")
                    .font(Type.display)
                    .tracking(-0.5)
                    .foregroundStyle(Paper.primary)
                    .padding(.bottom, Space.xxl)

                VStack(alignment: .leading, spacing: Space.l) {
                    beat(1, icon: "lock.fill", hue: DomainHue.note,
                         title: "Private by physics",
                         text: "The model lives on this phone. Nothing you say ever leaves it.")
                    beat(2, icon: "text.bubble", hue: lumen,
                         title: "One conversation",
                         text: "Tasks, projects, notes, knowledge — just ask, and it's done.")
                    beat(3, icon: "chevron.compact.down", hue: DomainHue.knowledge,
                         title: "Pull down to zoom out",
                         text: "Your structured world waits behind the thread.")
                }
                .padding(.horizontal, Space.xxl)
                .frame(maxWidth: 480)

                Spacer()

                GlassButton(title: "Begin", icon: "arrow.right", prominent: true) {
                    onBegin()
                }
                .opacity(stage >= 4 ? 1 : 0)
                .padding(.bottom, Space.vast)
            }
        }
        .task {
            for next in 1...4 {
                try? await Task.sleep(for: .milliseconds(next == 1 ? 350 : 650))
                withAnimation(Motion.glide) { stage = next }
            }
        }
    }

    @ViewBuilder
    private func beat(_ index: Int, icon: String, hue: Color,
                      title: String, text: String) -> some View {
        let shown = stage >= index
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(hue)
                .frame(width: 34, height: 34)
                .glass(Radius.control, tint: hue, depth: 0.4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Type.bodyMedium)
                    .foregroundStyle(Paper.primary)
                Text(text)
                    .font(Type.callout)
                    .foregroundStyle(Paper.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 10)
    }
}
