import SwiftUI

/// Mirrors LaunchScreen.storyboard exactly so there is no visible seam
/// between the OS launch screen and this SwiftUI overlay.
struct SplashView: View {
    var body: some View {
        ZStack {
            Color(red: 0.016, green: 0.039, blue: 0.086)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                Text("Just Do Three")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

#Preview {
    SplashView()
}
