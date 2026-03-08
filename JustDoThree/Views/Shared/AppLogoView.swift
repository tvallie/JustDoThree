import SwiftUI
import UIKit

/// App logo loaded from Assets.xcassets ("AppLogo").
/// Falls back to a teal/green lightbulb gradient if the asset isn't present.
struct AppLogoView: View {
    var size: CGFloat = 60

    var body: some View {
        Group {
            if UIImage(named: "AppLogo") != nil {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "lightbulb.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.22)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(
                            colors: [Color.teal, Color.green],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    AppLogoView(size: 80)
        .padding()
}
