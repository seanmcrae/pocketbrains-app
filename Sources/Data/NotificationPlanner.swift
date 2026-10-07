import Foundation
import UserNotifications

/// Due-date reminders, kept truthful by full resync: after any task change,
/// pending notifications are rebuilt from the open, dated tasks. Personal
/// scale makes resync instant; truthfulness beats bookkeeping.
@MainActor
enum NotificationPlanner {
    private static let enabledKey = "pb.notifs"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// Returns whether reminders ended up enabled (permission may be denied).
    static func setEnabled(_ on: Bool, tasks: [TaskItem]) async -> Bool {
        guard on else {
            UserDefaults.standard.set(false, forKey: enabledKey)
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            return false
        }
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
        UserDefaults.standard.set(granted, forKey: enabledKey)
        if granted { sync(tasks: tasks) }
        return granted
    }

    /// Rebuild all pending reminders. Each open task with a due date gets a
    /// 9am nudge on its due day.
    static func sync(tasks: [TaskItem]) {
        guard isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for task in tasks where !task.isDone {
            guard let due = task.dueDate,
                  due > Date.now.addingTimeInterval(-12 * 3600) else { continue }
            var components = Calendar.current.dateComponents([.year, .month, .day], from: due)
            components.hour = 9
            let content = UNMutableNotificationContent()
            content.title = task.title
            content.body = task.project.map { "Due today · \($0.name)" } ?? "Due today"
            content.sound = .default
            center.add(UNNotificationRequest(
                identifier: task.id.uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        }
    }
}
