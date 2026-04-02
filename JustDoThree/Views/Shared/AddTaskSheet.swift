import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private let addTaskSheetOrdinalFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .ordinal
    return f
}()

/// Sheet for creating a new task or editing an existing task title.
struct AddTaskSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage("jdt_enableTaskDates") private var enableTaskDates = false

    /// Pass nil to create a new task; pass an existing task to edit its title.
    var existingTask: JDTask? = nil

    /// Called after a new task is successfully created.
    var onCreated: ((JDTask) -> Void)? = nil

    @State private var title: String = ""
    @State private var showImportInfo = false
    @State private var showPasteSheet = false
    @State private var recurringPattern: RecurringRule.Pattern? = nil
    @State private var recurringWeekday: Int = 2   // Monday (Calendar weekday 2)
    @State private var recurringDayOfMonth: Int = 1
    @State private var taskDateEnabled = false
    @State private var selectedTaskDate: Date? = nil
    @Query(sort: \JDTask.sortOrder) private var allTasks: [JDTask]

    var isEditing: Bool { existingTask != nil }
    private var minimumTaskDate: Date { Date().startOfDay }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What do you need to do?", text: $title, axis: .vertical)
                        .lineLimit(1...4)
                }

                // File import row — only shown when creating (not editing)
                if !isEditing {
                    Section {
                        Button {
                            showPasteSheet = true
                        } label: {
                            Label("Paste tasks", systemImage: "doc.on.clipboard")
                                .font(.subheadline)
                        }
                        Button {
                            showImportInfo = true
                        } label: {
                            Label("Import from .txt or .csv", systemImage: "doc.badge.plus")
                                .font(.subheadline)
                        }
                    } footer: {
                        Text("Add multiple tasks at once from paste or a file.")
                    }
                }

                // Recurrence section
                Section {
                    Picker("Repeat", selection: $recurringPattern) {
                        Text("None").tag(Optional<RecurringRule.Pattern>.none)
                        Text("Weekly").tag(Optional(RecurringRule.Pattern.weekly))
                        Text("Monthly").tag(Optional(RecurringRule.Pattern.monthly))
                    }

                    if recurringPattern == .weekly {
                        Picker("Day", selection: $recurringWeekday) {
                            ForEach(1...7, id: \.self) { day in
                                Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                            }
                        }
                    }

                    if recurringPattern == .monthly {
                        Picker("Day of month", selection: $recurringDayOfMonth) {
                            ForEach(1...31, id: \.self) { day in
                                Text(addTaskSheetOrdinalFormatter.string(from: NSNumber(value: day)) ?? "\(day)").tag(day)
                            }
                        }
                    }
                } header: {
                    Text("Recurrence")
                } footer: {
                    Text("Recurring tasks reset automatically after completion.")
                }

                if enableTaskDates {
                    Section("Task Date") {
                        if taskDateEnabled {
                            DatePicker(
                                "Task Date",
                                selection: Binding(
                                    get: { selectedTaskDate ?? minimumTaskDate },
                                    set: { selectedTaskDate = $0.startOfDay }
                                ),
                                in: minimumTaskDate...,
                                displayedComponents: .date
                            )

                            Button("Remove Task Date", role: .destructive) {
                                taskDateEnabled = false
                                selectedTaskDate = nil
                            }
                        } else {
                            Button("Add Task Date") {
                                taskDateEnabled = true
                                selectedTaskDate = (existingTask?.taskDate ?? minimumTaskDate).startOfDay
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Task" : "New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .disabled(trimmedTitle.isEmpty)
                }
            }
        }
        .presentationDetents(sheetDetents)
        .sheet(isPresented: $showImportInfo) {
            ImportInstructionsSheet()
        }
        .sheet(isPresented: $showPasteSheet) {
            PasteTasksSheet()
        }
        .onAppear(perform: loadExistingState)
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var builtRecurringRule: RecurringRule? {
        switch recurringPattern {
        case .weekly:  return .weekly(weekday: recurringWeekday)
        case .monthly: return .monthly(dayOfMonth: recurringDayOfMonth)
        case .none:    return nil
        }
    }

    private var normalizedTaskDate: Date? {
        guard enableTaskDates, taskDateEnabled else { return nil }
        return selectedTaskDate?.startOfDay
    }

    private var sheetDetents: Set<PresentationDetent> {
        if recurringPattern != nil || (enableTaskDates && taskDateEnabled) {
            return [.medium]
        }

        return [.height(isEditing ? 300 : 340)]
    }

    private func loadExistingState() {
        guard let existing = existingTask else { return }
        title = existing.title
        if let rule = existing.recurringRule {
            recurringPattern = rule.pattern
            if let wd = rule.weekday { recurringWeekday = wd }
            if let d = rule.dayOfMonth { recurringDayOfMonth = d }
        }
        if let taskDate = existing.taskDate {
            taskDateEnabled = true
            selectedTaskDate = taskDate.startOfDay
        }
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        if let task = existingTask {
            task.title = trimmedTitle
            task.recurringRule = builtRecurringRule
            task.taskDate = normalizedTaskDate
            try? modelContext.save()
        } else {
            let startOrder = PlannerEngine.topInsertionStartOrder(existingTasks: allTasks, count: 1)
            let task = JDTask(title: trimmedTitle, sortOrder: startOrder)
            task.recurringRule = builtRecurringRule
            task.taskDate = normalizedTaskDate
            modelContext.insert(task)
            try? modelContext.save()
            onCreated?(task)
        }
        dismiss()
    }
}

