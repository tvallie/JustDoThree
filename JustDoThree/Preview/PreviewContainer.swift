import SwiftData
import Foundation

/// In-memory ModelContainer pre-seeded with sample data. Use in #Preview blocks.
@MainActor
let previewContainer: ModelContainer = {
    let schema = Schema([JDTask.self, DailyPlan.self, CompletionLog.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    let ctx = container.mainContext

    // -- Tasks --
    let t1 = JDTask(title: "Morning pages", sortOrder: 0)
    let t2 = JDTask(title: "30-minute workout", sortOrder: 1)
    let t3 = JDTask(title: "Review project proposal", sortOrder: 2)
    let t4 = JDTask(title: "Call dentist", sortOrder: 3)
    let t5 = JDTask(title: "Read for 20 minutes", sortOrder: 4)
    let t6 = JDTask(title: "Tidy desk", sortOrder: 5)
    t6.rolloverCount = 3
    [t1, t2, t3, t4, t5, t6].forEach { ctx.insert($0) }

    // -- Today's plan (t1 complete, t2 + t3 pending) --
    let plan = DailyPlan(date: Date())
    plan.taskIDs = [t1.id, t2.id, t3.id]
    plan.completedTaskIDs = [t1.id]
    ctx.insert(plan)

    // -- Yesterday's plan (t4 incomplete → rollover candidate) --
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    let prevPlan = DailyPlan(date: yesterday)
    prevPlan.taskIDs = [t4.id]
    prevPlan.completedTaskIDs = []
    ctx.insert(prevPlan)

    // -- Completion log --
    let log = CompletionLog(taskID: t1.id, taskTitle: t1.title, planDate: Date())
    ctx.insert(log)
    t1.isCompleted = true
    t1.completionDate = Date()

    try! ctx.save()
    return container
}()
