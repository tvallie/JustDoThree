import SwiftUI
import SwiftData

struct PasteTasksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JDTask.sortOrder) private var allTasks: [JDTask]

    @State private var text = ""
    @State private var importResult: String? = nil
    @FocusState private var focused: Bool

    private var nonBlankLines: [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Paste or type tasks below, one per line.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                TextEditor(text: $text)
                    .focused($focused)
                    .padding(.horizontal, 8)

                if !nonBlankLines.isEmpty {
                    Text("\(nonBlankLines.count) task\(nonBlankLines.count == 1 ? "" : "s") ready to add")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                }
            }
            .navigationTitle("Paste Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { importLines() }
                        .disabled(nonBlankLines.isEmpty)
                }
            }
        }
        .onAppear { focused = true }
        .alert("Import Complete", isPresented: Binding(
            get: { importResult != nil },
            set: { if !$0 { importResult = nil } }
        )) {
            Button("OK") { dismiss() }
        } message: {
            Text(importResult ?? "")
        }
    }

    private func importLines() {
        let existingTitles = Set(allTasks.map { $0.title.trimmingCharacters(in: .whitespaces).lowercased() })
        let nextSortOrder = (allTasks.map(\.sortOrder).max() ?? -1) + 1

        var imported = 0
        var skipped = 0

        for title in nonBlankLines {
            guard !existingTitles.contains(title.lowercased()) else {
                skipped += 1
                continue
            }
            modelContext.insert(JDTask(title: title, sortOrder: nextSortOrder + imported))
            imported += 1
        }

        try? modelContext.save()

        if imported == 0 {
            importResult = "No new tasks found. All items were already in your backlog."
        } else if skipped > 0 {
            importResult = "\(imported) task\(imported == 1 ? "" : "s") added. \(skipped) skipped — already in your backlog."
        } else {
            importResult = "\(imported) task\(imported == 1 ? "" : "s") added to your backlog."
        }
    }
}

#Preview {
    PasteTasksSheet()
        .modelContainer(previewContainer)
}
