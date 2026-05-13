import Foundation
import SwiftData

/// Result of a successful backlog insertion. The id is the new task's UUID
/// (so the watch can forward it to the phone for dedupe), and title is
/// the trimmed final string for confirmation dialogs/snippets.
struct InsertedBacklogTask: Equatable {
    let id: UUID
    let title: String
}

/// Trims `title`, validates it's non-empty, and inserts a new `JDTask` at the
/// top of the matching backlog (personal or work, per `isWork`).
///
/// "Top" means `min(sortOrder) - 1` filtered to the same `isWork` value, so
/// each backlog maintains its own ordering independent of the other.
///
/// Throws `AddTaskIntentError.emptyTitle` if `title` is empty after trimming.
@MainActor
func insertAtTopOfBacklog(title: String,
                          isWork: Bool,
                          in container: ModelContainer) throws -> InsertedBacklogTask {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw AddTaskIntentError.emptyTitle }
    let context = ModelContext(container)
    let predicate = #Predicate<JDTask> { $0.isWork == isWork }
    let existing = try context.fetch(FetchDescriptor<JDTask>(predicate: predicate))
    let minOrder = existing.map(\.sortOrder).min() ?? 0
    let task = JDTask(title: trimmed, sortOrder: minOrder - 1, isWork: isWork)
    context.insert(task)
    try context.save()
    return InsertedBacklogTask(id: task.id, title: trimmed)
}
