import SwiftUI

/// Two-page swipeable root: Today (personal) on page 1, Work on page 2.
/// Page indicator dots appear at the bottom via .tabViewStyle(.page).
struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { DailyPlanPage(isWork: false) }
            NavigationStack { DailyPlanPage(isWork: true) }
        }
        .tabViewStyle(.page)
    }
}

#Preview {
    RootView()
}
