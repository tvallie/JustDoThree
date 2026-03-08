import SwiftUI

/// A teaser banner shown in place of premium features.
struct PremiumGateView: View {
    let featureName: String
    var onUpgrade: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text(featureName)
                    .font(.headline)
                Text("This feature is part of Just Do Three Premium — a one-time unlock.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onUpgrade) {
                Label("Unlock for $2.99", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    PremiumGateView(featureName: "Weekly Planning", onUpgrade: {})
}
