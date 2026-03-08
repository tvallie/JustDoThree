import SwiftUI

struct SettingsView: View {
    @Environment(PremiumManager.self) private var premium
    @State private var showUpgrade = false
    @State private var notifManager = NotificationManager.shared

    // Notification bindings backed by NotificationManager
    @State private var morningOn: Bool = NotificationManager.shared.morningEnabled
    @State private var eveningOn: Bool = NotificationManager.shared.eveningEnabled
    @State private var morningTime: Date = timeDate(h: NotificationManager.shared.morningHour,
                                                     m: NotificationManager.shared.morningMinute)
    @State private var eveningTime: Date = timeDate(h: NotificationManager.shared.eveningHour,
                                                     m: NotificationManager.shared.eveningMinute)

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Notifications
                Section {
                    Toggle("Morning reminder", isOn: $morningOn)
                        .onChange(of: morningOn) { _, v in
                            notifManager.morningEnabled = v
                            if v { requestNotifAuth() }
                        }
                    if morningOn {
                        DatePicker("Time", selection: $morningTime, displayedComponents: .hourAndMinute)
                            .onChange(of: morningTime) { _, v in
                                let c = Calendar.current.dateComponents([.hour, .minute], from: v)
                                notifManager.morningHour = c.hour ?? 8
                                notifManager.morningMinute = c.minute ?? 0
                            }
                    }

                    Toggle("Evening check-in", isOn: $eveningOn)
                        .onChange(of: eveningOn) { _, v in
                            notifManager.eveningEnabled = v
                            if v { requestNotifAuth() }
                        }
                    if eveningOn {
                        DatePicker("Time", selection: $eveningTime, displayedComponents: .hourAndMinute)
                            .onChange(of: eveningTime) { _, v in
                                let c = Calendar.current.dateComponents([.hour, .minute], from: v)
                                notifManager.eveningHour = c.hour ?? 19
                                notifManager.eveningMinute = c.minute ?? 0
                            }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Reminders are optional and never guilt-driven.")
                }

                // MARK: - Premium
                Section("Premium") {
                    if premium.isPremium {
                        Label("Just Do Three Premium — unlocked", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Just Do Three Premium")
                                    .font(.body)
                                Text("7-day planning · analytics · recurring tasks")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("$2.99") {
                                showUpgrade = true
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        Button("Restore purchase") {
                            Task { await premium.restorePurchases() }
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                }

                // MARK: - About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.releaseVersion)
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink("Privacy Policy") {
                        PrivacyPolicyView()
                    }
                    NavigationLink("Terms of Use") {
                        TermsOfUseView()
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("© \(currentYear) Todd Vallie. All rights reserved.")
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }

                // DEBUG (remove before release)
                #if DEBUG
                Section("Debug") {
                    Button("Toggle Premium") {
                        premium.isPremium ? premium.revokePremium() : premium.simulatePurchase()
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
        }
        .sheet(isPresented: $showUpgrade) {
            UpgradeSheet()
        }
    }

    private func requestNotifAuth() {
        Task {
            _ = await NotificationManager.shared.requestAuthorization()
            NotificationManager.shared.reschedule()
        }
    }
}

// MARK: - Upgrade sheet

struct UpgradeSheet: View {
    @Environment(PremiumManager.self) private var premium
    @Environment(\.dismiss) private var dismiss
    @State private var purchasing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 52))
                        .foregroundStyle(.yellow)
                        .padding(.top, 12)

                    VStack(spacing: 8) {
                        Text("Just Do Three Premium")
                            .font(.title2.bold())
                        Text("One-time purchase · No subscription")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        FeatureRow(icon: "calendar.badge.clock", text: "Plan tasks up to 7 days ahead")
                        FeatureRow(icon: "chart.bar.xaxis", text: "Day, week, month & year analytics")
                        FeatureRow(icon: "arrow.triangle.2.circlepath", text: "Weekly & monthly recurring tasks")
                        FeatureRow(icon: "star.fill", text: "Stretch goal tracking & insights")
                        FeatureRow(icon: "exclamationmark.triangle", text: "Most avoided tasks report")
                    }
                    .padding(.horizontal)

                    Button {
                        purchasing = true
                        Task {
                            await premium.purchase()
                            purchasing = false
                            dismiss()
                        }
                    } label: {
                        Group {
                            if purchasing {
                                ProgressView()
                            } else {
                                Text("Unlock for $2.99")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(purchasing)
                    .padding(.horizontal)

                    Button("Restore purchase") {
                        Task {
                            await premium.restorePurchases()
                            dismiss()
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Helpers

private func timeDate(h: Int, m: Int) -> Date {
    var c = DateComponents()
    c.hour = h; c.minute = m
    return Calendar.current.date(from: c) ?? Date()
}

extension Bundle {
    var releaseVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

#Preview {
    SettingsView()
        .environment(PremiumManager())
}
