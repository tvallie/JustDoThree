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
}
