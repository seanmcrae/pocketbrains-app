import Foundation

/// What the Today widget shows, written by the app into the App Group
/// container and read by the widget extension. A small JSON file rather
/// than the SwiftData store itself: the widget never opens the database,
/// and the store's location (and its migration story) stays untouched.
struct WidgetSnapshot: Codable, Equatable {
    struct Item: Codable, Equatable {
        var title: String
        var due: Date?
        var project: String?
        var isOverdue: Bool
    }

    var generatedAt: Date
    var headline: String
    var focus: String?
    var overdue: Int
    var dueToday: Int
    var items: [Item]

    static let appGroup = "group.com.pocketbrains.shared"
    static let fileName = "widget-today.json"

    static let placeholder = WidgetSnapshot(
        generatedAt: .now, headline: "A clear morning.", focus: nil,
        overdue: 0, dueToday: 0, items: [])

    /// nil when the App Group entitlement is missing (unsigned builds,
    /// simulators without the capability): the widget then shows its
    /// placeholder and the app simply skips publishing.
    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
    }

    static func load(from url: URL? = fileURL) -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    @discardableResult
    func save(to url: URL? = WidgetSnapshot.fileURL) -> Bool {
        guard let url else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return false }
        return (try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
    }
}
