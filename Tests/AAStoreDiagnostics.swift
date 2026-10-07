import Foundation
import SwiftData
import Testing
@testable import PocketBrains

/// Named to sort (and therefore run) before every other suite. Inserts one
/// instance of each model, ordered by attribute-type novelty, with a
/// breadcrumb after every step — the first missing breadcrumb in a CI log
/// names the exact model/type that traps the iOS 26.5 runtime.
@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct AAStoreDiagnostics {
    @Test func typedInsertWalk() throws {
        print("DIAG thread.isMain=\(Thread.isMainThread)")
        let container = Store.makeContainer(inMemory: true)
        let context = container.mainContext
        print("DIAG container ok")

        // 1. Strings + dates + optional to-one relationship (proven good).
        context.insert(Note(title: "diag note", body: "strings and dates"))
        try context.save()
        print("DIAG note ok")

        // 2. String + optional Data.
        let message = ChatMessage(role: .user, text: "diag message")
        message.toolEvents = [.init(toolName: "t", summary: "s", detail: "d", succeeded: true)]
        context.insert(message)
        try context.save()
        print("DIAG chatMessage ok (String + Data?)")

        // 3. Non-optional Data + Int + unique UUID.
        context.insert(EmbeddingRecord(entityID: UUID(), kind: .note,
                                       vector: [0.1, 0.2], contentHash: 42))
        try context.save()
        print("DIAG embeddingRecord ok (Data + Int)")

        // 4. Int attribute + to-many relationship arrays.
        let project = Project(name: "diag project")
        context.insert(project)
        try context.save()
        print("DIAG project ok (Int + relationships)")

        // 5. Optional Date + to-one relationship.
        context.insert(Milestone(title: "diag milestone", targetDate: .now, project: project))
        try context.save()
        print("DIAG milestone ok (Date? + relation)")

        // 6. The historic crasher: Int + Data + two Date? + relationship.
        let task = TaskItem(title: "diag task", dueDate: .now, priority: .high)
        print("DIAG task init ok")
        context.insert(task)
        print("DIAG task insert ok")
        try context.save()
        print("DIAG task save ok")
        task.project = project
        try context.save()
        print("DIAG task relation ok")
        task.blockedByIDs = [UUID()]
        try context.save()
        print("DIAG task packedData ok")

        // 7. v0.2 journal: String + Data + Date? + unique UUID.
        context.insert(JournalEntry(groupID: "diag", toolName: "createTask", summary: "diag",
                                    inverse: [.init(kind: .deleteTask, id: task.id)]))
        try context.save()
        print("DIAG journalEntry ok")

        let fetched = context.fetchAll(TaskItem.self,
                                       sortBy: [.init(\.createdAt, order: .reverse)])
        print("DIAG sorted fetch ok count=\(fetched.count)")
        #expect(fetched.count == 1)
        #expect(project.tasks?.count == 1)
        print("DIAG inverse traversal ok")
    }
}
