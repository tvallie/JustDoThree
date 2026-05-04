# Mic Dictation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a visible mic affordance to the two single-task input fields (`AddTaskSheet`, TodayView inline add row) that records via `SFSpeechRecognizer`, streams a live transcript into the field, and on stop shifts focus to the Save / Add button.

**Architecture:** A new `SpeechDictationController` (ObservableObject) wraps `SFSpeechRecognizer` + `AVAudioEngine`, exposes a small state machine (`idle | requesting | recording | error`) and a published partial transcript. A new `MicButton` SwiftUI view drives the controller, owns its own pulse animation, and writes into a `Binding<String>`. Both target fields embed a `MicButton` as a trailing accessory. The recognizer is protocol-wrapped so the state machine can be unit-tested with a fake.

**Tech Stack:** SwiftUI, Swift 5.9, iOS 17, `Speech` framework (`SFSpeechRecognizer`), `AVFoundation` (`AVAudioEngine`, `AVAudioSession`), XCTest, xcodegen (`project.yml`).

**Background notes for the implementer:**
- Project uses `xcodegen` — `project.yml` is the source of truth. After editing it, regenerate the Xcode project with `xcodegen generate` from the repo root.
- Build via: `xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 15' build`
- Tests via: `xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 15' test`
- There is currently **no test target**. Task 1 adds one.
- The user's feedback memory says TDD is required for new logic and Co-Authored-By Claude lines must NOT appear in commit messages.
- Single-developer workflow: do **not** create a git worktree. Work on `main` or a feature branch.

---

### Task 1: Add a unit test target

**Files:**
- Modify: `project.yml` (add `JustDoThreeTests` target)
- Create: `JustDoThreeTests/SmokeTests.swift`

**Step 1: Add test target to `project.yml`**

Append to the `targets:` block (after the existing `JustDoThree:` target):

```yaml
  JustDoThreeTests:
    type: bundle.unit-test
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: JustDoThreeTests
    dependencies:
      - target: JustDoThree
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.todd.justdothree.tests
        DEVELOPMENT_TEAM: 3ZAS78KQUH
        SWIFT_VERSION: "5.9"
        TARGETED_DEVICE_FAMILY: "1"
        GENERATE_INFOPLIST_FILE: YES
```

Also extend the existing scheme's `test` block to include the new target:

```yaml
schemes:
  JustDoThree:
    build:
      targets:
        JustDoThree: all
        JustDoThreeTests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - JustDoThreeTests
    archive:
      config: Release
```

**Step 2: Create a smoke test file**

`JustDoThreeTests/SmokeTests.swift`:

```swift
import XCTest

final class SmokeTests: XCTestCase {
    func test_smoke() {
        XCTAssertEqual(1 + 1, 2)
    }
}
```

**Step 3: Regenerate the Xcode project**

Run: `xcodegen generate`
Expected: writes a new `JustDoThree.xcodeproj` with the test target included.

**Step 4: Run the test**

Run: `xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 15' test`
Expected: PASS (`** TEST SUCCEEDED **`).

**Step 5: Commit**

```bash
git add project.yml JustDoThree.xcodeproj JustDoThreeTests/SmokeTests.swift
git commit -m "chore: add JustDoThreeTests unit test target"
```

---

### Task 2: Define the `SpeechRecognizing` protocol and recognizer state types

**Files:**
- Create: `JustDoThree/Speech/SpeechRecognizing.swift`

**Step 1: Write the types (no test yet — pure type definitions)**

```swift
import Foundation

/// Auth state for combined microphone + speech-recognition permission.
enum SpeechAuthState: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

/// Recording lifecycle for the dictation controller.
enum DictationState: Equatable {
    case idle
    case requestingAuth
    case recording
    case error(String)
}

/// Abstraction over `SFSpeechRecognizer` + `AVAudioEngine` so the controller
/// can be unit-tested without touching real audio hardware.
protocol SpeechRecognizing: AnyObject {
    var isAvailable: Bool { get }
    var supportsOnDevice: Bool { get }

    func requestAuthorization(_ completion: @escaping (SpeechAuthState) -> Void)

    /// Starts recognition. `onPartial` is called with the running transcript.
    /// `onFinish` is called once when recognition stops (manually or via silence).
    /// `onError` is called if audio/recognizer fails mid-stream.
    func start(
        requireOnDevice: Bool,
        onPartial: @escaping (String) -> Void,
        onFinish: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    )

    func stop()
}
```

