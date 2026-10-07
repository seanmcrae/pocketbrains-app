import SwiftUI

// MARK: - Glass chip

/// Small labeled pill on glass — tags, dates, statuses.
struct GlassChip: View {
    let text: String
    var icon: String? = nil
    var tint: Color = Paper.secondary

    var body: some View {
        HStack(spacing: Space.xxs) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .semibold)) }
            Text(text)
                .font(Type.caption)
                .lineLimit(1) // chips never wrap — truncate with grace
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Space.xs + 2)
        .padding(.vertical, Space.xxs + 1)
        .glass(Radius.chip, tint: tint, depth: 0)
    }
}

// MARK: - Glass button

struct GlassButton: View {
    let title: String
    var icon: String? = nil
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.commit()
            action()
        } label: {
            HStack(spacing: Space.xs) {
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .semibold)) }
                Text(title).font(Type.callout)
            }
            .foregroundStyle(prominent ? Ink.l0 : Paper.primary)
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.s)
            .background {
                if prominent {
                    RoundedRectangle.control().fill(lumen)
                }
            }
            .glass(Radius.control, tint: prominent ? nil : lumen, depth: prominent ? 1 : 0.6)
        }
        .buttonStyle(GlassPressStyle())
    }
}

// MARK: - Progress ring

/// Thin luminous arc — project progress. The tip carries a glow bead.
struct ProgressRing: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 3.5
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .stroke(Paper.faint, lineWidth: lineWidth)
            if progress > 0 {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.6), radius: 4)
                Text("\(Int(progress * 100))")
                    .font(Type.micro)
                    .foregroundStyle(Paper.secondary)
            } else {
                // Untouched projects show a quiet empty track, not "0".
                Circle()
                    .fill(tint.opacity(0.35))
                    .frame(width: 4, height: 4)
            }
        }
        .frame(width: size, height: size)
        .animation(Motion.glide, value: progress)
    }
}

// MARK: - Priority glyph

/// Priority as stacked light, not color screaming: 1–3 ascending bars.
struct PriorityGlyph: View {
    let priority: TaskPriority

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i < priority.bars ? DomainHue.task : Paper.faint)
                    .frame(width: 3, height: CGFloat(5 + i * 3))
            }
        }
        .frame(height: 12, alignment: .bottom)
        .accessibilityLabel("Priority \(priority.label)")
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            MicroLabel(text: title)
            Spacer()
            if let detail {
                Text(detail).font(Type.caption).foregroundStyle(Paper.tertiary)
            }
        }
        .padding(.horizontal, Space.xxs)
    }
}

// MARK: - Empty state

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Space.s) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Paper.tertiary)
            Text(title).font(Type.heading).foregroundStyle(Paper.secondary)
            Text(message)
                .font(Type.callout)
                .foregroundStyle(Paper.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Checkmark

/// Task completion control: a ring that fills with citrine light and draws
/// its check with a trimmed path.
struct CompletionToggle: View {
    var done: Bool
    let action: () -> Void

    @State private var burstAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            if !done {
                Haptics.success()
                if !reduceMotion { burstAt = .now }
            } else {
                Haptics.tick()
            }
            action()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(done ? DomainHue.task : Paper.tertiary, lineWidth: 1.5)
                    .background(Circle().fill(done ? DomainHue.task.opacity(0.9) : .clear))
                CheckShape()
                    .trim(from: 0, to: done ? 1 : 0)
                    .stroke(Ink.l0, style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .padding(6)
            }
            .frame(width: 24, height: 24)
            .animation(Motion.snap, value: done)
        }
        .buttonStyle(GlassPressStyle(scale: 0.85))
        .overlay {
            if let burstAt {
                EmberBurst(startedAt: burstAt)
                    .frame(width: 72, height: 72)
                    .allowsHitTesting(false)
            }
        }
        .task(id: burstAt) {
            guard burstAt != nil else { return }
            try? await Task.sleep(for: .milliseconds(900))
            burstAt = nil
        }
    }
}

/// A dozen embers thrown from a completed task — gone in 700ms, remembered
/// longer. The product's smallest celebration.
struct EmberBurst: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(startedAt)
                guard t >= 0, t < 0.7 else { return }
                let p = t / 0.7
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0..<12 {
                    let angle = Double(i) / 12 * 2 * .pi + Double((i * 5) % 7) * 0.13
                    let speed = 16.0 + Double((i * 7) % 11) * 2.0
                    let radius = speed * p * (2 - p) // ease-out fling
                    let pos = CGPoint(x: center.x + cos(angle) * radius,
                                      y: center.y + sin(angle) * radius - 6 * p)
                    let alpha = (1 - p) * 0.9
                    let dot = 2.4 - p * 1.6
                    context.fill(
                        Path(ellipseIn: CGRect(x: pos.x - dot / 2, y: pos.y - dot / 2,
                                               width: dot, height: dot)),
                        with: .color(DomainHue.task.opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: rect.minX, y: rect.midY + rect.height * 0.08))
        p.addLine(to: .init(x: rect.minX + rect.width * 0.36, y: rect.maxY - rect.height * 0.1))
        p.addLine(to: .init(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        return p
    }
}
