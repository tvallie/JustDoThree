import AppIntents
import SwiftData
import Foundation

struct AddWorkTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Work Task to JustDoThree"
    static var description = IntentDescription(
        "Add a new task to your work backlog in JustDoThree.",
        categoryName: "Tasks"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Task",
        description: "What you want to add to your work backlog.",
        requestValueDialog: IntentDialog("What's the work task?")
    )
    var title: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await perform(in: JDTModelContainer.shared)
    }

    /// Test seam: lets tests inject an in-memory container.
    @MainActor
    func perform(in container: ModelContainer) async throws -> some IntentResult & ProvidesDialog {
        let trimmed = try insertAtTopOfBacklog(title: title, isWork: true, in: container)
        return .result(dialog: IntentDialog("Added '\(trimmed)' to your work backlog."))
    }
}
