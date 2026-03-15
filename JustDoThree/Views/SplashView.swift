import SwiftUI

/// Mirrors LaunchScreen.storyboard exactly so there is no visible seam
/// between the OS launch screen and this SwiftUI overlay.
struct SplashView: View {
    @State private var glowAmount: Double = 0

    var body: some View {
        ZStack {
            Color(red: 0.024, green: 0.094, blue: 0.125)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .shadow(color: Color.teal.opacity(glowAmount), radius: 30)
                    .shadow(color: Color.teal.opacity(glowAmount * 0.5), radius: 60)
                Text("Just Do Three")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .onAppear {
            // Pulse glow in then out starting at 1.0s
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeIn(duration: 0.4)) { glowAmount = 0.8 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeOut(duration: 0.4)) { glowAmount = 0 }
                }
            }
        }
    }
}

#Preview {
    SplashView()
}
