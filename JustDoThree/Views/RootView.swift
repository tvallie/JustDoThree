import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "checkmark.circle")
                }

            BacklogView()
                .tabItem {
                    Label("Backlog", systemImage: "tray")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }

            PlanView()
                .tabItem {
                    Label("Plan", systemImage: "calendar")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    RootView()
        .environment(AppState())
        .environment(PremiumManager())
        .modelContainer(previewContainer)
}
