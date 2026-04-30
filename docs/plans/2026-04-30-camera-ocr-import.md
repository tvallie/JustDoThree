# Camera OCR Import Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add "Scan with Camera" and "Import from Photos" options to the backlog Import menu that run OCR and pre-fill the existing Paste Tasks review sheet.

**Architecture:** A new `TaskOCREngine` struct wraps `VNRecognizeTextRequest` at `.accurate` level and returns sorted, filtered lines. Two `UIViewControllerRepresentable` wrappers (`CameraPickerView`, `PhotoPickerView`) capture images. `BacklogView` orchestrates selection → OCR → pre-filled `PasteTasksSheet` via a `pendingOCRImage` state trigger. `PasteTasksSheet` gains an `initialText` parameter and an optional hint string.

**Tech Stack:** Swift, SwiftUI, Vision framework, VisionKit, PhotosUI, UIKit (UIImagePickerController, PHPickerViewController)

---

### Task 1: Add camera permission to Info.plist

**Files:**
- Modify: `JustDoThree/Info.plist`

**Step 1: Add NSCameraUsageDescription**

Open `JustDoThree/Info.plist` and add this key/value pair inside the root `<dict>`, after the existing `NSUserNotificationUsageDescription` entry:

```xml
<key>NSCameraUsageDescription</key>
<string>Just Do Three uses the camera to scan task lists.</string>
```

**Step 2: Build to confirm no errors**

Build the project (`Cmd+B`). Expected: build succeeds.

**Step 3: Commit**

```bash
git add JustDoThree/Info.plist
git commit -m "feat: add camera usage description to Info.plist"
```

---

### Task 2: Create TaskOCREngine

**Files:**
- Create: `JustDoThree/Engines/TaskOCREngine.swift`

**Step 1: Create the file**

```swift
import Vision
import UIKit

struct TaskOCREngine {
    static func recognizeLines(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                // Vision bounding boxes use bottom-left origin, so higher minY = higher on screen
                let lines = observations
                    .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
                    .compactMap { $0.topCandidates(1).first?.string }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.count > 1 }

                continuation.resume(returning: lines)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}
```

**Step 2: Build to confirm no errors**

Build (`Cmd+B`). Expected: build succeeds with no warnings on the new file.

**Step 3: Commit**

```bash
git add JustDoThree/Engines/TaskOCREngine.swift
git commit -m "feat: add TaskOCREngine using Vision accurate OCR"
```

---

### Task 3: Create CameraPickerView

**Files:**
- Create: `JustDoThree/Views/Shared/CameraPickerView.swift`

**Step 1: Create the file**

```swift
import SwiftUI
import UIKit

struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onImage: onImage)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        @Binding var isPresented: Bool
        let onImage: (UIImage) -> Void

        init(isPresented: Binding<Bool>, onImage: @escaping (UIImage) -> Void) {
            self._isPresented = isPresented
            self.onImage = onImage
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            isPresented = false
        }
    }
}
```

**Step 2: Build to confirm no errors**

Build (`Cmd+B`). Expected: build succeeds.

**Step 3: Commit**

```bash
git add JustDoThree/Views/Shared/CameraPickerView.swift
git commit -m "feat: add CameraPickerView UIViewControllerRepresentable"
```

---

### Task 4: Create PhotoPickerView

**Files:**
- Create: `JustDoThree/Views/Shared/PhotoPickerView.swift`

**Step 1: Create the file**

```swift
import SwiftUI
import PhotosUI
import UIKit

struct PhotoPickerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onImage: onImage)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        @Binding var isPresented: Bool
        let onImage: (UIImage) -> Void

        init(isPresented: Binding<Bool>, onImage: @escaping (UIImage) -> Void) {
            self._isPresented = isPresented
            self.onImage = onImage
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            isPresented = false
            guard let result = results.first else { return }
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                if let image = object as? UIImage {
                    DispatchQueue.main.async { self.onImage(image) }
                }
            }
        }
    }
}
```

**Step 2: Build to confirm no errors**

Build (`Cmd+B`). Expected: build succeeds.

**Step 3: Commit**

```bash
git add JustDoThree/Views/Shared/PhotoPickerView.swift
git commit -m "feat: add PhotoPickerView UIViewControllerRepresentable"
```

---

### Task 5: Update PasteTasksSheet to accept initialText

**Files:**
- Modify: `JustDoThree/Views/Backlog/PasteTasksSheet.swift`

**Step 1: Replace the existing @State text declaration and add an init**

The current file has:
```swift
@State private var text = ""
```

Replace the struct opening through the first `@State` line so it reads:

```swift
struct PasteTasksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JDTask.sortOrder) private var allTasks: [JDTask]

    @State private var text: String
    @State private var importResult: String? = nil
    @FocusState private var focused: Bool

    private let hint: String?

    init(initialText: String = "", hint: String? = nil) {
        self._text = State(initialValue: initialText)
        self.hint = hint
    }
```

**Step 2: Show the hint below the subtitle when present**

