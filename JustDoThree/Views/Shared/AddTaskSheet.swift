import SwiftUI
import SwiftData

/// Sheet for creating a new task or editing an existing task title.
struct AddTaskSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Pass nil to create a new task; pass an existing task to edit its title.
    var existingTask: JDTask? = nil

    /// Called after a new task is successfully created.
    var onCreated: ((JDTask) -> Void)? = nil

    @State private var title: String = ""
    @Query(sort: \JDTask.sortOrder) private var allTasks: [JDTask]

    var isEditing: Bool { existingTask != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What do you need to do?", text: $title, axis: .vertical)
                        .lineLimit(1...4)
                        .onAppear {
                            if let existing = existingTask { title = existing.title }
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
        .presentationDetents([.height(200)])
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        if let task = existingTask {
            task.title = trimmedTitle
            try? modelContext.save()
        } else {
            let nextOrder = (allTasks.map(\.sortOrder).max() ?? -1) + 1
            let task = JDTask(title: trimmedTitle, sortOrder: nextOrder)
            modelContext.insert(task)
            try? modelContext.save()
            onCreated?(task)
        }
        dismiss()
    }
}

#Preview {
    AddTaskSheet()
        .modelContainer(previewContainer)
}
