# JDT at Work — Design Doc

**Date:** 2026-05-01
**Status:** Approved

## Overview

"JDT at Work" is an opt-in feature that separates work and personal tasks into independent contexts, each with their own backlog, daily plans, and 3-task limits. When disabled, the app is visually and functionally identical to its current state.

## Goals

- Keep JDT simple — no visible complexity until the feature is enabled
- Allow users to maintain fully independent work and personal task systems
- Remember the last-used context across app launches

## Data Model Changes

### `JDTask`
- Add `var isWork: Bool = false`
- Tasks are tagged at creation time based on the active context
- Existing tasks default to `false` (personal) via SwiftData's default value — no migration needed

### `DailyPlan`
- Add `var isWork: Bool = false`
- Each calendar day can have up to two plans: one personal (`isWork: false`), one work (`isWork: true`)
- `PlannerEngine.fetchOrCreateTodayPlan` gains an `isWork: Bool` parameter
- Existing plans default to `false` (personal)

### `AppState`
- Add `workModeEnabled: Bool` — persisted to `UserDefaults` key `jdt_workModeEnabled`
  - Controls whether the feature is visible anywhere in the app
- Add `activeContext: Bool` — persisted to `UserDefaults` key `jdt_activeContext`
  - `false` = Personal, `true` = Work
  - Remembered across app launches
  - Resets to `false` when `workModeEnabled` is turned off

## Settings

A new toggle in the **Features** section of Settings:

> **JDT at Work**
> *Separate your work and personal tasks with independent daily plans.*

When turned **off**: all context UI is hidden, `activeContext` resets to personal, app behaves exactly as before.

When turned **on**: a `Personal | Work` segmented control appears in the nav bar of Today, Backlog, and Plan tabs.

## UI: Context Switcher

- A `Segmented Picker` (`Personal | Work`) in the navigation bar of Today, Backlog, and Plan
- Only visible when `workModeEnabled` is `true`
- All three tabs reflect the same global `activeContext` — switching in one tab switches all
- State persists to UserDefaults via `AppState.activeContext`

## Today Tab

- Fetches/creates the `DailyPlan` matching `activeContext` for today
- Each context has independent: 3-task limit, stretch goals, completion state, and celebration
- Rollover runs per context independently (see Rollover below)

## Backlog Tab

- Filters `JDTask` by `isWork` matching `activeContext`
- New tasks created in work context get `isWork = true`; personal context gets `isWork = false`
- Drag-to-reorder is scoped to the active context

## Plan Tab (Calendar)

- Filters `DailyPlan` records by `isWork` matching `activeContext`
- Tapping a day to view or add tasks is scoped to the active context

## Rollover

- Rollover runs independently per context
- Personal rollover triggers on app open (existing behavior, scoped to personal plans)
- Work rollover triggers when the user first switches to Work context that day (if not yet resolved)
- Each context tracks its own `jdt_rolloverResolved` key:
  - `jdt_rolloverResolved_personal`
  - `jdt_rolloverResolved_work`

## History Tab

- No changes — History remains a combined view across both contexts

## Out of Scope

- Per-task manual context switching after creation
- More than two contexts (YAGNI)
- Separate History views per context
