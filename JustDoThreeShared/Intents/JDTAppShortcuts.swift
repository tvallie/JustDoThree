import AppIntents

struct JDTAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add a task to \(.applicationName)",
                "Add to \(.applicationName)",
                "New task in \(.applicationName)"
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: AddWorkTaskIntent(),
            phrases: [
                "Add a work task to \(.applicationName)",
                "Add work task to \(.applicationName)",
                "New work task in \(.applicationName)"
            ],
            shortTitle: "Add Work Task",
            systemImageName: "briefcase"
        )
    }
}
