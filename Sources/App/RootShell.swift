import SwiftUI

/// The signature moment. The thread is home; pulling its horizon down (or
/// tapping the horizon button) dissolves the conversation into a slim glass
/// dock at the foot of the screen while the three spaces fan in. One scalar
/// (`app.zoom`) drives every property — gestural, interruptible, and
/// impossible to desync. The dock keeps the agent present without spending
/// the spaces' canvas.
struct RootShell: View {
    @Environment(AppModel.self) private var app
    @State private var dragOffset: CGFloat = 0
    @AppStorage("pb.onboarded") private var onboarded = false

    /// Live progress: settled zoom plus the in-flight gesture scrub.
    private var progress: CGFloat {
        min(1, max(0, app.zoom + dragOffset))
    }

    var body: some View {
        if !onboarded {
            OnboardingOverlay {
                Haptics.commit()
                withAnimation(Motion.glide) { onboarded = true }
            }
            .transition(.opacity)
        } else {
            shell
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
        }
    }

    private var shell: some View {
        GeometryReader { geo in
            let p = progress

            ZStack {
                InkBackdrop()

                // ── Spaces, behind: sharpen and fan in as the thread recedes.
                SpacesView()
                    .scaleEffect(1.06 - 0.06 * p)
                    .blur(radius: (1 - p) * 14)
                    .opacity(Double(p) * 1.25)
                    .allowsHitTesting(p > 0.95)

                // ── Thread, in front: sinks, softens, and dissolves toward
                //    the dock — it leaves the stage rather than shrinking on it.
                ThreadView(horizonProgress: p, horizonDrag: horizonDrag)
                    .clipShape(RoundedRectangle(cornerRadius: 12 + 20 * p, style: .continuous))
                    .scaleEffect(1 - 0.08 * p)
                    .offset(y: geo.size.height * 0.14 * p)
                    .blur(radius: 10 * smooth(p, from: 0.35, to: 1))
                    .opacity(Double(1 - smooth(p, from: 0.45, to: 0.85)))
                    .allowsHitTesting(p < 0.3)

                // ── The dock: a quiet capsule carrying the agent's presence.
                ThreadDock()
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, Space.gutter)
                    .padding(.bottom, Space.xs)
                    .opacity(Double(smooth(p, from: 0.6, to: 1)))
                    .offset(y: (1 - p) * 56)
                    .allowsHitTesting(p > 0.9)
                    .onTapGesture { app.returnToThread() }
                    .gesture(horizonDrag) // flick up also brings it home
            }
            .animation(Motion.glide, value: app.zoom)
        }
        .statusBarHidden(progress > 0.5)
    }

    private func smooth(_ x: CGFloat, from a: CGFloat, to b: CGFloat) -> CGFloat {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// Attached to the thread's horizon grabber: pull down to dock the
    /// conversation, flick up from the dock to bring it home.
    private var horizonDrag: AnyGesture<DragGesture.Value> {
        AnyGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { value in
                    let delta = value.translation.height / 420
                    dragOffset = app.zoom == 0 ? max(0, delta) : min(0, delta)
                }
                .onEnded { value in
                    let velocity = value.predictedEndTranslation.height - value.translation.height
                    let settled: CGFloat = if app.zoom == 0 {
                        (progress > 0.35 || velocity > 120) ? 1 : 0
                    } else {
                        (progress < 0.65 || velocity < -120) ? 0 : 1
                    }
                    dragOffset = 0
                    withAnimation(Motion.glide) { app.zoom = settled }
                    if settled == 1 { Haptics.commit() } else { Haptics.touch() }
                }
        )
    }
}

/// The docked thread: orb, the last exchange at a glance, and the way home.
/// While the agent works, the dock is alive — light, not a spinner.
private struct ThreadDock: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: Space.s) {
            AuroraOrb(energy: app.agent.isBusy ? 1 : 0.3, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text("Thread")
                    .font(Type.callout)
                    .foregroundStyle(Paper.primary)
                Text(snippet)
                    .font(Type.micro)
                    .foregroundStyle(Paper.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: Space.s)

            Image(systemName: "chevron.compact.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Paper.tertiary)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .glass(Radius.sheet, tint: lumen, depth: 1)
        .contentShape(Rectangle())
        .accessibilityLabel("Return to conversation")
        .accessibilityAddTraits(.isButton)
    }

    private var snippet: String {
        if app.agent.isBusy { return "Working…" }
        guard let last = app.agent.messages.last else {
            return "Ask, capture, or command"
        }
        let flat = last.text.replacingOccurrences(of: "\n", with: "  ")
        return (last.role == .user ? "You: " : "") + flat
    }
}
