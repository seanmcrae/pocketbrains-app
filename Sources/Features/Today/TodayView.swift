import SwiftUI
import SwiftData

/// The agenda: exactly what needs attention, ranked — overdue, due today,
/// blocked, then the week. Auto-updates the instant the agent acts.
struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var allTasks: [TaskItem]

    private var open: [TaskItem] { allTasks.filter { !$0.isDone } }
    private var overdue: [TaskItem] { open.filter(\.isOverdue) }
    private var dueToday: [TaskItem] {
        open.filter { $0.dueDate.map { Calendar.current.isDateInToday($0) } ?? false && !$0.isOverdue }
    }
    private var blocked: [TaskItem] { open.filter { $0.isBlocked && !$0.isOverdue } }
    private var thisWeek: [TaskItem] {
        let horizon = Calendar.current.date(byAdding: .day, value: 7, to: .now)!
        return open.filter { task in
            guard let due = task.dueDate else { return false }
            return due <= horizon && !task.isOverdue
                && !Calendar.current.isDateInToday(due) && !task.isBlocked
        }
    }

    private var doneToday: Int {
        allTasks.filter {
            $0.completedAt.map { Calendar.current.isDateInToday($0) } ?? false
        }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                masthead
                if overdue.isEmpty && dueToday.isEmpty && blocked.isEmpty && thisWeek.isEmpty {
                    clearRunway
                }
                section("Overdue", tasks: overdue, urgentTint: true)
                section("Today", tasks: dueToday)
                section("Blocked", tasks: blocked)
                section("This week", tasks: thisWeek)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.xl)
            .frame(maxWidth: Layout.readingWidth)
            .frame(maxWidth: .infinity) // centered column on iPad
        }
        .scrollIndicators(.hidden)
        .animation(Motion.glide, value: open.count)
    }

    /// The day, set like a magazine folio: serif date, what's done, what waits.
    private var masthead: some View {
        let attention = overdue.count + dueToday.count
        let total = doneToday + attention
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide)))
                    .font(Type.display)
                    .tracking(-0.5)
                    .foregroundStyle(Paper.primary)
                Text(Date.now.formatted(.dateTime.month(.wide).day()))
                    .font(Type.callout)
                    .foregroundStyle(Paper.tertiary)
            }
            Spacer()
            if total > 0 {
                VStack(spacing: Space.xxs) {
                    ProgressRing(progress: Double(doneToday) / Double(total),
                                 tint: DomainHue.task, size: 40)
                    MicroLabel(text: "\(doneToday) done")
                }
            }
        }
        .padding(.horizontal, Space.xxs)
        .padding(.bottom, Space.xs)
    }

    @ViewBuilder
    private func section(_ title: String, tasks: [TaskItem], urgentTint: Bool = false) -> some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: Space.xs) {
                SectionHeader(title: title, detail: "\(tasks.count)")
                VStack(spacing: Space.xs) {
                    ForEach(tasks, id: \.id) { task in
                        TaskRow(task: task, alarm: urgentTint)
                    }
                }
            }
        }
    }

    private var clearRunway: some View {
        VStack(spacing: Space.m) {
            AuroraOrb(energy: 0.3, tint: DomainHue.note, size: 64)
            Text("Clear runway")
                .font(Type.heading)
                .foregroundStyle(Paper.primary)
            Text("Nothing is overdue, due, or blocked.\nA rare and beautiful state.")
                .font(Type.callout)
                .foregroundStyle(Paper.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.vast)
    }
}

/// One task on glass: completion ring, title, context chips.
struct TaskRow: View {
    @Environment(AppModel.self) private var app
    let task: TaskItem
    var alarm: Bool = false

    var body: some View {
        HStack(spacing: Space.s) {
            CompletionToggle(done: task.isDone) {
                if task.isDone {
                    app.services.tasks.reopen(task)
                } else {
                    _ = app.services.tasks.complete(task)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(Type.bodyMedium)
                    .foregroundStyle(Paper.primary)
                    .strikethrough(task.isDone, color: Paper.tertiary)
                    .lineLimit(2)

                HStack(spacing: Space.xs) {
                    if let due = task.dueDate {
                        Label(NaturalDateParser.describe(due),
                              systemImage: "calendar")
                            .font(Type.micro)
                            .foregroundStyle(task.isOverdue ? DomainHue.task : Paper.tertiary)
                    }
                    if let project = task.project {
                        HStack(spacing: 3) {
                            Circle().fill(project.hue.color).frame(width: 5, height: 5)
                            Text(project.name)
                                .font(Type.micro)
                                .foregroundStyle(Paper.tertiary)
                        }
                    }
                    if task.isBlocked {
                        Label("Blocked", systemImage: "hourglass")
                            .font(Type.micro)
                            .foregroundStyle(Paper.tertiary)
                    }
                }
            }

            Spacer(minLength: Space.xs)
            PriorityGlyph(priority: task.priority)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .glass(Radius.card, tint: alarm ? DomainHue.task : nil, depth: 0.5)
        .contextMenu {
            Button(task.isDone ? "Reopen" : "Complete",
                   systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark.circle") {
                if task.isDone { app.services.tasks.reopen(task) }
                else { Haptics.success(); _ = app.services.tasks.complete(task) }
            }
            Button("Due tomorrow", systemImage: "calendar.badge.clock") {
                app.services.tasks.update(
                    task, due: Calendar.current.date(byAdding: .day, value: 1,
                        to: Calendar.current.startOfDay(for: .now)))
            }
            Button(task.priority == .high ? "Normal priority" : "High priority",
                   systemImage: "bolt") {
                app.services.tasks.update(
                    task, priority: task.priority == .high ? .normal : .high)
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                app.services.tasks.delete(task)
            }
        }
        .opacity(task.isDone ? 0.55 : 1)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .scale(scale: 0.95).combined(with: .opacity)))
    }
}
