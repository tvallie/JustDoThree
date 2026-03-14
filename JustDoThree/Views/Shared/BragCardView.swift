import SwiftUI

/// A shareable card summarizing the user's completed tasks for the day.
/// Uses static (non-adaptive) colors so ImageRenderer captures it correctly.
struct BragCardView: View {
    var date: Date
    var completedTasks: [String]
    var completedStretches: [String]
    var cardWidth: CGFloat = 360

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: date)
    }

    // Static teal gradient — ImageRenderer-safe (no adaptive colors)
    private var headerGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.0,  green: 0.62, blue: 0.62),
                Color(red: 0.05, green: 0.45, blue: 0.58)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Festive header ──────────────────────────────────────────
            VStack(spacing: 6) {
                Text("🎉")
                    .font(.system(size: 44))

                Text("Look what I did!")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(dateString)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(white: 1.0, opacity: 0.72))
                    .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity)
            .background(headerGradient)

            // ── Task body ───────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 12) {
                // Primary tasks
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(completedTasks, id: \.self) { title in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 17))
                                .foregroundColor(Color(red: 0.18, green: 0.68, blue: 0.28))
                            Text(title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(Color(white: 0.1))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // Stretch goals (optional)
                if !completedStretches.isEmpty {
                    Rectangle()
                        .fill(Color(white: 0.88))
                        .frame(height: 1)
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("STRETCH GOALS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(white: 0.55))
                            .kerning(0.8)

                        ForEach(completedStretches, id: \.self) { title in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(red: 0.98, green: 0.63, blue: 0.0))
                                Text(title)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(Color(white: 0.1))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)

            // ── Branded footer ──────────────────────────────────────────
            HStack(spacing: 7) {
                AppLogoView(size: 18)
                Text("justdothree.com")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(white: 0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Color(white: 0.96))
        }
        .frame(width: cardWidth)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(white: 0, opacity: 0.13), radius: 14, x: 0, y: 5)
    }
}

#Preview {
    ZStack {
        Color.secondary.opacity(0.15).ignoresSafeArea()
        BragCardView(
            date: Date(),
            completedTasks: ["Morning pages", "30-min workout", "Review project proposal"],
            completedStretches: ["Read 20 min"]
        )
        .padding()
    }
}
