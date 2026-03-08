import SwiftUI
import UIKit

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                LegalBrandedHeader(
                    documentTitle: "Privacy Policy",
                    effectiveDate: "March 7, 2026"
                )

                Group {
                    LegalSection(heading: "Overview") {
                        """
                        Just Do Three is designed with your privacy in mind. The app stores all of your data \
                        locally on your device. We do not collect, transmit, or share any personal information.
                        """
                    }

                    LegalSection(heading: "Data We Do Not Collect") {
                        """
                        We do not collect:
                        • Your name, email address, or any contact information
                        • Your tasks, plans, or completion history
                        • Location data
                        • Device identifiers or advertising identifiers
                        • Crash reports or analytics (beyond what Apple provides to all developers)
                        • Any usage telemetry
                        """
                    }

                    LegalSection(heading: "Data Stored on Your Device") {
                        """
                        All app data — including tasks, daily plans, and completion history — is stored \
                        exclusively on your device using Apple's SwiftData framework. This data never \
                        leaves your device unless you explicitly enable iCloud sync in your device Settings.
                        """
                    }

                    LegalSection(heading: "iCloud Sync (Optional)") {
                        """
                        If you have iCloud Drive enabled for Just Do Three in your device Settings, \
                        Apple may sync your data across your devices via iCloud. This sync is governed \
                        by Apple's iCloud Terms and Conditions and Privacy Policy. We do not have access \
                        to data stored in your iCloud account.
                        """
                    }
                }

                Group {
                    LegalSection(heading: "Notifications") {
                        """
                        Just Do Three offers optional morning and evening reminders. Notifications are \
                        scheduled locally on your device using Apple's notification framework. No \
                        notification content is sent to or stored on any external server.

                        You can disable notifications at any time in your device Settings or within the app.
                        """
                    }

                    LegalSection(heading: "In-App Purchases") {
                        """
                        Just Do Three offers a one-time premium unlock via Apple's App Store. All \
                        payment processing is handled entirely by Apple. We never see or store your \
                        payment information. Your purchase receipt is verified through Apple's StoreKit \
                        framework on-device.
                        """
                    }

                    LegalSection(heading: "Third-Party Services") {
                        """
                        Just Do Three does not integrate with any third-party analytics, advertising, \
                        or data-collection services.
                        """
                    }

                    LegalSection(heading: "Children's Privacy") {
                        """
                        Just Do Three does not knowingly collect any personal information from anyone, \
                        including children under the age of 13. Because no data is collected, the app \
                        is suitable for all ages.
                        """
                    }

                    LegalSection(heading: "Changes to This Policy") {
                        """
                        If we update this Privacy Policy, the new version will be included in an app \
                        update and reflected here with a new effective date. Continued use of the app \
                        after an update constitutes acceptance of the revised policy.
                        """
                    }

                    LegalSection(heading: "Contact") {
                        """
                        If you have questions about this Privacy Policy, please reach out via the App \
                        Store support link on the Just Do Three product page.
                        """
                    }
                }

                LegalFooter()
            }
            .padding(20)
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shared legal components

/// Full-width branded header: logo + app name on top, document title + date below.
struct LegalBrandedHeader: View {
    let documentTitle: String
    let effectiveDate: String

    var body: some View {
        VStack(spacing: 20) {

            // ── Brand strip ──────────────────────────────────
            HStack(spacing: 14) {
                LegalAppLogo()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Just Do Three")
                        .font(.title2.bold())
                    Text("Focus on what matters most.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            // ── Document identity ─────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text(documentTitle)
                    .font(.title3.bold())
                Text("Effective \(effectiveDate)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// App logo: loads "AppLogo" from the asset catalog; falls back to an SF Symbol.
/// To use your own icon: drag your image into Assets.xcassets and name it "AppLogo".
struct LegalAppLogo: View {
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
                    .padding(14)
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
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
    }
}

/// Section block with a bold heading and body text.
struct LegalSection: View {
    let heading: String
    let text: String

    init(heading: String, content: () -> String) {
        self.heading = heading
        self.text = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heading)
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Copyright footer shown at the bottom of every legal document.
struct LegalFooter: View {
    private var copyrightYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    var body: some View {
        VStack(spacing: 12) {
            Divider()
            Text("© \(copyrightYear) Todd Vallie. All rights reserved.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
