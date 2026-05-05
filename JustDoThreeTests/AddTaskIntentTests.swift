import XCTest
import SwiftData
@testable import JustDoThree

final class AddTaskIntentTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: JDTask.self, DailyPlan.self, CompletionLog.self,
            configurations: config
        )
    }

    @MainActor
    func test_perform_addsTaskToPersonalBacklogAtTop() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // Pre-existing items so we can prove the new task is at the top.
        let existing = JDTask(title: "old personal", sortOrder: 0, isWork: false)
        let work = JDTask(title: "work item", sortOrder: 0, isWork: true)
        context.insert(existing)
        context.insert(work)
        try context.save()

        var intent = AddTaskIntent()
        intent.title = "buy milk"

        _ = try await intent.perform(in: container)

        let all = try context.fetch(FetchDescriptor<JDTask>())
        let personal = all.filter { !$0.isWork }.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(personal.count, 2)
        XCTAssertEqual(personal.first?.title, "buy milk")
        XCTAssertEqual(personal.first?.isWork, false)
        XCTAssertLessThan(personal.first!.sortOrder, existing.sortOrder)
        // Work backlog untouched.
        XCTAssertEqual(all.filter { $0.isWork }.count, 1)
    }

    @MainActor
    func test_perform_personalSortOrder_scopedToPersonalBacklog() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // Work backlog has a deeply-negative sortOrder; new personal task must
        // ignore it and only sort relative to other personal items.
        let work = JDTask(title: "deep work", sortOrder: -100, isWork: true)
        let personal = JDTask(title: "old personal", sortOrder: 5, isWork: false)
        context.insert(work)
        context.insert(personal)
        try context.save()

        var intent = AddTaskIntent()
        intent.title = "buy milk"
        _ = try await intent.perform(in: container)

        let all = try context.fetch(FetchDescriptor<JDTask>())
        let personalSorted = all.filter { !$0.isWork }.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(personalSorted.first?.title, "buy milk")
        // Should be 4 (one less than the existing personal min of 5), NOT -101.
        XCTAssertEqual(personalSorted.first?.sortOrder, 4)
    }

    @MainActor
    func test_perform_emptyTitle_throwsAndDoesNotInsert() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        var intent = AddTaskIntent()
        intent.title = "   "

        do {
            _ = try await intent.perform(in: container)
            XCTFail("Expected error for empty title")
        } catch {
            // expected
        }

        let all = try context.fetch(FetchDescriptor<JDTask>())
        XCTAssertTrue(all.isEmpty, "Should not insert a task for empty/whitespace title")
    }
}
