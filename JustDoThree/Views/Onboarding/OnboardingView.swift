import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var page = 0

    private let slides: [OnboardingPageView.Model] = [
        .init(
            symbol: "3.circle.fill",
            title: "Focus on three things",
            message: "Each day, pick just three tasks to get done. Not a to-do list — a short list you'll actually finish."
        ),
        .init(
            symbol: "tray.full",
            title: "Build your backlog",
            message: "Add tasks one at a time, paste a whole list, or import from a file. Your backlog is always there when you're ready to plan."
        ),
        .init(
            symbol: "star.circle",
            title: "Done? Go further.",
            message: "Check off your tasks as you go. Once you finish your three, add stretch goals to keep the momentum."
        ),
        .init(
            symbol: "gearshape",
            title: "Set it and forget it",
            message: "Mark tasks as recurring and they'll show up automatically each day. Set a daily reminder and tweak your preferences in Settings."
        ),
    ]

    private var isLastPage: Bool { page == slides.count - 1 }

    var body: some View {
        ZStack(alignment: .top) {
            // Slides
            TabView(selection: $page) {
                ForEach(slides.indices, id: \.self) { index in
                    OnboardingPageView(model: slides[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page)
            .ignoresSafeArea(edges: .top)

            // Skip button
            HStack {
                Spacer()
                Button("Skip") {
                    appState.hasSeenOnboarding = true
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 56)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Button {
                    if isLastPage {
                        appState.hasSeenOnboarding = true
                    } else {
                        withAnimation {
                            page += 1
                        }
                    }
                } label: {
                    Text(isLastPage ? "Get Started" : "Next")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
            }
            .background(Color(.systemBackground).opacity(0.95))
        }
    }
}

// MARK: - Page View

struct OnboardingPageView: View {
    struct Model {
        let symbol: String
        let title: String
        let message: String
    }

    let model: Model

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: model.symbol)
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(.teal)

            VStack(spacing: 12) {
                Text(model.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(model.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 40)
    }
}

#Preview {
    OnboardingView()
        .environment(AppState())
}