// MARK: - Import Instructions Sheet

/// Shown when a premium user taps "Import from .txt or .csv".
/// Explains the file format requirements, then opens the system file picker.
struct ImportInstructionsSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \JDTask.sortOrder) private var allTasks: [JDTask]

    @State private var showFileImporter = false
    @State private var importOutcome: ImportOutcome? = nil

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {

                VStack(alignment: .leading, spacing: 18) {
                    ImportFormatBlock(title: "Plain text (.txt)", bullets: [
                        "One task title per line",
                        "Blank lines are skipped",
                    ])
                    ImportFormatBlock(title: "Spreadsheet (.csv)", bullets: [
                        "Task title in the first column",
                        "All other columns are ignored",
                        "Quoted fields are supported",
                    ])
                    Label(
                        "Tasks already in your backlog are skipped automatically.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                Button {
                    showFileImporter = true
                } label: {
                    Label("Choose File", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle("Import Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.plainText, .commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result: result)
        }
        .alert(
            "Import Complete",
            isPresented: Binding(
                get: { importOutcome != nil },
                set: { if !$0 { importOutcome = nil } }
            )
        ) {
            Button("Done") {
                importOutcome = nil
                dismiss()
            }
        } message: {
            if let r = importOutcome {
                if r.imported == 0 {
                    Text("No new tasks found — all items were already in your backlog.")
                } else if r.skipped > 0 {
                    Text("\(r.imported) task\(r.imported == 1 ? "" : "s") added. \(r.skipped) skipped — already in your backlog.")
                } else {
                    Text("\(r.imported) task\(r.imported == 1 ? "" : "s") added to your backlog.")
                }
            }
        }
    }

    // MARK: Import logic

    private func handleImport(result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }

        let isCSV = url.pathExtension.lowercased() == "csv"
        let lines = content.components(separatedBy: .newlines)
        let existingTitles = Set(allTasks.map { $0.title.trimmingCharacters(in: .whitespaces).lowercased() })
        let startSortOrder = PlannerEngine.topInsertionStartOrder(existingTasks: allTasks, count: lines.count)

        var imported = 0
        var skipped = 0

        for line in lines {
            let raw = isCSV ? firstCSVField(from: line) : line
            let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            guard !existingTitles.contains(title.lowercased()) else { skipped += 1; continue }
            modelContext.insert(JDTask(title: title, sortOrder: startSortOrder + imported))
            imported += 1
        }

        try? modelContext.save()
        importOutcome = ImportOutcome(imported: imported, skipped: skipped)
    }

    /// Extracts the first field from a CSV line, handling quoted values.
    private func firstCSVField(from line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("\"") {
            let inner = trimmed.dropFirst()
            if let end = inner.firstIndex(of: "\"") { return String(inner[inner.startIndex..<end]) }
            return String(inner)
        }
        return trimmed.components(separatedBy: ",").first ?? trimmed
    }
}

// MARK: - Private helpers

private struct ImportOutcome {
    let imported: Int
    let skipped: Int
}

private struct ImportFormatBlock: View {
    let title: String
    let bullets: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.bold())
            ForEach(bullets, id: \.self) { bullet in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 4))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    Text(bullet)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    AddTaskSheet()
        .modelContainer(previewContainer)
}
