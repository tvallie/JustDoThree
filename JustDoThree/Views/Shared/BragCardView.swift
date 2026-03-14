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

    var body: some View {
        VStack(spacing: 0) {
            // Header band
            HStack(spacing: 10) {
                AppLogoView(size: 30)
                Text("Just Do Three")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(red: 0.0, green: 0.588, blue: 0.588))

            // Body
            VStack(alignment: .leading, spacing: 16) {
                Text(dateString)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(white: 0.45))

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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Stretch goals")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(white: 0.5))
                            .kerning(0.5)

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

            // Footer
            Text("Just Do Three")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(white: 0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(white: 0.96))
        }
        .frame(width: cardWidth)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(white: 0, opacity: 0.12), radius: 12, x: 0, y: 4)
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
