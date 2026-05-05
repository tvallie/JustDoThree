import AppIntents
import SwiftData
import Foundation

enum AddTaskIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case emptyTitle

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .emptyTitle: return "I didn't catch a task — try again."
        }
    }
}

struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Task to JustDoThree"
    static var description = IntentDescription(
        "Add a new task to your personal backlog in JustDoThree.",
        categoryName: "Tasks"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Task",
        description: "What you want to add to your backlog.",
        requestValueDialog: IntentDialog("What's the task?")
    )
    var title: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await perform(in: JDTModelContainer.shared)
    }

    /// Test seam: lets tests inject an in-memory container.
    @MainActor
    func perform(in container: ModelContainer) async throws -> some IntentResult & ProvidesDialog {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AddTaskIntentError.emptyTitle }
        let context = ModelContext(container)
        let existing = try context.fetch(FetchDescriptor<JDTask>())
        let minOrder = existing.map(\.sortOrder).min() ?? 0
        let task = JDTask(title: trimmed, sortOrder: minOrder - 1, isWork: false)
        context.insert(task)
        try context.save()
        return .result(dialog: IntentDialog("Added '\(trimmed)' to your backlog."))
    }
}
