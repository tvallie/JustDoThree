import SwiftUI

/// A shareable card summarizing the user's completed tasks for the day.
/// Uses static (non-adaptive) colors so ImageRenderer captures it correctly.
struct BragCardView: View {
    var date: Date
    var completedTasks: [String]
    var completedStretches: [String]
    var cardWidth: CGFloat = 360

    // Website palette — static colors, ImageRenderer-safe
    private let bgDeep      = Color(red: 0.039, green: 0.059, blue: 0.059)   // #0a0f0f
    private let bgBody      = Color(red: 0.063, green: 0.090, blue: 0.090)   // #101717
    private let bgFooter    = Color(red: 0.047, green: 0.071, blue: 0.071)   // #0c1212
    private let accent      = Color(red: 0.059, green: 0.725, blue: 0.694)   // #0fb9b1
    private let accentSoft  = Color(red: 0.549, green: 0.906, blue: 0.878)   // #8ce7e0
    private let textPrimary = Color(red: 0.949, green: 0.965, blue: 0.961)   // #f2f6f5
    private let textMuted   = Color(red: 0.949, green: 0.965, blue: 0.961).opacity(0.6)
    private let divider     = Color(red: 1, green: 1, blue: 1).opacity(0.08)

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: date)
    }

    // Header gradient matching website teal radial feel
    private var headerGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.059, green: 0.725, blue: 0.694),  // #0fb9b1
                Color(red: 0.020, green: 0.490, blue: 0.510)   // deeper teal
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
                    .foregroundColor(Color(white: 1.0, opacity: 0.78))
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
                                .foregroundColor(accent)
                            Text(title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // Stretch goals (optional)
                if !completedStretches.isEmpty {
                    divider
                        .frame(height: 1)
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("STRETCH GOALS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(accentSoft)
                            .kerning(0.8)

                        ForEach(completedStretches, id: \.self) { title in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(red: 0.718, green: 0.969, blue: 0.541)) // #b7f78a (website cta green)
                                Text(title)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bgBody)

            // ── Branded footer ──────────────────────────────────────────
            divider.frame(height: 1)

            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image("BulbIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text("justdothree.com")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(accentSoft)
                }
                Spacer()
                Text("Created with Just Do Three")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(bgFooter)
        }
        .frame(width: cardWidth)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.059, green: 0.725, blue: 0.694).opacity(0.18), radius: 24, x: 0, y: 8)
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
