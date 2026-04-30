# Camera OCR Import — Design

**Date:** 2026-04-30

## Overview

Add camera and photo-library OCR options to the backlog import flow. The user photographs a handwritten or printed list, recognized lines are pre-filled into the existing Paste Tasks review sheet, and the user edits before confirming.

## UI / Entry Point

The Import menu in `BacklogView` gains two new items below a visual separator:

```
Paste Tasks          (existing)
Import File          (existing)
──────────────────
Scan with Camera     (new)
Import from Photos   (new)
```

Both new options funnel into the same OCR engine and review flow.

## OCR Engine

A new `TaskOCREngine` struct takes a `UIImage` and returns `[String]`:

- Uses `VNRecognizeTextRequest` with `.accurate` recognition level and language correction enabled
- Results sorted top-to-bottom by bounding box Y position (natural reading order)
- Output trimmed; empty lines and single-character fragments dropped

## Image Sources

- **Scan with Camera** — `UIImagePickerController` with `sourceType: .camera`
- **Import from Photos** — `PHPickerViewController` (no permission prompt required; system picker handles access)

Both sources feed the selected image into the same `TaskOCREngine` call.

## Review & Edit Flow

`PasteTasksSheet` gains an optional `initialText: String` parameter (default `""`). When OCR results are passed in, the sheet opens pre-filled with recognized lines joined by newlines — identical to the manual paste experience. The user can edit, delete, or add lines before tapping Add.

`BacklogView` stores `@State private var ocrInitialText = ""` and passes it when presenting the sheet.

## Permissions & Error Handling

- `NSCameraUsageDescription` added to `Info.plist`; iOS prompts on first camera use automatically
- Photo library picker requires no permission entry
- If OCR returns zero lines, the sheet opens empty with subtitle "Nothing recognized — try again or type tasks manually"
- No special partial-failure handling; Vision results are passed through as-is