**Step 2: Build to confirm it compiles**

Run: `xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 15' build`
Expected: BUILD SUCCEEDED.

**Step 3: Commit**

```bash
git add JustDoThree/Speech/SpeechRecognizing.swift project.yml JustDoThree.xcodeproj
git commit -m "feat: add SpeechRecognizing protocol and dictation state types"
```

---

### Task 3: TDD — `SpeechDictationController` idle → recording transition on auth granted

**Files:**
- Create: `JustDoThree/Speech/SpeechDictationController.swift`
- Create: `JustDoThreeTests/SpeechDictationControllerTests.swift`
- Create: `JustDoThreeTests/Fakes/FakeSpeechRecognizer.swift`

**Step 1: Write the fake recognizer**

`JustDoThreeTests/Fakes/FakeSpeechRecognizer.swift`:

```swift
import Foundation
@testable import JustDoThree

final class FakeSpeechRecognizer: SpeechRecognizing {
    var isAvailable = true
    var supportsOnDevice = true

    var stubAuth: SpeechAuthState = .authorized
    var startCallCount = 0
    var stopCallCount = 0

    private var partialHandler: ((String) -> Void)?
    private var finishHandler: (() -> Void)?
    private var errorHandler: ((Error) -> Void)?

    func requestAuthorization(_ completion: @escaping (SpeechAuthState) -> Void) {
        completion(stubAuth)
    }

    func start(
        requireOnDevice: Bool,
        onPartial: @escaping (String) -> Void,
        onFinish: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        startCallCount += 1
        partialHandler = onPartial
        finishHandler = onFinish
        errorHandler = onError
    }

    func stop() {
        stopCallCount += 1
        finishHandler?()
    }

    // Test hooks
    func emitPartial(_ text: String) { partialHandler?(text) }
    func emitError(_ err: Error) { errorHandler?(err) }
}
```

**Step 2: Write the failing test**

`JustDoThreeTests/SpeechDictationControllerTests.swift`:

```swift
import XCTest
@testable import JustDoThree

@MainActor
final class SpeechDictationControllerTests: XCTestCase {
    func test_start_whenAuthorized_entersRecordingState() {
        let fake = FakeSpeechRecognizer()
        fake.stubAuth = .authorized
        let controller = SpeechDictationController(recognizer: fake)

        controller.start()

        XCTAssertEqual(controller.state, .recording)
        XCTAssertEqual(fake.startCallCount, 1)
    }
}
```

**Step 3: Run the test — verify it fails**

Run: `xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 15' test`
Expected: FAIL — `SpeechDictationController` does not exist.

**Step 4: Implement the minimum**

`JustDoThree/Speech/SpeechDictationController.swift`:

```swift
import Foundation
import Combine

@MainActor
final class SpeechDictationController: ObservableObject {
    @Published private(set) var state: DictationState = .idle
    @Published private(set) var transcript: String = ""

    private let recognizer: SpeechRecognizing

    init(recognizer: SpeechRecognizing) {
        self.recognizer = recognizer
    }

    func start() {
        state = .requestingAuth
        recognizer.requestAuthorization { [weak self] auth in
            Task { @MainActor in
                guard let self else { return }
                guard auth == .authorized else {
                    self.state = .error("Permission denied")
                    return
                }
                self.transcript = ""
                self.recognizer.start(
                    requireOnDevice: self.recognizer.supportsOnDevice,
                    onPartial: { [weak self] text in
                        Task { @MainActor in self?.transcript = text }
                    },
                    onFinish: { [weak self] in
                        Task { @MainActor in self?.state = .idle }
                    },
                    onError: { [weak self] err in
                        Task { @MainActor in self?.state = .error(err.localizedDescription) }
                    }
                )
                self.state = .recording
            }
        }
    }

    func stop() {
        recognizer.stop()
    }
}
```

**Step 5: Run the test — verify it passes**

Run: `xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 15' test`
Expected: PASS.

**Step 6: Commit**

