# Tomorrow Setup home section (Spec B)

**Status:** Approved design, awaiting implementation plan.
**Date:** 2026-05-11

## Summary

Add a new "Tomorrow" section to `HomeScreenView` that appears in the evening (≥ 18:00 local) and previews tomorrow's calendar events plus tomorrow's due notes, with a one-line AI summary. Sits below today's events, above the homepage note. Coexists with — does not replace — the existing today-focused hero, so any late-evening events still due today remain visible above-the-fold.

## Motivation

Several users (the project owner included) work with international colleagues whose meetings land late in the evening, so the home dashboard needs to keep showing today's remaining items right up until midnight. At the same time, by 6pm "today" mostly mentally belongs to "wrapping up", and a glance at tomorrow turns the home screen into a useful end-of-day check-in. A passive preview — no action required, no notifications — gives the personal-assistant feel without nagging.

## Trigger

- Hard-coded threshold: section is rendered iff `Calendar.current.component(.hour, from: .now) >= 18`.
- Configurable trigger time is **out of scope** for this spec; revisit if user feedback asks for it.

## Section content

In order, top to bottom:

1. **AI sentence** — one-line preview of tomorrow ("You have 3 meetings and 2 things due tomorrow, starting at 8am with the Sydney standup.").
2. **Tomorrow's calendar events** — sorted by start time. Same row chrome as `EventsTodaySection`.
3. **Tomorrow's due notes** — predicate:
   `todoEnabled && status ∉ {done, cancelled} && dueDate falls in tomorrow && (snoozedUntil == nil || snoozedUntil <= .now)`.
   Sorted by priority desc, then title asc. Tap opens the note via the existing `onOpenNote` callback.

## Empty-state behaviour

- If both events and due notes are empty for tomorrow → **section is not rendered**. No "Tomorrow's clear" placeholder; the dashboard stays focused on what matters now.
- If `calendarEventsEnabled` is off but tomorrow has due notes → section still renders (no events rows). The AI sentence reflects only what's available.

## Layout

- Inserted between `EventsTodaySection` and `homepageSection` in `HomeScreenView.body`.
- Same card chrome as `EventsTodaySection`: rounded rect, hairline border, `Color.secondary.opacity(0.06)` fill.
- Eyebrow header: **"Tomorrow"**, with right-aligned italic detail like `"Wednesday · 3 events, 2 due"`.
- Reuses existing `EventRow` for events; new `TomorrowDueRow` view for due notes (title + priority dot, no time column).

## CalendarEventsService changes

- Widen the EventKit predicate window from `[startOfToday, startOfTomorrow)` to `[startOfToday, startOfDayAfterTomorrow)` — one extra day.
- Add `tomorrowEvents: [CalendarEventViewModel]` partitioned at access time:
  - One EventKit fetch produces both arrays.
  - `events` keeps the existing semantics (today only, future / all-day filter).
  - `tomorrowEvents` filtering: events whose `startDate` falls in `[startOfTomorrow, startOfDayAfterTomorrow)`.
- Same calendar-IDs & authorization gates apply.
- Refresh cooldown unchanged (30s).

## IntelligenceService changes

Add `tomorrowSummary(_ input: TomorrowSummaryInput, hash: Int) async -> String?`.

```swift
struct TomorrowSummaryInput {
    let weekdayNoun: String                 // "Wednesday"
    let eventCount: Int
    let firstEventTime: String?             // "8am"
    let firstEventTitle: String?
    let dueCount: Int
    let urgentDueCount: Int
}
```

Prompt shape is similar to `generateDailySummary` but framed in future tense and second-person modal:
- "You're previewing tomorrow for the user."
- "Maximum 24 words. Friendly, no emoji, no exclamation marks."
- "If the day looks busy, set expectations briefly. If quiet, say so."
- "Use future / modal verbs ('You'll have', 'You can')."
- "Don't assert what the user is feeling. Don't reference today."

Caching mirrors today's summary:
- New private state: `cachedTomorrowSummary: (hash: Int, text: String)?` and `tomorrowSummaryTask: (hash: Int, task: Task<String?, Never>)?`.
- Same 8-second wall-clock timeout race.
- Hash includes tomorrow-event IDs, due-note count, urgent-due count, and the current hour (so the summary regenerates roughly hourly through the evening as new context lands).

## New view: `TomorrowSection.swift`

- Mirrors `EventsTodaySection` structure (eyebrow + card with rows).
- Reuses `EventRow`.
- New `TomorrowDueRow` for due notes — title + priority-coloured dot + tap to open.
- AI sentence uses the existing `ComposingSummaryLine` placeholder while loading; falls back to a rule-based sentence if AI is unavailable (e.g., "Tomorrow brings 3 events and 2 due items.").

## HomeScreenView wiring

- Add `private var tomorrowDueNotes: [Note]` computed off `activeNotes` with the predicate above.
- Add `private var showTomorrowSection: Bool = (now hour >= 18) && (!tomorrowEvents.isEmpty || !tomorrowDueNotes.isEmpty)`.
- Insert `TomorrowSection(...)` between `EventsTodaySection` and `homepageSection`, gated on `showTomorrowSection`.

## Schema

**No changes.** Reuses the snooze field added in Spec A.

## Files affected (rough)

- `Services/CalendarEventsService.swift` — widen fetch window; add `tomorrowEvents`.
- `Services/IntelligenceService.swift` — add `TomorrowSummaryInput`, `tomorrowSummary(...)`, separate cache slot.
- New: `Views/Home/TomorrowSection.swift` (and `TomorrowDueRow`).
- `Views/Home/HomeScreenView.swift` — `tomorrowDueNotes`, `showTomorrowSection`, render the new section in the right slot.

## Out of scope (deliberate)

- User-configurable trigger time.
- More than 1 day ahead (no "this week" preview).
- Push notifications about tomorrow's items.
- Merging today + tomorrow into a single "next 24h" view.
- Per-event drill-down differences from `EventsTodaySection`.

## Testing notes

- Trigger threshold easy to test with an injected clock; the section's pure visibility logic should be a small function fed `(now: Date, tomorrowEvents: [...], tomorrowDueNotes: [...])`.
- AI prompt unit-testable indirectly via `TomorrowSummaryInput` shape; manual verification of the produced text on Mac (Foundation Models eligible).
- Manual cross-device check: at 17:55 nothing renders; at 18:00 the section appears.
