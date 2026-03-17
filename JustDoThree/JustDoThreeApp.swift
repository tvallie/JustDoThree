import SwiftUI
import SwiftData

@main
struct JustDoThreeApp: App {
    @State private var appState = AppState()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environment(appState)
                    .tint(.teal)
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { !appState.hasSeenOnboarding },
                set: { if !$0 { appState.hasSeenOnboarding = true } }
            )) {
                OnboardingView()
                    .environment(appState)
            }
            .onAppear {
                ReviewManager.shared.recordFirstLaunchIfNeeded()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        showSplash = false
                    }
                }
            }
        }
        .modelContainer(for: [JDTask.self, DailyPlan.self, CompletionLog.self])
    }
}