```bash
git add JustDoThree/Speech/SpeechDictationController.swift JustDoThreeTests/
git commit -m "feat: add SpeechDictationController with auth-granted recording path"
```

---

### Task 4: TDD — denied auth path

**Files:**
- Modify: `JustDoThreeTests/SpeechDictationControllerTests.swift`

**Step 1: Add the failing test**

```swift
func test_start_whenDenied_entersErrorState_andDoesNotStartRecognizer() {
    let fake = FakeSpeechRecognizer()
    fake.stubAuth = .denied
    let controller = SpeechDictationController(recognizer: fake)

    controller.start()

    if case .error = controller.state {} else {
        XCTFail("Expected error state, got \(controller.state)")
    }
    XCTAssertEqual(fake.startCallCount, 0)
}
```

**Step 2: Run tests — verify it passes**

The implementation from Task 3 already handles this. Run:
`xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 15' test`
Expected: PASS.

**Step 3: Commit**

```bash
git add JustDoThreeTests/SpeechDictationControllerTests.swift
git commit -m "test: cover denied permission path in SpeechDictationController"
```

---

### Task 5: TDD — partial transcript publishing and stop transition

**Files:**
- Modify: `JustDoThreeTests/SpeechDictationControllerTests.swift`

**Step 1: Add failing tests**

```swift
func test_partialResults_updateTranscript() {
    let fake = FakeSpeechRecognizer()
    let controller = SpeechDictationController(recognizer: fake)
    controller.start()

    fake.emitPartial("buy")
    XCTAssertEqual(controller.transcript, "buy")

    fake.emitPartial("buy milk")
    XCTAssertEqual(controller.transcript, "buy milk")
}

func test_stop_returnsToIdle() {
    let fake = FakeSpeechRecognizer()
    let controller = SpeechDictationController(recognizer: fake)
    controller.start()
    XCTAssertEqual(controller.state, .recording)

    controller.stop()

    XCTAssertEqual(controller.state, .idle)
    XCTAssertEqual(fake.stopCallCount, 1)
}

func test_recognizerError_movesControllerToErrorState() {
    let fake = FakeSpeechRecognizer()
    let controller = SpeechDictationController(recognizer: fake)
    controller.start()

    fake.emitError(NSError(domain: "test", code: 1))

    if case .error = controller.state {} else {
        XCTFail("Expected error state, got \(controller.state)")
    }
}
```

**Step 2: Run — verify pass**

The fake's `emitPartial` / `stop` / `emitError` already drive the existing controller correctly. Run tests; expected PASS for all three.

