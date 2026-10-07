import Foundation
import SwiftData

/// Container bootstrap + the one shared ModelContext the app and agent use.
@MainActor
enum Store {
    /// Built fresh per container — sharing one Schema instance across
    /// containers (app + tests in one process) can crash SwiftData.
    static var schema: Schema {
        Schema([
            TaskItem.self, Project.self, Milestone.self, Note.self,
            KnowledgeLink.self, ChatMessage.self, EmbeddingRecord.self,
            JournalEntry.self,
        ])
    }

    /// The app's one persistent container — retained for the process's
    /// lifetime (a ModelContext does NOT retain its container; see
    /// VERIFICATION.md). Shared by the UI and App Intents.
    static let sharedContainer: ModelContainer = makeContainer()

    // MARK: - Migration failure state

    /// Non-nil when the persistent store failed to open and the app is
    /// running on a temporary in-memory database. The app model should
    /// read this on launch and surface a recovery banner to the user —
    /// their data has not been lost (see `lastStoreBackupURL`), but new
    /// writes will not persist until the app is reinstalled or the
    /// corrupted store is removed.
    private(set) static var migrationError: Error? = nil

    /// URL of the `.store.bak` file written when a migration failure
    /// occurred, or nil if no backup was attempted.
    private(set) static var lastStoreBackupURL: URL? = nil

    // MARK: - Container factory

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        if !inMemory {
            // SwiftData puts the store in Application Support but expects the
            // directory to exist — it doesn't on fresh installs/simulators.
            try? FileManager.default.createDirectory(
                at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        }
        let schema = Self.schema // one instance per container, see above
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Persistent store could not be opened — most likely a schema
            // migration failure after an app update.  Steps:
            //   1. Log the error so it appears in Console and crash reports.
            //   2. Attempt to back up the broken store files so the user's
            //      data is preserved for manual recovery.
            //   3. Surface the failure via `migrationError` so the UI can
            //      show a recovery banner instead of silently losing data.
            //   4. Fall back to a fresh in-memory store so the app stays
            //      usable; the in-memory container itself must succeed or
            //      there is a programming error, hence fatalError below.
            print("[PocketBrains] \u{26A0}\u{FE0F} Persistent store failed to open: \(error)")
            migrationError = error
            lastStoreBackupURL = backupBrokenStore()
            let fallback = Self.schema
            do {
                return try ModelContainer(
                    for: fallback,
                    configurations: [ModelConfiguration(schema: fallback, isStoredInMemoryOnly: true)])
            } catch let memoryError {
                fatalError("[PocketBrains] Failed to create in-memory fallback container — " +
                           "original error: \(error), fallback error: \(memoryError)")
            }
        }
    }

    // MARK: - Store backup

    /// Renames all SwiftData store files in Application Support to `.bak`
    /// timestamped copies, preserving data for manual recovery.
    /// Returns the URL of the primary backup file (`.store.bak-<timestamp>`)
    /// or nil if no store files were found or the rename failed.
    @discardableResult
    private static func backupBrokenStore() -> URL? {
        let fm = FileManager.default
        let supportDir = URL.applicationSupportDirectory
        guard let contents = try? fm.contentsOfDirectory(
            at: supportDir, includingPropertiesForKeys: nil)
        else { return nil }

        let stamp = Int(Date().timeIntervalSince1970)
        // SwiftData uses Core Data's SQLite stack: .store, .store-wal, .store-shm.
        let storeExtensions: Set<String> = ["store", "sqlite", "db"]
        var primaryBackup: URL? = nil

        for url in contents where storeExtensions.contains(url.pathExtension) {
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent(url.lastPathComponent + ".bak-\(stamp)")
            if (try? fm.moveItem(at: url, to: backup)) != nil {
                print("[PocketBrains] Backed up \(url.lastPathComponent) → \(backup.lastPathComponent)")
                if url.pathExtension == "store" || url.pathExtension == "sqlite" || url.pathExtension == "db" {
                    primaryBackup = backup
                }
            }
        }
        // Also look for WAL/SHM companions of any extension we recognised.
        for url in contents where url.lastPathComponent.contains(".store-") ||
                                  url.lastPathComponent.contains(".sqlite-") ||
                                  url.lastPathComponent.contains(".db-") {
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent(url.lastPathComponent + ".bak-\(stamp)")
            try? fm.moveItem(at: url, to: backup)
        }
        return primaryBackup
    }
}

extension ModelContext {
    func fetchAll<T: PersistentModel>(_ type: T.Type,
                                      sortBy: [SortDescriptor<T>] = []) -> [T] {
        // Sort in memory: pushing key-path SortDescriptors into the store
        // proved fragile, and personal-scale data sorts instantly anyway.
        let items = (try? fetch(FetchDescriptor<T>())) ?? []
        return sortBy.isEmpty ? items : items.sorted(using: sortBy)
    }
}
