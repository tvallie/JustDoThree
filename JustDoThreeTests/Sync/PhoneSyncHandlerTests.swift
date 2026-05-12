import XCTest
import SwiftData
@testable import JustDoThree

@MainActor
final class PhoneSyncHandlerTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var handler: PhoneSyncHandler!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: JDTask.self, DailyPlan.self, CompletionLog.self,
            configurations: config
        )
        context = ModelContext(container)
        handler = PhoneSyncHandler(container: container)
    }

    // MARK: - complete

    func test_apply_completionCommand_marks_primary_task_complete() throws {
        let task = JDTask(title: "Test")
        let plan = DailyPlan(date: Date())
        context.insert(task)
        context.insert(plan)
        plan.taskIDs = [task.id]
        try context.save()

        try handler.apply(CompletionCommand(
            schemaVersion: SyncSchema.current,
            taskID: task.id, action: .complete,
            issuedAt: Date()
        ))

        let updatedTask = try XCTUnwrap(
            try context.fetch(FetchDescriptor<JDTask>()).first { $0.id == task.id }
        )
        let updatedPlan = try XCTUnwrap(
            try context.fetch(FetchDescriptor<DailyPlan>()).first
        )
        XCTAssertTrue(updatedTask.isCompleted)
        XCTAssertTrue(updatedPlan.completedTaskIDs.contains(task.id))
    }

    func test_apply_completionCommand_marks_stretch_task_complete() throws {
        let task = JDTask(title: "Stretch task")
        let plan = DailyPlan(date: Date())
        context.insert(task)
        context.insert(plan)
        plan.stretchTaskIDs = [task.id]
        try context.save()

        try handler.apply(CompletionCommand(
            schemaVersion: SyncSchema.current,
            taskID: task.id, action: .complete,
            issuedAt: Date()
        ))

        let updatedPlan = try XCTUnwrap(
            try context.fetch(FetchDescriptor<DailyPlan>()).first
        )
        XCTAssertTrue(updatedPlan.completedStretchIDs.contains(task.id),
                      "Stretch tasks should land in completedStretchIDs, not completedTaskIDs")
        XCTAssertFalse(updatedPlan.completedTaskIDs.contains(task.id))
    }

    // MARK: - uncomplete

    func test_apply_uncompleteCommand_clears_primary_completion() throws {
        let task = JDTask(title: "Test")
        let plan = DailyPlan(date: Date())
        context.insert(task)
        context.insert(plan)
        plan.taskIDs = [task.id]
        plan.completedTaskIDs = [task.id]
        task.isCompleted = true
        try context.save()

        try handler.apply(CompletionCommand(
            schemaVersion: SyncSchema.current,
            taskID: task.id, action: .uncomplete,
            issuedAt: Date()
        ))

        let updatedTask = try XCTUnwrap(
            try context.fetch(FetchDescriptor<JDTask>()).first { $0.id == task.id }
        )
        let updatedPlan = try XCTUnwrap(
            try context.fetch(FetchDescriptor<DailyPlan>()).first
        )
        XCTAssertFalse(updatedTask.isCompleted)
        XCTAssertFalse(updatedPlan.completedTaskIDs.contains(task.id))
    }

    func test_apply_uncompleteCommand_clears_stretch_completion() throws {
        let task = JDTask(title: "Stretch")
        let plan = DailyPlan(date: Date())
        context.insert(task)
        context.insert(plan)
        plan.stretchTaskIDs = [task.id]
        plan.completedStretchIDs = [task.id]
        task.isCompleted = true
        try context.save()

        try handler.apply(CompletionCommand(
            schemaVersion: SyncSchema.current,
            taskID: task.id, action: .uncomplete,
            issuedAt: Date()
        ))

        let updatedPlan = try XCTUnwrap(
            try context.fetch(FetchDescriptor<DailyPlan>()).first
        )
        XCTAssertFalse(updatedPlan.completedStretchIDs.contains(task.id))
    }

    // MARK: - WatchIntentResult

    func test_apply_intentResult_inserts_personal_backlog_task_with_clientID() throws {
        let clientID = UUID()
        try handler.apply(WatchIntentResult(
            schemaVersion: SyncSchema.current,
            clientID: clientID,
            list: .personalBacklog,
            title: "  Pick up milk  ",
            createdAt: Date()
        ))

        let tasks = try context.fetch(FetchDescriptor<JDTask>())
        XCTAssertEqual(tasks.count, 1)
        let inserted = try XCTUnwrap(tasks.first)
        XCTAssertEqual(inserted.id, clientID, "Inserted task must use the watch-supplied clientID")
        XCTAssertEqual(inserted.title, "Pick up milk", "Title should be trimmed")
        XCTAssertFalse(inserted.isWork)
    }

    func test_apply_intentResult_inserts_work_backlog_task() throws {
        try handler.apply(WatchIntentResult(
            schemaVersion: SyncSchema.current,
            clientID: UUID(),
            list: .workBacklog,
            title: "Email Bob",
            createdAt: Date()
        ))

        let tasks = try context.fetch(FetchDescriptor<JDTask>())
        XCTAssertEqual(tasks.count, 1)
        XCTAssertTrue(try XCTUnwrap(tasks.first).isWork)
    }

    func test_apply_intentResult_is_idempotent_on_duplicate_clientID() throws {
        let result = WatchIntentResult(
            schemaVersion: SyncSchema.current,
            clientID: UUID(),
            list: .personalBacklog,
            title: "Buy stamps",
            createdAt: Date()
        )

        try handler.apply(result)
        try handler.apply(result)
        try handler.apply(result)

        let tasks = try context.fetch(FetchDescriptor<JDTask>())
        XCTAssertEqual(tasks.count, 1, "Duplicate clientID must dedupe")
    }

    func test_apply_intentResult_inserts_at_top_of_correct_backlog() throws {
        // Seed existing personal + work tasks; sortOrder of personal min = 5,
        // work min = 10. New personal insertion should be 4; new work would be 9.
        let p1 = JDTask(title: "Personal old 1", sortOrder: 5, isWork: false)
        let w1 = JDTask(title: "Work old 1",     sortOrder: 10, isWork: true)
        context.insert(p1); context.insert(w1)
        try context.save()

        try handler.apply(WatchIntentResult(
            schemaVersion: SyncSchema.current,
            clientID: UUID(),
            list: .personalBacklog,
            title: "New personal",
            createdAt: Date()
        ))

        let personalTasks = try context.fetch(FetchDescriptor<JDTask>())
            .filter { !$0.isWork }
        let newOne = try XCTUnwrap(personalTasks.first { $0.title == "New personal" })
        XCTAssertEqual(newOne.sortOrder, 4, "Should be one less than min personal sortOrder")
    }

    func test_apply_intentResult_empty_title_is_a_noop() throws {
        XCTAssertNoThrow(try handler.apply(WatchIntentResult(
            schemaVersion: SyncSchema.current,
            clientID: UUID(),
            list: .personalBacklog,
            title: "   ",
            createdAt: Date()
        )))
        let tasks = try context.fetch(FetchDescriptor<JDTask>())
        XCTAssertTrue(tasks.isEmpty, "Empty/whitespace title should not insert")
    }

    // MARK: - unknown task

    func test_apply_unknown_taskID_is_a_noop() throws {
        // No task seeded. Handler should silently return rather than throw.
        XCTAssertNoThrow(try handler.apply(CompletionCommand(
            schemaVersion: SyncSchema.current,
            taskID: UUID(), action: .complete,
            issuedAt: Date()
        )))
    }
}
