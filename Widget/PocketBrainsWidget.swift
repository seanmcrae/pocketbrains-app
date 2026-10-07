import SwiftUI
import WidgetKit

/// Today widget: the brief's headline and the next few tasks. Reads only the
/// JSON snapshot the app writes into the shared App Group container; it has
/// no database access and makes no network calls.
struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let isPlaceholder: Bool
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, snapshot: .placeholder, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        // The app reloads the timeline after every task change; this refresh
        // only rolls "today"/"overdue" over at the day boundary.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry()], policy: .after(next)))
    }

    private func entry() -> TodayEntry {
        if let snapshot = WidgetSnapshot.load() {
            return TodayEntry(date: .now, snapshot: snapshot, isPlaceholder: false)
        }
        return TodayEntry(date: .now, snapshot: .placeholder, isPlaceholder: true)
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private let accent = Color(red: 0.894, green: 0.773, blue: 0.435)

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.snapshot.headline).font(.headline).lineLimit(1)
                if let first = entry.snapshot.items.first {
                    Text(first.title).font(.caption).lineLimit(1)
                } else {
                    Text("Nothing due").font(.caption)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.date.formatted(.dateTime.weekday(.wide)).uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                    Spacer()
                    if entry.snapshot.overdue > 0 {
                        Text("\(entry.snapshot.overdue) overdue")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                }
                Text(entry.snapshot.headline)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                let limit = family == .systemSmall ? 2 : 4
                ForEach(Array(entry.snapshot.items.prefix(limit).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        Circle()
                            .strokeBorder(item.isOverdue ? Color.orange : Color.white.opacity(0.5), lineWidth: 1.2)
                            .frame(width: 9, height: 9)
                        Text(item.title)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                if entry.snapshot.items.isEmpty {
                    Text(entry.isPlaceholder ? "Open PocketBrains to sync." : "Nothing due. Clear runway.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct TodayWidget: Widget {
    let kind = "PocketBrainsToday"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(Color.black, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Your next tasks and the morning brief.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

@main
struct PocketBrainsWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}