If any fail because of `Task { @MainActor in ... }` scheduling, replace the `Task { @MainActor in ... }` blocks in `SpeechDictationController` with synchronous `MainActor.assumeIsolated { ... }` calls (the fake invokes its handlers synchronously on the test's main actor).

**Step 3: Commit**

```bash
git add JustDoThreeTests/SpeechDictationControllerTests.swift JustDoThree/Speech/SpeechDictationController.swift
git commit -m "test: cover transcript updates, stop, and recognizer error paths"
```

---

### Task 6: Implement the real `SFSpeechRecognizer` adapter

**Files:**
- Create: `JustDoThree/Speech/AppleSpeechRecognizer.swift`
- Modify: `JustDoThree/Info.plist`

**Step 1: Add Info.plist usage descriptions**

Edit `project.yml`'s existing `info.properties` block under target `JustDoThree` to add:

```yaml
        NSMicrophoneUsageDescription: "Just Do Three uses the microphone so you can dictate tasks instead of typing."
        NSSpeechRecognitionUsageDescription: "Just Do Three uses speech recognition to turn your dictation into task text."
```

Run `xcodegen generate` to propagate.

**Step 2: Implement the adapter**

`JustDoThree/Speech/AppleSpeechRecognizer.swift`:

```swift
import Foundation
import Speech
import AVFoundation

/// Production adapter wrapping `SFSpeechRecognizer` and `AVAudioEngine`.
final class AppleSpeechRecognizer: SpeechRecognizing {
    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?

    var isAvailable: Bool { recognizer?.isAvailable ?? false }
    var supportsOnDevice: Bool { recognizer?.supportsOnDeviceRecognition ?? false }

    func requestAuthorization(_ completion: @escaping (SpeechAuthState) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            AVAudioApplication.requestRecordPermission { micGranted in
                let mapped: SpeechAuthState
                switch (speechStatus, micGranted) {
                case (.authorized, true): mapped = .authorized
                case (.denied, _), (_, false): mapped = .denied
                case (.restricted, _): mapped = .restricted
                default: mapped = .notDetermined
                }
                DispatchQueue.main.async { completion(mapped) }
            }
        }
    }

    func start(
        requireOnDevice: Bool,
        onPartial: @escaping (String) -> Void,
        onFinish: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard let recognizer, recognizer.isAvailable else {
            onError(NSError(domain: "AppleSpeechRecognizer", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Speech recognition is unavailable."]))
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if requireOnDevice && recognizer.supportsOnDeviceRecognition {
                req.requiresOnDeviceRecognition = true
            }
            self.request = req

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                req.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            self.task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    onPartial(text)
                    self.resetSilenceTimer(onFinish: onFinish)
                }
                if let error {
                    self.cleanup()
                    onError(error)
                } else if result?.isFinal == true {
                    self.cleanup()
                    onFinish()
                }
            }
            resetSilenceTimer(onFinish: onFinish)
        } catch {
            cleanup()
            onError(error)
        }
    }

    func stop() {
        cleanup()
    }

    private func resetSilenceTimer(onFinish: @escaping () -> Void) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.cleanup()
            onFinish()
        }
    }

    private func cleanup() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
```

**Step 3: Build**

Run: `xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 15' build`
Expected: BUILD SUCCEEDED.

**Step 4: Commit**

```bash
git add JustDoThree/Speech/AppleSpeechRecognizer.swift project.yml JustDoThree.xcodeproj
git commit -m "feat: add SFSpeechRecognizer adapter with on-device preference"
```

---

### Task 7: Build the `MicButton` view

**Files:**
- Create: `JustDoThree/Views/Shared/MicButton.swift`

**Step 1: Implement**

```swift
import SwiftUI

/// Trailing-accessory mic button. Drives a `SpeechDictationController` and
/// writes the transcript into a bound string. Calls `onFinished` when
/// recording stops (manual or silence auto-stop) so the host view can
/// shift focus to a Save / Add button.
struct MicButton: View {
    @Binding var text: String
    var onFinished: () -> Void = {}

    @StateObject private var controller: SpeechDictationController
    @State private var pulse = false
    @State private var showPermissionAlert = false

    init(text: Binding<String>, onFinished: @escaping () -> Void = {}) {
        self._text = text
        self.onFinished = onFinished
        self._controller = StateObject(
            wrappedValue: SpeechDictationController(recognizer: AppleSpeechRecognizer())
        )
    }

    var body: some View {
        Button(action: tapped) {
            Image(systemName: isRecording ? "mic.fill" : "mic")
                .foregroundStyle(isRecording ? .red : .accentColor)
                .scaleEffect(pulse ? 1.15 : 1.0)
                .animation(
                    isRecording
                        ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                        : .default,
                    value: pulse
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop dictation" : "Start dictation")
        .onChange(of: controller.transcript) { _, new in
            if isRecording { text = new }
        }
        .onChange(of: controller.state) { _, new in
            switch new {
            case .recording:
                pulse = true
            case .idle:
                pulse = false
                onFinished()
            case .error(let msg):
                pulse = false
                if msg.contains("Permission") { showPermissionAlert = true }
            case .requestingAuth:
                break
            }
        }
        .alert("Microphone access needed",
               isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enable Microphone and Speech Recognition for Just Do Three to use dictation.")
        }
    }

    private var isRecording: Bool { controller.state == .recording }

    private func tapped() {
        if isRecording { controller.stop() } else { controller.start() }
    }
}
```

**Step 2: Build**

Run: `xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 15' build`
Expected: BUILD SUCCEEDED.

**Step 3: Commit**

```bash
git add JustDoThree/Views/Shared/MicButton.swift
git commit -m "feat: add MicButton view bound to SpeechDictationController"
```

---

### Task 8: Wire `MicButton` into `AddTaskSheet`

**Files:**
- Modify: `JustDoThree/Views/Shared/AddTaskSheet.swift:39-45` (the title section) and the toolbar Save button.

**Step 1: Add a `FocusState` for the Save button and embed the mic**

Replace the section block at line 41-45:

```swift
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        TextField("What do you need to do?", text: $title, axis: .vertical)
                            .lineLimit(1...4)
                            .focused($focus, equals: .title)
                        MicButton(text: $title) {
                            focus = .save
                        }
                        .padding(.top, 2)
                    }
                }
```

Add at top of the struct, near the other `@State` declarations:

```swift
    @FocusState private var focus: Field?
    private enum Field: Hashable { case title, save }
```

In the toolbar, attach focus to the Save button:

```swift
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .disabled(trimmedTitle.isEmpty)
                        .focused($focus, equals: .save)
                }
```

**Step 2: Build**

Run: `xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 15' build`
Expected: BUILD SUCCEEDED.

**Step 3: Manual smoke (real device or simulator with mic)**

- Open the app, tap "+ New Task".
- Tap the mic icon: first time, accept both permission prompts.
- Speak "buy milk". The transcript appears in the field. Stop on silence (~1.5s) — focus should move to the Save button.
- Tap mic, speak, then tap mic again to stop manually — focus should still move to Save.

**Step 4: Commit**

```bash
git add JustDoThree/Views/Shared/AddTaskSheet.swift
git commit -m "feat: add mic dictation to AddTaskSheet title field"
```

---

### Task 9: Wire `MicButton` into TodayView inline add row

**Files:**
- Modify: `JustDoThree/Views/Today/TodayView.swift:646-656`

**Step 1: Embed mic in the HStack**

Replace lines 641-657:

```swift
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.title3)

                        TextField("Type a new task…", text: $newTaskTitle)
                            .submitLabel(.done)
                            .focused($fieldFocused)
                            .onSubmit { createAndAdd() }

                        MicButton(text: $newTaskTitle) {
                            // No separate Save button here; just leave the text in
                            // the field — the inline "Add" appears once non-empty.
                            fieldFocused = false
                        }

                        if !trimmed.isEmpty {
                            Button("Add") { createAndAdd() }
                                .bold()
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.vertical, 4)
```

**Step 2: Build**

Run: `xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 15' build`
Expected: BUILD SUCCEEDED.

**Step 3: Manual smoke**

- Open TodayView's "Add to plan" inline row.
- Tap mic, speak a task, stop on silence. Transcript fills the field; the inline "Add" button appears. Tap it — task is added.

**Step 4: Commit**

```bash
git add JustDoThree/Views/Today/TodayView.swift
git commit -m "feat: add mic dictation to TodayView inline add row"
```

---

### Task 10: Manual test matrix and final cleanup

**Step 1: Run the manual matrix from the design doc**

Walk through each item in `docs/plans/2026-05-04-mic-dictation-design.md` under "Testing → Manual matrix":

- [ ] First-launch permission prompt (both mic and speech).
- [ ] Permission denial — alert appears with Settings deep link; mic stays inert for the session.
- [ ] Airplane mode — recording still works on devices that support on-device recognition; otherwise an inline error shows and mic returns to idle.
- [ ] Background → foreground mid-recording — the recording cleans up and returns to idle without a crash.
- [ ] Dismiss the AddTaskSheet while recording — no crash, audio session deactivates.
- [ ] Auto-stop on silence (~1.5s) and manual stop both work and both shift focus to Save (in AddTaskSheet).
- [ ] Mic icon pulses while active and reverts when stopped.

**Step 2: Run unit tests once more**

Run: `xcodebuild -scheme JustDoThree -destination 'platform=iOS Simulator,name=iPhone 15' test`
Expected: PASS.

**Step 3: Final commit if any tweaks were needed**

```bash
git status
# If anything changed during the manual matrix:
git add -p
git commit -m "fix: <describe tweak>"
```

---

## Out of scope (do not implement)

- Bulk dictation in `PasteTasksSheet`.
- Multi-task splitting from a single dictation.
- Locale picker (uses device default).
- Voice commands ("save", "cancel").
- Punctuation commands beyond what `SFSpeechRecognizer` already provides.
