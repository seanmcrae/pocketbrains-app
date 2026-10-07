import Foundation
import WidgetKit

/// Keeps the Today widget's snapshot current. Called from the task write
/// path after every mutation (cheap at personal scale) and on launch.
@MainActor
enum WidgetPublisher {
    /// Pure mapping, unit-tested: the brief's headline and focus plus the
    /// next open tasks — overdue first, then by due date, undated last.
    static func makeSnapshot(brief: DailyBrief, tasks: [TaskItem], limit: Int = 4,
                             now: Date = .now) -> WidgetSnapshot {
        let open = tasks.filter { !$0.isDone }
            .sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case let (l?, r?): return l != r ? l < r : lhs.priorityRaw > rhs.priorityRaw
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.priorityRaw > rhs.priorityRaw
                }
            }
        let items = open.prefix(limit).map {
            WidgetSnapshot.Item(title: $0.title, due: $0.dueDate,
                                project: $0.project?.name, isOverdue: $0.isOverdue)
        }
        return WidgetSnapshot(generatedAt: now, headline: brief.headline, focus: brief.focus,
                              overdue: brief.overdue, dueToday: brief.dueToday, items: Array(items))
    }

    static func publish(services: DataServices) {
        guard WidgetSnapshot.fileURL != nil else { return } // no App Group: nothing to feed
        let snapshot = makeSnapshot(brief: DailyBrief.compose(services: services),
                                    tasks: services.tasks.all())
        if snapshot.save() {
            WidgetCenter.shared.reloadTimelines(ofKind: "PocketBrainsToday")
        }
    }
}
