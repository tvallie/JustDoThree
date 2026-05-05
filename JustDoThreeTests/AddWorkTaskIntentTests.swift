import XCTest
import SwiftData
@testable import JustDoThree

final class AddWorkTaskIntentTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: JDTask.self, DailyPlan.self, CompletionLog.self,
            configurations: config
        )
    }

    @MainActor
    func test_perform_addsTaskToWorkBacklogAtTop() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let personal = JDTask(title: "personal item", sortOrder: 0, isWork: false)
        let existingWork = JDTask(title: "old work", sortOrder: 0, isWork: true)
        context.insert(personal)
        context.insert(existingWork)
        try context.save()

        var intent = AddWorkTaskIntent()
        intent.title = "ship release"
        _ = try await intent.perform(in: container)

        let all = try context.fetch(FetchDescriptor<JDTask>())
        let work = all.filter { $0.isWork }.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(work.count, 2)
        XCTAssertEqual(work.first?.title, "ship release")
        XCTAssertEqual(work.first?.isWork, true)
        XCTAssertLessThan(work.first!.sortOrder, existingWork.sortOrder)
        // Personal backlog untouched.
        XCTAssertEqual(all.filter { !$0.isWork }.count, 1)
    }

    @MainActor
    func test_perform_emptyTitle_throwsAndDoesNotInsert() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        var intent = AddWorkTaskIntent()
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
