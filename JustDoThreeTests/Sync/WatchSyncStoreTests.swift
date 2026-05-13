import XCTest
import SwiftData
@testable import JustDoThree

@MainActor
final class WatchSyncStoreTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var lastApplied: Date?
    var store: WatchSyncStore!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: JDTask.self, DailyPlan.self, CompletionLog.self,
            configurations: config
        )
        context = ModelContext(container)
        lastApplied = nil
        store = WatchSyncStore(
            container: container,
            lastAppliedAt: { [weak self] in self?.lastApplied },
            setLastAppliedAt: { [weak self] in self?.lastApplied = $0 }
        )
    }

    // MARK: - Snapshot apply

    func test_apply_snapshot_seeds_empty_store_with_today_and_work() throws {
        let today = Calendar.current.startOfDay(for: Date())
        let pID = UUID(); let sID = UUID(); let wID = UUID()
        let snap = TodaySnapshot(
            schemaVersion: SyncSchema.current,
            planDate: today,
            today: [
                .init(id: pID, title: "Primary", isCompleted: false, isStretch: false),
                .init(id: sID, title: "Stretch", isCompleted: true,  isStretch: true)
            ],
            work: [.init(id: wID, title: "Work", isCompleted: false, isStretch: false)],
            generatedAt: Date()
        )

        try store.apply(snap)

        let tasks = try context.fetch(FetchDescriptor<JDTask>())
        XCTAssertEqual(Set(tasks.map(\.id)), [pID, sID, wID])
        XCTAssertTrue(try XCTUnwrap(tasks.first { $0.id == wID }).isWork)

        let plans = try context.fetch(FetchDescriptor<DailyPlan>())
        XCTAssertEqual(plans.count, 2)
        let personal = try XCTUnwrap(plans.first { !$0.isWork })
        XCTAssertEqual(personal.taskIDs, [pID])
        XCTAssertEqual(personal.stretchTaskIDs, [sID])
        XCTAssertEqual(personal.completedStretchIDs, [sID])
        XCTAssertTrue(personal.completedTaskIDs.isEmpty)

        let work = try XCTUnwrap(plans.first { $0.isWork })
        XCTAssertEqual(work.taskIDs, [wID])
    }

    func test_apply_snapshot_replaces_stale_data() throws {
        let today = Calendar.current.startOfDay(for: Date())
        let oldID = UUID(); let newID = UUID()

        // Seed old state via a first snapshot
        try store.apply(TodaySnapshot(
            schemaVersion: SyncSchema.current,
            planDate: today,
            today: [.init(id: oldID, title: "Old", isCompleted: false, isStretch: false)],
            work: [],
            generatedAt: Date(timeIntervalSince1970: 1_000)
        ))

        // New snapshot supersedes
        try store.apply(TodaySnapshot(
            schemaVersion: SyncSchema.current,
            planDate: today,
            today: [.init(id: newID, title: "New", isCompleted: false, isStretch: false)],
            work: [],
            generatedAt: Date(timeIntervalSince1970: 2_000)
        ))

        let tasks = try context.fetch(FetchDescriptor<JDTask>())
        XCTAssertEqual(tasks.map(\.id), [newID])
        let plan = try XCTUnwrap(try context.fetch(FetchDescriptor<DailyPlan>()).first { !$0.isWork })
        XCTAssertEqual(plan.taskIDs, [newID])
    }

    func test_apply_snapshot_ignores_out_of_order_delivery() throws {
        let today = Calendar.current.startOfDay(for: Date())
        let newerID = UUID(); let olderID = UUID()

        // Apply newer first
        try store.apply(TodaySnapshot(
            schemaVersion: SyncSchema.current,
            planDate: today,
            today: [.init(id: newerID, title: "Newer", isCompleted: false, isStretch: false)],
            work: [],
            generatedAt: Date(timeIntervalSince1970: 2_000)
        ))

        // Older delivery arriving late should be discarded
        try store.apply(TodaySnapshot(
            schemaVersion: SyncSchema.current,
            planDate: today,
            today: [.init(id: olderID, title: "Older", isCompleted: false, isStretch: false)],
            work: [],
            generatedAt: Date(timeIntervalSince1970: 1_000)
        ))

        let tasks = try context.fetch(FetchDescriptor<JDTask>())
        XCTAssertEqual(tasks.map(\.id), [newerID], "Older snapshot must not overwrite newer")
    }

    func test_apply_empty_snapshot_clears_existing_today() throws {
        let today = Calendar.current.startOfDay(for: Date())
        let id = UUID()
        try store.apply(TodaySnapshot(
            schemaVersion: SyncSchema.current,
            planDate: today,
            today: [.init(id: id, title: "Will vanish", isCompleted: false, isStretch: false)],
            work: [],
            generatedAt: Date(timeIntervalSince1970: 1_000)
        ))

        try store.apply(TodaySnapshot(
            schemaVersion: SyncSchema.current,
            planDate: today,
            today: [],
            work: [],
            generatedAt: Date(timeIntervalSince1970: 2_000)
        ))

        XCTAssertTrue(try context.fetch(FetchDescriptor<JDTask>()).isEmpty)
        // Personal plan may exist with empty arrays — that's the
        // "no items today" state, which is distinct from "no plan at all".
        let plans = try context.fetch(FetchDescriptor<DailyPlan>())
        for plan in plans {
            XCTAssertTrue(plan.taskIDs.isEmpty)
            XCTAssertTrue(plan.stretchTaskIDs.isEmpty)
        }
    }

    func test_apply_updates_lastAppliedAt() throws {
        let stamp = Date(timeIntervalSince1970: 5_000)
        try store.apply(TodaySnapshot(
            schemaVersion: SyncSchema.current,
            planDate: Date(),
            today: [], work: [],
            generatedAt: stamp
        ))
        XCTAssertEqual(lastApplied, stamp)
    }
}
