import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BacklogView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \JDTask.sortOrder) private var allTasks: [JDTask]
    @Query(sort: \DailyPlan.date) private var plans: [DailyPlan]

    @State private var showAddSheet = false
    @State private var editingTask: JDTask? = nil
    @State private var showDeleteConfirm: JDTask? = nil
    @State private var showFileImporter = false
    @State private var showPasteSheet = false
    @State private var importResult: ImportResult? = nil

    private var todayTaskIDs: Set<UUID> {
        let plan = plans.first { $0.date.isSameDay(as: Date()) }
        return Set((plan?.taskIDs ?? []) + (plan?.stretchTaskIDs ?? []))
    }

    private var backlogTasks: [JDTask] {
        allTasks.filter { ($0.recurringRule != nil || !$0.isCompleted) && !todayTaskIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if backlogTasks.isEmpty {
                    EmptyStateView(
                        icon: "tray",
                        title: "Your backlog is clear",
                        message: "Add tasks here to pick from them each day.",
                        actionTitle: "Add a Task",
                        action: { showAddSheet = true }
                    )
                } else {
                    List {
                        ForEach(backlogTasks) { task in
                            BacklogRow(
                                task: task,
                                onEdit: { editingTask = task },
                                onDelete: { showDeleteConfirm = task }
                            )
                            // Suppress the system delete circles — we have our own button
                            .deleteDisabled(true)
                        }
                        .onMove(perform: move)
                    }
                    .listStyle(.plain)
                    // Always in edit mode so drag handles are live without tapping EditButton
                    .environment(\.editMode, .constant(.active))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Menu {
                        Button {
                            showPasteSheet = true
                        } label: {
                            Label("Paste Tasks", systemImage: "doc.on.clipboard")
                        }
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Import File", systemImage: "doc.badge.plus")
                        }
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        showAddSheet = true
                    } label: {
                        Label("Add Task", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        AppLogoView(size: 26)
                        Text("Just Do Three")
                            .font(.headline)
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddTaskSheet()
        }
        .sheet(isPresented: $showPasteSheet) {
            PasteTasksSheet()
        }
        .sheet(item: $editingTask) { task in
            AddTaskSheet(existingTask: task)
        }
        .confirmationDialog(
            "Delete \"\(showDeleteConfirm?.title ?? "")\"?",
            isPresented: Binding(
                get: { showDeleteConfirm != nil },
                set: { if !$0 { showDeleteConfirm = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Task", role: .destructive) {
                if let task = showDeleteConfirm { delete(task) }
            }
            Button("Cancel", role: .cancel) { showDeleteConfirm = nil }
        } message: {
            Text("This can't be undone.")
        }
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
                get: { importResult != nil },
                set: { if !$0 { importResult = nil } }
            )
        ) {
            Button("OK") { importResult = nil }
        } message: {
            if let r = importResult {
                if r.imported == 0 {
                    Text("No new tasks found. All items were already in your backlog.")
                } else if r.skipped > 0 {
                    Text("\(r.imported) task\(r.imported == 1 ? "" : "s") added. \(r.skipped) skipped — already in your backlog.")
                } else {
                    Text("\(r.imported) task\(r.imported == 1 ? "" : "s") added to your backlog.")
                }
            }
        }
    }

    // MARK: - List actions

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = backlogTasks
        reordered.move(fromOffsets: source, toOffset: destination)
        for (i, task) in reordered.enumerated() { task.sortOrder = i }
        try? modelContext.save()
    }

    private func delete(_ task: JDTask) {
        modelContext.delete(task)
        try? modelContext.save()
        showDeleteConfirm = nil
    }

    // MARK: - File import

    private func handleImport(result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }

        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }

        let isCSV = url.pathExtension.lowercased() == "csv"
        let lines = content.components(separatedBy: .newlines)

        // Build a set of existing titles for fast duplicate detection (case-insensitive)
        let existingTitles = Set(allTasks.map { $0.title.trimmingCharacters(in: .whitespaces).lowercased() })
        let nextSortOrder = (allTasks.map(\.sortOrder).max() ?? -1) + 1

        var imported = 0
        var skipped = 0

        for line in lines {
            let raw = isCSV ? firstCSVField(from: line) : line
            let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !title.isEmpty else { continue }
            guard !existingTitles.contains(title.lowercased()) else {
                skipped += 1
                continue
            }

            let task = JDTask(title: title, sortOrder: nextSortOrder + imported)
            modelContext.insert(task)
            imported += 1
        }

        try? modelContext.save()
        importResult = ImportResult(imported: imported, skipped: skipped)
    }

    /// Extracts the first field from a CSV line, handling quoted values.
    private func firstCSVField(from line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if trimmed.hasPrefix("\"") {
            // Quoted field — find the closing quote
            let inner = trimmed.dropFirst()
            if let end = inner.firstIndex(of: "\"") {
                return String(inner[inner.startIndex..<end])
            }
            // Malformed quoted field — return everything after the opening quote
            return String(inner)
        }

        // Unquoted field — take everything up to the first comma
        return trimmed.components(separatedBy: ",").first ?? trimmed
    }
}

// MARK: - Import result model

private struct ImportResult {
    let imported: Int
    let skipped: Int
}

// MARK: - BacklogRow

struct BacklogRow: View {
    let task: JDTask
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Tap the text area to edit
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        Text(task.createdDate.monthDayString)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        if task.rolloverCount > 0 {
                            Label("\(task.rolloverCount) rollover\(task.rolloverCount == 1 ? "" : "s")",
                                  systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                        }
                        if let rule = task.recurringRule {
                            Label("recurring · \(rule.displayString)", systemImage: "repeat")
                                .font(.caption)
                                .foregroundStyle(.teal)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            // Visible delete button — tap to confirm delete
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.callout)
                    .foregroundStyle(.red.opacity(0.6))
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    BacklogView()
        .modelContainer(previewContainer)
}
