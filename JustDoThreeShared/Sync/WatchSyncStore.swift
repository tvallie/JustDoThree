import Foundation
import SwiftData

/// Watch-side store that materializes a TodaySnapshot into local SwiftData
/// so the watch's SwiftUI @Query views can drive off the same models the
/// phone uses. The phone is the source of truth; the watch wipes its
/// today/work plans and the referenced tasks on each successful apply.
///
/// `lastAppliedAt` / `setLastAppliedAt` are injection points so the store
/// is testable without UserDefaults. In production these read/write
/// `UserDefaults.standard` under `kLastAppliedSnapshotKey`.
@MainActor
final class WatchSyncStore {
    private let container: ModelContainer
    private let lastAppliedAt: () -> Date?
    private let setLastAppliedAt: (Date) -> Void

    init(container: ModelContainer,
         lastAppliedAt: @escaping () -> Date?,
         setLastAppliedAt: @escaping (Date) -> Void) {
        self.container = container
        self.lastAppliedAt = lastAppliedAt
        self.setLastAppliedAt = setLastAppliedAt
    }

    /// Convenience initializer that backs lastAppliedAt with UserDefaults.
    convenience init(container: ModelContainer) {
        let key = "jdt_watch_lastAppliedSnapshot"
        self.init(
            container: container,
            lastAppliedAt: {
                UserDefaults.standard.object(forKey: key) as? Date
            },
            setLastAppliedAt: { date in
                UserDefaults.standard.set(date, forKey: key)
            }
        )
    }

    /// Apply a snapshot. Out-of-order deliveries (older `generatedAt` than
    /// the last applied snapshot) are silently dropped to protect against
    /// WatchConnectivity re-delivery of stale messages.
    func apply(_ snapshot: TodaySnapshot) throws {
        if let last = lastAppliedAt(), snapshot.generatedAt <= last {
            return
        }
        let ctx = ModelContext(container)

        // Wipe today's plans + their referenced tasks. Keep CompletionLog
        // entries — the watch doesn't display them.
        try wipeTodayState(in: ctx, planDate: snapshot.planDate)

        // Insert tasks from both lists.
        for row in snapshot.today {
            let task = JDTask(title: row.title, isWork: false)
            task.id = row.id
            task.isCompleted = row.isCompleted
            ctx.insert(task)
        }
        for row in snapshot.work {
            let task = JDTask(title: row.title, isWork: true)
            task.id = row.id
            task.isCompleted = row.isCompleted
            ctx.insert(task)
        }

        // Re-create the personal plan (today) with primary + stretch.
        let personalPrimary = snapshot.today.filter { !$0.isStretch }
        let personalStretch = snapshot.today.filter { $0.isStretch }
        let personalPlan = DailyPlan(date: snapshot.planDate, isWork: false)
        personalPlan.taskIDs = personalPrimary.map(\.id)
        personalPlan.completedTaskIDs = personalPrimary.filter(\.isCompleted).map(\.id)
        personalPlan.stretchTaskIDs = personalStretch.map(\.id)
        personalPlan.completedStretchIDs = personalStretch.filter(\.isCompleted).map(\.id)
        ctx.insert(personalPlan)

        // Re-create the work plan.
        let workPrimary = snapshot.work.filter { !$0.isStretch }
        let workStretch = snapshot.work.filter { $0.isStretch }
        let workPlan = DailyPlan(date: snapshot.planDate, isWork: true)
        workPlan.taskIDs = workPrimary.map(\.id)
        workPlan.completedTaskIDs = workPrimary.filter(\.isCompleted).map(\.id)
        workPlan.stretchTaskIDs = workStretch.map(\.id)
        workPlan.completedStretchIDs = workStretch.filter(\.isCompleted).map(\.id)
        ctx.insert(workPlan)

        try ctx.save()
        setLastAppliedAt(snapshot.generatedAt)
    }

    private func wipeTodayState(in ctx: ModelContext, planDate: Date) throws {
        let plans = try ctx.fetch(FetchDescriptor<DailyPlan>())
            .filter { $0.date.isSameDay(as: planDate) }
        let referencedIDs = plans.flatMap { $0.taskIDs + $0.stretchTaskIDs }
        let tasksToDelete = try ctx.fetch(FetchDescriptor<JDTask>())
            .filter { referencedIDs.contains($0.id) }
        for t in tasksToDelete { ctx.delete(t) }
        for p in plans { ctx.delete(p) }
    }
}
