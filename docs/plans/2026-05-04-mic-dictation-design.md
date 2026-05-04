# Mic Dictation on Task Input — Design

Date: 2026-05-04

## Goal

Add a visible mic affordance to single-task input fields so users discover dictation and can speak a task without bringing up the keyboard.

## Scope

In scope:
- `AddTaskSheet` (`JustDoThree/Views/Shared/AddTaskSheet.swift:43`) — modal single-task add.
- TodayView inline add row (`JustDoThree/Views/Today/TodayView.swift:646`) — "Type a new task…" field.

Out of scope:
- `PasteTasksSheet` (bulk multi-line input).
- Multi-task splitting from a single dictation.
- Locale picker; use the device default.
- Voice commands ("save", "cancel").
- Punctuation commands beyond what `SFSpeechRecognizer` provides natively.

## Behavior

1. Mic icon (SF Symbol `mic`) sits inside the trailing edge of the text field.
2. First tap: request `SFSpeechRecognizer.requestAuthorization` and `AVAudioSession.requestRecordPermission`.
3. Recording starts immediately; the system keyboard is not invoked. The field is non-editable while recording.
4. Live transcript streams into the field via partial results.
5. While active, the mic icon pulses and tints red. Tap again to stop. Auto-stop after ~1.5s of detected silence.
6. On stop: transcript stays in the field; focus moves to the Save / submit button so the user can confirm with one tap.
7. Permission denied: one-time alert with a Settings deep link, then the mic hides for the session.
8. Mid-recording error (recognizer unavailable, audio session interrupted): revert to idle, show inline error text below the field.

## Architecture

### `SpeechDictationController` (new, `ObservableObject`)

Wraps `SFSpeechRecognizer` + `AVAudioEngine`. Owns:
- Auth state: `notDetermined | authorized | denied | restricted`.
- Recording state: `idle | recording | stopping | error(message)`.
- Published partial transcript.
- Silence-detection timer (~1.5s).

Recognizer config:
- `recognitionRequest.shouldReportPartialResults = true`.
- `recognitionRequest.requiresOnDeviceRecognition = true` when `recognizer.supportsOnDeviceRecognition` is true, otherwise fall back.

State machine: `idle → requestingAuth → recording → stopped` with denied/error branches. Protocol-wrap the recognizer for testability.

### `MicButton` (new SwiftUI view)

- Inputs: `Binding<String>` for target text, `FocusState` binding for post-stop focus shift, owned `@StateObject` controller.
- Renders mic / mic.fill swap, pulse animation while recording.
- Handles tap → start/stop, permission alert presentation.

### Integration

- `AddTaskSheet`: add `MicButton` as a trailing accessory on the title `TextField`. On stop, shift focus to the Save button.
- TodayView inline row: add `MicButton` next to the existing field. On stop, shift focus to the row's add/submit control.

### Configuration

- Info.plist: `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`.

## Testing

Unit:
- Controller state-machine transitions across all paths (auth granted/denied, start, partial result, silence auto-stop, manual stop, error).
- Use a protocol-wrapped recognizer fake; do not exercise real audio in unit tests.

Manual matrix:
- First-launch permission prompt (both permissions).
- Permission denial path; verify Settings deep link and session hiding.
- Airplane mode (forces on-device or fallback path).
- Background → foreground transition mid-recording.
- Switching fields / dismissing sheet while recording (must stop cleanly).
- Auto-stop on silence; manual stop via second tap.
- Save-button focus shift on both surfaces.
