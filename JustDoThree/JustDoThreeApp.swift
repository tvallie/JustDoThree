import SwiftUI
import SwiftData

@main
struct JustDoThreeApp: App {
    @State private var appState = AppState()
    @State private var premium = PremiumManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(premium)
                .tint(.teal)
                .task { await premium.loadProducts() }
        }
        .modelContainer(for: [JDTask.self, DailyPlan.self, CompletionLog.self])
    }
}
