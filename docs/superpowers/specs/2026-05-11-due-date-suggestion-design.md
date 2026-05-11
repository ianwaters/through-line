# Smart due-date suggestion (Spec C)

**Status:** Approved design, awaiting implementation plan.
**Date:** 2026-05-11

## Summary

When a note's title or body mentions a date ("send Bob the proposal by Friday"), surface a one-tap "Suggested due date" row in `TodoInspector` that sets `Note.dueDate`. Powered by `NSDataDetector` — instant, deterministic, no AI dependency. No schema change.

## Motivation

`dueDate` is a structured field but the natural way to capture intent is in prose. Users write "by Friday" or "due Nov 14" in a note body without manually filling the inspector. A passive suggestion turns that prose into structured data with one tap — no nag if you didn't mean it, and no work if you did.

## Detection

- **Mechanism:** `NSDataDetector` with the `.date` checking type.
- **Why not AI:** the data-detector vocabulary (relative phrases, day names, dates, "tomorrow", "next Tuesday at 5pm") covers virtually everything users write in notes, runs instantly, is deterministic, and works regardless of Apple Intelligence availability.
- **Scope:** title and body markdown — concatenated with a space separator before detection. Todo-item text is **out of scope** (too noisy; checklists routinely mention dates that aren't the parent note's due date).
- **Filtering:**
  - Drop any detected dates in the past (`< startOfToday`).
  - Drop ambiguous detector results where `duration > 0` and the start is in the past (e.g., "May 2025–Jan 2026" range).
  - If multiple future dates remain, take the **earliest**.
- **Suppression conditions:**
  - `Note.dueDate != nil` — suggestion is hidden entirely (user already chose).
  - User dismissed the current suggestion this editing session (transient state — re-typing the date later re-suggests).

## Trigger / lifecycle

- Run on `onChange` of `note.title` or `note.bodyMarkdown`, debounced **800 ms** (matches the existing editor save debounce rhythm).
- Detection runs on the main actor — fast enough for the typical note size that no off-actor work is needed. If profiling shows otherwise, move to a `Task.detached`.
- Result stored in a `@State var suggestedDueDate: Date?` on `NoteEditorContent` and passed into `TodoInspector` as a binding-like value (or via an environment value if cleaner).

## UI surface

Inspector row inside `TodoInspector`, positioned **directly above the existing Due Date row** so the suggestion sits next to where the canonical field lives.

Behaviour:

- **Hidden** when `suggestedDueDate == nil` or `note.dueDate != nil`.
- **When visible**, the row shows:
  - Eyebrow / label: "Suggested"
  - The detected date formatted as a friendly absolute string ("Fri 14 Nov" or "Tue 18 Nov, 5pm" if a time is present).
  - A primary "Set" button that assigns `note.dueDate = suggestedDueDate` and bumps `note.modifiedDate`.
  - A small dismiss control (an `xmark.circle`) that clears the transient state for this session.

Styling matches the inspector's existing dueDate row — same row chrome, slightly muted eyebrow.

## Files affected (rough)

- `Views/Editor/NoteEditorView.swift` — add the `@State` + the 800ms debounced detection task; pass result into `TodoInspector`.
- `Views/Editor/TodoInspector.swift` — add the "Suggested" row above the Due Date row; "Set" + dismiss actions.
- New: `Services/DateDetectionService.swift` — small wrapper around `NSDataDetector` with the filtering rules. Pure, testable.

## Schema

**No changes.**

## Edge cases

| Case | Behaviour |
|---|---|
| Body says "Friday", today is Friday | Detector resolves to today; suggestion shows "Today" — user can still set it. |
| Body says "Friday" but `dueDate` already Friday | Suggestion is hidden (dueDate already set). |
| Multiple dates in body ("call Bob Friday, meeting Tuesday") | Earliest future is shown ("Friday"). |
| User edits body to remove the date phrase | Next debounce returns nil; suggestion row disappears. |
| Note has todo items mentioning dates, body doesn't | No suggestion (todo-item text is out of scope). |
| Date with explicit time ("Friday at 5pm") | Suggestion preserves the time when setting `dueDate`. |

## Out of scope (deliberate)

- AI-based detection or fallback.
- Suggesting multiple dates simultaneously.
- Detecting dates in todo-item text.
- Auto-applying without a tap.
- Suggesting **recurrence** ("every Monday").
- Editing the suggested date inline before setting.

## Testing notes

- `DateDetectionService.detect(in:relativeTo:)` is the testable unit. Cases to cover:
  - "by Friday" relative to a Tuesday → next Friday.
  - "in 3 days" → today + 3 days.
  - "yesterday" → nil (past).
  - "Nov 14, 2025" with reference date 2026 → nil (past).
  - "Friday and Tuesday" → returns Friday (earlier).
- Manual verification: typing a date in the editor surfaces the suggestion within ~1s; tapping "Set" assigns it; clearing the date in the body removes the suggestion within ~1s.
