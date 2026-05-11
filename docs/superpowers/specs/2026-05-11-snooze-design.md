# Snooze (Spec A)

**Status:** Approved design, awaiting implementation plan.
**Date:** 2026-05-11

## Summary

First-class "snooze" for notes. A snoozed note disappears from every list, count, and Focus view until its `snoozedUntil` time passes; on wake it surfaces briefly on the home dashboard as a "Back to your attention" chip. Schema impact is one optional field on `Note`.

## Motivation

Today the only way to get a note out of view is to archive, complete, or cancel it — all of which carry semantic weight. There's no clean affordance for *"this is still real, but not now"*. Focus mode in particular needs this: a small triage gesture to dismiss something for the rest of the day without losing it.

## Schema change

Add to `Note`:

```swift
var snoozedUntil: Date?
```

- Optional, default `nil` — CloudKit-safe per the existing constraints in CLAUDE.md.
- Mutating it does **not** bump `modifiedDate` (snooze is meta-state, not content). Side-effect: a long-snoozed note remains eligible for auto-archive based on its real last edit, which is correct.
- `Services/SchemaSeeder.swift` `seed(into:)` must set `snoozedUntil` on the seeded `Note` so the field registers in CloudKit Development before the schema is promoted to Production.

No new model types, no new relationships, no enum changes.

## Snooze action surface

Three points of entry, native idioms per platform:

| Surface | macOS | iOS |
|---|---|---|
| Note row | Right-click → Snooze submenu | Trailing-edge swipe → "Snooze" (`moon.zzz`) |
| Inspector | "Snooze" row showing current state + button | Same |

The inspector control shows:
- When not snoozed: a "Snooze…" button.
- When snoozed: "Snoozed until {relative date}" + a "Wake now" button.

## Picker presets (time-aware)

The picker shows the following presets, hiding any that are in the past or nonsensical relative to "now":

- **This evening** (today 18:00) — only shown before 17:00
- **Tomorrow morning** (08:00)
- **Tomorrow evening** (18:00)
- **This weekend** (next Saturday 09:00) — only shown Mon–Thu
- **Next week** (next Monday 09:00)
- **Next month** (1st of next month 09:00)
- **Pick a date…** — opens a native `DatePicker`

Implementation note: encapsulate preset generation in a small pure helper (`SnoozePresets.options(for now: Date) -> [SnoozeOption]`) so it's unit-testable without UI.

## Visibility rules

By default, a note where `snoozedUntil != nil && snoozedUntil > now` is hidden from:

- All folder lists, All Notes, tag-scoped lists.
- Focus mode (regardless of pin / priority / due date — snooze beats pin in focus).
- Home dashboard counts: `urgent`, `dueToday`, `overdue` predicates each gain a `(snoozedUntil == nil || snoozedUntil <= .now)` clause.

The single place snoozed notes are visible is the **Snoozed sidebar pseudo-folder**:

- New `SidebarSelection` case: `.snoozed`. New `NoteListScope` case: `.snoozed`.
- Sidebar entry sits **between All Notes and Folders**, only when `count(snoozed) > 0`. Disappears when empty.
- List sorted by `snoozedUntil` ascending (next to wake at top).
- Each row shows a moon icon and a "Wakes in 2h" / "Wakes Mon 9am" subtitle.
- Context menu / inspector offers "Wake now" (clears `snoozedUntil`) or re-snooze.

## Wake behaviour

A note "wakes" purely by `snoozedUntil <= now`. The field is **not cleared** on wake — it stays as a tombstone enabling the chips below. No new MaintenanceService work is required.

### "Back to your attention" chips on home dashboard

- Definition: notes where `snoozedUntil != nil && snoozedUntil <= now && snoozedUntil > now - 24h`.
- Rendered as a second chip row below the existing `updateNotes` chips in `HomeScreenView.hero`, with eyebrow label **"Back to your attention"**.
- Reuses `UpdateChip` with a small moon prefix dot to distinguish from urgent / due-today chips.
- Tapping a chip opens the note (existing chip behaviour).

## MaintenanceService changes

- `rescheduleOverdue` predicate gains `(snoozedUntil == nil || snoozedUntil <= .now)` — don't push due dates forward while a note is hidden.
- `archiveInactive` predicate gains the same clause — snoozed notes are deferred, not stale.

## Edge cases

| Case | Behaviour |
|---|---|
| Snoozed note becomes overdue while asleep | On wake, appears as overdue. Correct — user explicitly deferred past its own due date. |
| Pinned + snoozed | Hidden everywhere; pin preserved and effective again on wake. |
| Locked + snoozed | Orthogonal; row in Snoozed list shows title only (consistent with locked-note display). |
| Editing in the Snoozed list | Does **not** auto-wake. Wake is always explicit. |
| Recurring + snoozed | No interaction; recurrence advances `dueDate` independently of snooze. |

## Files affected (rough)

- `Models/Note.swift` — add `snoozedUntil`.
- `Models/AppSelection.swift` — add `.snoozed` cases to `SidebarSelection` and `NoteListScope`.
- `Services/SchemaSeeder.swift` — set `snoozedUntil` on seeded note.
- `Services/MaintenanceService.swift` — add snooze clauses to predicates.
- `Views/Sidebar/*` — render "Snoozed" entry conditionally.
- `Views/NoteList/NoteListView.swift` (and friends) — handle `.snoozed` scope; exclude snoozed from other scopes; show "Wakes …" subtitle in `.snoozed` scope; exclude from focus filter.
- `Views/NoteList/NoteRow.swift` — moon icon + relative subtitle in `.snoozed` scope.
- `Views/Editor/TodoInspector.swift` — Snooze row + picker entry point.
- New: `Views/Editor/SnoozePicker.swift` (or similar) — picker view (Menu on Mac, sheet on iOS).
- New: `Models/SnoozePresets.swift` — pure preset-generation helper.
- Mac context menu on rows — Snooze submenu.
- iOS swipe action on rows — Snooze trailing swipe.
- `Views/Home/HomeScreenView.swift` — exclude snoozed from urgent / dueToday / overdue; add "Back to your attention" chip section.

## Out of scope (deliberate)

- Notifications when a note wakes — separate spec.
- Per-`TodoItem` snooze.
- Rule-based snooze ("always snooze emails until 5pm").

## Testing notes

- `SnoozePresets.options(for:)` — easy to unit-test against fixed clock values (covers the Mon–Thu / pre-17:00 conditions).
- Schema deploy procedure: build Debug → Debug → Seed CloudKit Schema → wait for "Export CONFIRMED" alert → CloudKit Console → Deploy Dev → Prod → verify `CD_snoozedUntil` appears on `CD_Note`. Then Debug → Remove Schema Seed Records.
- No automated UI tests today; manual verification on Mac + iOS Simulator before merge.
