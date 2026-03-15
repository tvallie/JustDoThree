import SwiftUI
import SwiftData

@main
struct JustDoThreeApp: App {
    @State private var appState = AppState()
    @State private var premium = PremiumManager()
    @State private var showSplash = true
    @State private var splashOpacity: Double = 1.0
    @State private var splashScale: Double = 1.0

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environment(appState)
                    .environment(premium)
                    .tint(.teal)
                if showSplash {
                    SplashView()
                        .opacity(splashOpacity)
                        .scaleEffect(splashScale)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation(.easeIn(duration: 0.55)) {
                        splashOpacity = 0
                        splashScale = 0.88
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        showSplash = false
                    }
                }
            }
        }
        .modelContainer(for: [JDTask.self, DailyPlan.self, CompletionLog.self])
    }
}
