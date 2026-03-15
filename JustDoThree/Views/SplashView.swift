import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image("SplashScreen")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    SplashView()
}
