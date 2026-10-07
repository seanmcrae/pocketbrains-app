import SwiftUI
import SwiftData

/// Magazine catalog of projects: serif headlines, identity hue glass,
/// progress as light. Tap a card and it expands into its dossier in place.
struct ProjectsView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @Namespace private var hero

    var body: some View {
        GeometryReader { geo in
            // iPhone: a single magazine column. iPad: a two-up spread.
            let columns = geo.size.width > Layout.twoColumnThreshold
                ? [GridItem(.flexible(), spacing: Space.m), GridItem(.flexible(), spacing: Space.m)]
                : [GridItem(.flexible())]
            ZStack {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Space.m) {
                        ForEach(projects, id: \.id) { project in
                            if app.focusedProject?.id != project.id {
                                ProjectCard(project: project)
                                    .matchedGeometryEffect(id: project.id, in: hero)
                                    .onTapGesture {
                                        Haptics.touch()
                                        withAnimation(Motion.glide) { app.focusedProject = project }
                                    }
                            } else {
                                // Hole the card leaves behind while expanded.
                                Color.clear.frame(height: 120)
                            }
                        }
                    }
                    .padding(.horizontal, Space.gutter)
                    .padding(.top, Space.xs)
                    .padding(.bottom, Space.xl)

                    if projects.isEmpty {
                        EmptyState(icon: "square.stack",
                                   title: "No projects yet",
                                   message: "Tell the thread: “start a project called Spring Launch.”")
                    }
                }
                .scrollIndicators(.hidden)

                if let project = app.focusedProject {
                    ProjectDossier(project: project)
                        .matchedGeometryEffect(id: project.id, in: hero)
                        .transition(.identity)
                        .zIndex(1)
                        .frame(maxWidth: Layout.readingWidth)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// The catalog card: a spread, not a row.
struct ProjectCard: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    MicroLabel(text: project.status.label,
                               color: project.hue.color.opacity(0.9))
                    Text(project.name)
                        .font(Type.display)
                        .tracking(-0.5)
                        .foregroundStyle(Paper.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: Space.s)
                ProgressRing(progress: project.progress, tint: project.hue.color)
            }

            if !project.summary.isEmpty {
                Text(project.summary)
                    .font(Type.callout)
                    .foregroundStyle(Paper.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: Space.s) {
                let open = project.openTasks.count
                GlassChip(text: "\(open) open", icon: "circle.dashed",
                          tint: Paper.secondary)
                if !project.blockers.isEmpty {
                    GlassChip(text: "\(project.blockers.count) blocked", icon: "hourglass",
                              tint: DomainHue.task)
                }
                if let next = (project.milestones ?? [])
                    .filter({ !$0.isReached && $0.targetDate != nil })
                    .min(by: { $0.targetDate! < $1.targetDate! }) {
                    GlassChip(text: "\(next.title) · \(NaturalDateParser.describe(next.targetDate!))",
                              icon: "flag", tint: project.hue.color)
                }
                Spacer()
                // Only earned momentum is shown — no dotted placeholder.
                if (project.tasks ?? []).contains(where: { $0.isDone }) {
                    ActivitySparkline(project: project)
                }
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(Radius.card, tint: project.hue.color, depth: 0.9)
    }
}

/// Fourteen days of completions as a quiet bar of light in the card footer —
/// momentum you can read at a glance without a single number.
struct ActivitySparkline: View {
    let project: Project

    private var counts: [Int] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var bins = Array(repeating: 0, count: 14)
        for task in project.tasks ?? [] {
            guard let done = task.completedAt else { continue }
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: done), to: today).day ?? 99
            if (0..<14).contains(days) { bins[13 - days] += 1 }
        }
        return bins
    }

    var body: some View {
        let bins = counts
        let peak = max(1, bins.max() ?? 1)
        Canvas { context, size in
            let slot = size.width / 14
            let barWidth = max(1.5, slot * 0.45)
            for (index, count) in bins.enumerated() {
                let height = count == 0
                    ? 1.5
                    : max(3, size.height * CGFloat(count) / CGFloat(peak))
                let rect = CGRect(
                    x: CGFloat(index) * slot + (slot - barWidth) / 2,
                    y: size.height - height,
                    width: barWidth, height: height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(count == 0
                        ? Paper.faint
                        : project.hue.color.opacity(0.45 + 0.55 * Double(count) / Double(peak))))
            }
        }
        .frame(width: 84, height: 18)
        .accessibilityLabel("Activity, last two weeks")
    }
}

/// The expanded dossier: milestones, open work, and the activity ribbon.
struct ProjectDossier: View {
    @Environment(AppModel.self) private var app
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    MicroLabel(text: "\(project.status.label) · \(project.hue.name)",
                               color: project.hue.color.opacity(0.9))
                    Text(project.name)
                        .font(Type.display)
                        .tracking(-0.5)
                        .foregroundStyle(Paper.primary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    withAnimation(Motion.glide) { app.focusedProject = nil }
                    Haptics.touch()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Paper.secondary)
                        .frame(width: 32, height: 32)
                        .glass(Radius.control, depth: 0.4)
                }
                .buttonStyle(GlassPressStyle())
            }
            .padding(Space.l)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    if !project.summary.isEmpty {
                        Text(project.summary)
                            .font(Type.body)
                            .lineSpacing(4)
                            .foregroundStyle(Paper.secondary)
                    }

                    if let milestones = project.milestones, !milestones.isEmpty {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            SectionHeader(title: "Milestones")
                            ForEach(milestones.sorted {
                                ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture)
                            }, id: \.id) { milestone in
                                HStack(spacing: Space.s) {
                                    Image(systemName: milestone.isReached ? "flag.fill" : "flag")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(milestone.isReached
                                            ? project.hue.color : Paper.tertiary)
                                    Text(milestone.title)
                                        .font(Type.callout)
                                        .foregroundStyle(Paper.primary)
                                    Spacer()
                                    if let target = milestone.targetDate {
                                        Text(NaturalDateParser.describe(target))
                                            .font(Type.caption)
                                            .foregroundStyle(Paper.tertiary)
                                    }
                                }
                                .padding(.horizontal, Space.m)
                                .padding(.vertical, Space.s)
                                .glass(Radius.control, depth: 0.35)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Space.xs) {
                        SectionHeader(title: "Open work", detail: "\(project.openTasks.count)")
                        ForEach(project.openTasks, id: \.id) { task in
                            TaskRow(task: task)
                        }
                        if project.openTasks.isEmpty {
                            Text("Everything here is done.")
                                .font(Type.callout)
                                .foregroundStyle(Paper.tertiary)
                        }
                    }

                    VStack(alignment: .leading, spacing: Space.xs) {
                        SectionHeader(title: "Recent activity")
                        ForEach(app.services.projects.recentActivity(for: project, limit: 5),
                                id: \.self) { line in
                            HStack(spacing: Space.xs) {
                                Circle().fill(project.hue.color.opacity(0.7))
                                    .frame(width: 4, height: 4)
                                Text(line)
                                    .font(Type.caption)
                                    .foregroundStyle(Paper.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.l)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glass(Radius.sheet, tint: project.hue.color, depth: 1)
        .padding(.horizontal, Space.s)
    }
}
