import SwiftUI
import SwiftData

@main
struct JustDoThreeApp: App {
    @State private var appState = AppState()
    @State private var premium = PremiumManager()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environment(appState)
                    .environment(premium)
                    .tint(.teal)
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showSplash = false
                    }
                }
            }
        }
        .modelContainer(for: [JDTask.self, DailyPlan.self, CompletionLog.self])
    }
}
