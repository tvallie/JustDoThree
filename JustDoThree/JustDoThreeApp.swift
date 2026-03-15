import SwiftUI
import SwiftData

@main
struct JustDoThreeApp: App {
    @State private var appState = AppState()
    @State private var premium = PremiumManager()
    @State private var isVisible = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(premium)
                .tint(.teal)
                .opacity(isVisible ? 1 : 0)
                .scaleEffect(isVisible ? 1 : 0.98)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.4)) {
                        isVisible = true
                    }
                }
        }
        .modelContainer(for: [JDTask.self, DailyPlan.self, CompletionLog.self])
    }
}
