import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var notifManager = NotificationManager.shared
    @AppStorage("jdt_autoScheduleRecurring") private var autoScheduleRecurring = false
    @AppStorage("jdt_enableTaskDates") private var enableTaskDates = false

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

                // MARK: - Features
                Section {
                    Toggle(isOn: $autoScheduleRecurring) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-schedule recurring tasks")
                            Text("Adds recurring tasks to your plan automatically on their scheduled day")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle(isOn: $enableTaskDates) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Task Dates")
                            Text("Shows an optional date field in backlog task details.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Features")
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
                    Text("© \(String(currentYear)) Todd Vallie. All rights reserved.")
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }

                #if DEBUG
                Section("Debug") {
                    Button("Preview Rollover Sheet") {
                        appState.previewRolloverSheet(context: modelContext)
                    }
                    Button("Seed History Data") {
                        appState.seedHistoryData(context: modelContext)
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
        }
    }

    private func requestNotifAuth() {
        Task {
            let granted = await NotificationManager.shared.requestAuthorization()
            if granted { NotificationManager.shared.reschedule() }
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
        .environment(AppState())
        .modelContainer(previewContainer)
}
