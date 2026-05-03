# CSV Export Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a "Export Tasks" button to Settings that opens a half-sheet letting the user pick context (Personal / Work / Both) and optional CSV columns (Date, Context, Recurring), then shares the file via the iOS share sheet.

**Architecture:** A new `ExportTasksSheet` view fetches all `JDTask` records via `@Query`, filters by the selected context, builds a CSV string in-memory, writes it to a temp file, and presents it with SwiftUI's `ShareLink`. `SettingsView` gains a "Data" section with a button that presents the sheet. No new engine or service is needed.

**Tech Stack:** Swift, SwiftUI, SwiftData (`@Query`), `FileManager` (temp file), `ShareLink`

**Design doc:** `docs/plans/2026-05-03-csv-export-design.md`

---

### Task 1: Create ExportTasksSheet

**Files:**
- Create: `JustDoThree/Views/Settings/ExportTasksSheet.swift`

**Step 1: Create the file**

```swift
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
```

**Step 2: Regenerate Xcode project**

```bash
xcodegen generate
```

**Step 3: Build verify**

```bash
xcodebuild -project JustDoThree.xcodeproj -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add JustDoThree/Views/Settings/ExportTasksSheet.swift JustDoThree.xcodeproj/project.pbxproj
git commit -m "feat: add ExportTasksSheet for CSV task export"
```

---

### Task 2: Wire ExportTasksSheet into SettingsView

**Files:**
- Modify: `JustDoThree/Views/Settings/SettingsView.swift`

**Step 1: Add presentation state**

After the line `@AppStorage("jdt_enableTaskDates") private var enableTaskDates = false`, add:

```swift
@State private var showExportSheet = false
```

**Step 2: Add a "Data" section**

Inside `Form { … }`, before the `// MARK: - About` section, add:

```swift
// MARK: - Data
Section {
    Button {
        showExportSheet = true
    } label: {
        Label("Export Tasks", systemImage: "arrow.up.doc")
    }
} header: {
    Text("Data")
}
```

**Step 3: Present the sheet**

After the closing `}` of `Form { … }.navigationTitle("Settings")`, and before the closing `}` of `NavigationStack { … }`, add:

```swift
.sheet(isPresented: $showExportSheet) {
    ExportTasksSheet()
}
```

The modifier goes on `Form`, alongside the existing `.navigationTitle`. Concretely, add it after `.navigationTitle("Settings")`:

```swift
.navigationTitle("Settings")
.sheet(isPresented: $showExportSheet) {
    ExportTasksSheet()
}
```

**Step 4: Build verify**

```bash
xcodebuild -project JustDoThree.xcodeproj -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

**Step 5: Commit**

```bash
git add JustDoThree/Views/Settings/SettingsView.swift
git commit -m "feat: add 'Export Tasks' entry point to Settings"
```

---

### Task 3: Smoke test

**Manual checks (run in simulator):**

- Settings → "Data" section → "Export Tasks" button visible.
- Sheet opens at `.medium` detent with correct controls.
- Work Mode disabled: no context picker; Context toggle hidden.
- Work Mode enabled: context picker shows Personal / Work / Both.
- Selecting Personal/Work: Context toggle disappears.
- Selecting Both: Context toggle appears.
- Tap "Export CSV" → iOS share sheet opens; file named `jdt-tasks-YYYY-MM-DD.csv`.
- Save to Files and open — header row matches selected columns; data rows correct.
- Tasks with commas in their title are properly quoted.
- Recurring tasks show readable string (e.g. `every Monday`); non-recurring tasks have empty Recurring cell.
