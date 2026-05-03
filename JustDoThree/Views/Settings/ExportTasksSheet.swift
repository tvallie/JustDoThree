import SwiftUI
import SwiftData

struct ExportTasksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Query(sort: \JDTask.sortOrder) private var allTasks: [JDTask]

    enum ContextFilter: String, CaseIterable, Identifiable {
        case personal = "Personal"
        case work = "Work"
        case both = "Both"
        var id: String { rawValue }
    }

    @State private var contextFilter: ContextFilter = .both
    @State private var includeDate = true
    @State private var includeContext = true
    @State private var includeRecurring = true

    var body: some View {
        NavigationStack {
            Form {
                if appState.workModeEnabled {
                    Section("Context") {
                        Picker("Export", selection: $contextFilter) {
                            ForEach(ContextFilter.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section("Columns") {
                    Toggle("Date", isOn: $includeDate)
                    if contextFilter == .both && appState.workModeEnabled {
                        Toggle("Context", isOn: $includeContext)
                    }
                    Toggle("Recurring", isOn: $includeRecurring)
                }

                Section {
                    ShareLink(item: exportURL, preview: SharePreview(exportFileName, image: Image(systemName: "doc.text"))) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Export Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if !appState.workModeEnabled {
                    contextFilter = .personal
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - CSV generation

    private var exportFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "jdt-tasks-\(formatter.string(from: Date())).csv"
    }

    private var exportURL: URL {
        let content = buildCSV()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(exportFileName)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func buildCSV() -> String {
        var rows: [String] = []

        // Header
        var headers = ["Title"]
        if includeDate { headers.append("Date") }
        if includeContext && contextFilter == .both && appState.workModeEnabled { headers.append("Context") }
        if includeRecurring { headers.append("Recurring") }
        rows.append(headers.joined(separator: ","))

        // Filter tasks
        let filtered: [JDTask]
        switch contextFilter {
        case .personal: filtered = allTasks.filter { !$0.isWork }
        case .work:     filtered = allTasks.filter {  $0.isWork }
        case .both:     filtered = allTasks
        }

        // Date formatter
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // Data rows
        for task in filtered {
            var fields = [csvEscape(task.title)]
            if includeDate {
                fields.append(task.taskDate.map { dateFormatter.string(from: $0) } ?? "")
            }
            if includeContext && contextFilter == .both && appState.workModeEnabled {
                fields.append(task.isWork ? "Work" : "Personal")
            }
            if includeRecurring {
                fields.append(task.recurringRule.map { csvEscape($0.displayString) } ?? "")
            }
            rows.append(fields.joined(separator: ","))
        }

        return rows.joined(separator: "\n")
    }

    private func csvEscape(_ string: String) -> String {
        guard string.contains(",") || string.contains("\"") || string.contains("\n") else {
            return string
        }
        return "\"" + string.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
