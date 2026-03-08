import SwiftUI

struct TermsOfUseView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                LegalBrandedHeader(
                    documentTitle: "Terms of Use",
                    effectiveDate: "March 7, 2026"
                )

                Group {
                    LegalSection(heading: "Agreement") {
                        """
                        By downloading or using Just Do Three, you agree to these Terms of Use. If you \
                        do not agree, please do not use the app.
                        """
                    }

                    LegalSection(heading: "License") {
                        """
                        Just Do Three grants you a personal, non-exclusive, non-transferable, revocable \
                        license to use the app on Apple devices you own or control, in accordance with \
                        Apple's App Store Terms of Service.

                        You may not copy, modify, distribute, sell, or sublicense any part of the app.
                        """
                    }

                    LegalSection(heading: "Premium Features") {
                        """
                        Certain features are available through a one-time in-app purchase ("Premium"). \
                        The purchase is processed by Apple and is non-refundable except as required by \
                        applicable law or Apple's own refund policy.

                        Premium is tied to your Apple ID and can be restored on any device signed in \
                        with the same Apple ID using the "Restore purchase" option in Settings.
                        """
                    }

                    LegalSection(heading: "Acceptable Use") {
                        """
                        You agree to use Just Do Three only for lawful purposes and in a way that does \
                        not infringe the rights of others. You may not attempt to reverse-engineer, \
                        decompile, or tamper with the app.
                        """
                    }
                }

                Group {
                    LegalSection(heading: "Your Data") {
                        """
                        All data you enter into Just Do Three — including tasks, plans, and history — \
                        belongs to you. We do not claim any ownership over your content. See our \
                        Privacy Policy for details on how your data is handled.
                        """
                    }

                    LegalSection(heading: "Disclaimer of Warranties") {
                        """
                        Just Do Three is provided "as is" without warranties of any kind, express or \
                        implied. We do not warrant that the app will be uninterrupted, error-free, or \
                        free of harmful components. Use of the app is at your own risk.
                        """
                    }

                    LegalSection(heading: "Limitation of Liability") {
                        """
                        To the maximum extent permitted by law, we shall not be liable for any indirect, \
                        incidental, special, or consequential damages arising from your use of the app, \
                        including loss of data. Our total liability shall not exceed the amount you paid \
                        for the app.
                        """
                    }

                    LegalSection(heading: "Changes to These Terms") {
                        """
                        We may update these Terms of Use from time to time. Updated terms will be \
                        included in an app update with a revised effective date. Continued use of the \
                        app constitutes acceptance of the updated terms.
                        """
                    }

                    LegalSection(heading: "Governing Law") {
                        """
                        These Terms are governed by the laws of the jurisdiction in which the developer \
                        is based, without regard to conflict-of-law principles.
                        """
                    }

                    LegalSection(heading: "Contact") {
                        """
                        For questions about these Terms, please reach out via the App Store support \
                        link on the Just Do Three product page.
                        """
                    }
                }

                LegalFooter()
            }
            .padding(20)
        }
        .navigationTitle("Terms of Use")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        TermsOfUseView()
    }
}