The existing subtitle `Text("Paste or type tasks below...")` is followed by padding. Add the hint below it:

```swift
Text("Paste or type tasks below, one per line.")
    .font(.subheadline)
    .foregroundStyle(.secondary)
    .padding(.horizontal)
    .padding(.top, 16)
    .padding(.bottom, hint == nil ? 8 : 2)

if let hint {
    Text(hint)
        .font(.caption)
        .foregroundStyle(.orange)
        .padding(.horizontal)
        .padding(.bottom, 8)
}
```

**Step 3: Build to confirm no errors**

Build (`Cmd+B`). Existing call sites pass no arguments so default `initialText: ""` keeps them working.

**Step 4: Commit**

```bash
git add JustDoThree/Views/Backlog/PasteTasksSheet.swift
git commit -m "feat: add initialText and hint parameters to PasteTasksSheet"
```

---

### Task 6: Wire up BacklogView

**Files:**
- Modify: `JustDoThree/Views/Backlog/BacklogView.swift`

**Step 1: Add new state variables**

After the existing `@State private var showPasteSheet = false` line, add:

```swift
@State private var showCameraPicker = false
@State private var showPhotoPicker = false
@State private var pendingOCRImage: UIImage? = nil
@State private var isProcessingOCR = false
@State private var ocrInitialText = ""
@State private var ocrHint: String? = nil
```

**Step 2: Add two new menu items to the Import menu**

The existing Import menu `label` block contains two `Button` items. Add a `Divider()` and two new buttons after the existing "Import File" button:

```swift
Divider()
Button {
    showCameraPicker = true
} label: {
    Label("Scan with Camera", systemImage: "camera")
}
Button {
    showPhotoPicker = true
} label: {
    Label("Import from Photos", systemImage: "photo")
}
```

**Step 3: Add OCR processing overlay**

At the end of the `Group { ... }` block (after the `List` / empty state), add an overlay that shows a spinner while OCR runs. Add this modifier to the `Group`:

```swift
.overlay {
    if isProcessingOCR {
        ZStack {
            Color(.systemBackground).opacity(0.6)
            ProgressView("Scanning…")
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
```

**Step 4: Add .task modifier for OCR processing**

Add this modifier to the root `NavigationStack` (alongside the existing `.sheet`, `.alert` modifiers):

```swift
.task(id: pendingOCRImage?.hashValue) {
    guard let image = pendingOCRImage else { return }
    isProcessingOCR = true
    let lines = await TaskOCREngine.recognizeLines(in: image)
    ocrInitialText = lines.joined(separator: "\n")
    ocrHint = lines.isEmpty ? "Nothing recognized — try again or type tasks manually." : nil
    pendingOCRImage = nil
    isProcessingOCR = false
    showPasteSheet = true
}
```

**Step 5: Update PasteTasksSheet presentation to pass OCR text**

Find the existing sheet:
```swift
.sheet(isPresented: $showPasteSheet) {
    PasteTasksSheet()
}
```

Replace it with:
```swift
.sheet(isPresented: $showPasteSheet, onDismiss: {
    ocrInitialText = ""
    ocrHint = nil
}) {
    PasteTasksSheet(initialText: ocrInitialText, hint: ocrHint)
}
```

**Step 6: Add camera and photo picker sheets**

Add these two sheet modifiers alongside the others:

```swift
.sheet(isPresented: $showCameraPicker) {
    CameraPickerView(isPresented: $showCameraPicker) { image in
        pendingOCRImage = image
    }
}
.sheet(isPresented: $showPhotoPicker) {
    PhotoPickerView(isPresented: $showPhotoPicker) { image in
        pendingOCRImage = image
    }
}
```

**Step 7: Build to confirm no errors**

Build (`Cmd+B`). Expected: build succeeds with no warnings.

**Step 8: Manual test — camera path**

Run on a physical device (camera doesn't work in Simulator):
1. Open Backlog → tap Import menu → tap "Scan with Camera"
2. iOS prompts for camera permission — grant it
3. Point camera at a printed or handwritten list → capture
4. Spinner appears briefly → Paste Tasks sheet opens pre-filled with recognized lines
5. Edit if needed → tap Add → tasks appear in backlog

**Step 9: Manual test — photo library path**

Run on device or Simulator:
1. Open Backlog → tap Import → tap "Import from Photos"
2. System photo picker appears — select a photo of a list
3. Spinner → Paste Tasks sheet opens pre-filled
4. Tap Add → tasks appear

**Step 10: Manual test — empty OCR result**

Select a photo with no readable text (e.g. a landscape photo):
- Sheet opens empty with orange hint: "Nothing recognized — try again or type tasks manually."

**Step 11: Confirm existing Paste Tasks and Import File still work**

Tap each existing option and verify unchanged behavior.

**Step 12: Commit**

```bash
git add JustDoThree/Views/Backlog/BacklogView.swift
git commit -m "feat: add Scan with Camera and Import from Photos to backlog import"
```
