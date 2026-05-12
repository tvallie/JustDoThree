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
