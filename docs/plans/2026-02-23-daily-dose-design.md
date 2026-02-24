# Daily Dose — Design Document
Date: 2026-02-23

## Overview

Replace the endless sequential task queue with a "Daily Dose" system. Users see only a curated batch of tasks for TODAY, computed by distributing all remaining tasks evenly across working days until move day. When the day's batch is done, a celebration screen appears. Users can optionally get ahead by viewing the next day's batch.

## Architecture

The existing 4-state machine (`loading → welcome → activeTask → done`) is preserved. No new states are added. The view reads a computed `dailyDoseViewState` enum to decide which card variant to render in the `.done` state.

## Files Changed

| File | Change |
|------|--------|
| `PeezyCard.swift` | Add `urgencyPercentage: Int?` field + initializer param |
| `PeezyHomeViewModel.swift` | Add Daily Dose algorithm, UserDefaults tracking, new computed properties, `getAhead()` method |
| `PeezyHomeView.swift` | Add progress UI to welcome card, daily celebration card, all-done card |

## Algorithm

```swift
let daysUntilMove = userState?.daysUntilMove ?? 30
let bufferDays = daysUntilMove <= 10 ? 0 : daysUntilMove <= 14 ? 3 : 7
let workingDays = max(daysUntilMove - bufferDays, 1)
let dailyTarget = Int(ceil(Double(allActiveTasks.count) / Double(workingDays)))
let todaysBatch = Array(allActiveTasks.prefix(dailyTarget))
```

## Sorting

Primary: `urgencyPercentage DESC` (higher urgency = earlier in queue)
Secondary: `title ASC` (alphabetical tiebreak for consistency)

## UserDefaults Keys

- `dailyDoseCompletedCount: Int` — tasks completed today, reset on new day
- `dailyDoseLastDate: String` — ISO date of last completion, used to detect new day
- `dailyDoseFirstLaunchDate: String` — set once, used for "Day X of Y" calculation

## UI States

**STATE 1 — Batch active (welcome card):**
- "Today: X of Y done" progress
- "Day X of Y · Z tasks remaining"
- "Get started" button → begins today's batch

**STATE 2 — Daily complete (done card, isTodayComplete && !gettingAhead):**
- "You're all done for today! 🎉"
- Encouraging subtext based on schedule position
- ConfettiView with .high intensity
- "Want to get ahead?" button → calls getAhead()

**STATE 3 — Getting ahead (done card after extra batch):**
- "You're X days ahead!" headline
- Confetti
- "Keep going?" button → calls getAhead() again

**STATE 4 — All tasks done (done card, allActiveTasks.isEmpty):**
- "You're all set! Your move is in X days and Peezy is handling the rest."
- "We're working on X things for you." (inProgressTaskCount)

## Firestore Query Change

Add `"InProgress"` to the existing status filter:
```swift
.whereField("status", in: ["Upcoming", "pending", "Snoozed", "InProgress"])
```
Tasks with `InProgress` status are counted in `inProgressTaskCount` and excluded from `allActiveTasks`.

## Getting Ahead

Tracked via `currentBatchOffset: Int`. Each call to `getAhead()` increments offset and loads:
```swift
Array(allActiveTasks.dropFirst(dailyTarget * currentBatchOffset).prefix(dailyTarget))
```
If that slice is empty, nothing more to show — transition to STATE 4.

## What the Card Stack Shows — Before/After

**Before:** `taskQueue` = ALL active tasks (all upcoming/snoozed tasks sorted by dueDate + priority)

**After:** `taskQueue` = only `todaysBatch` (top N tasks by urgencyPercentage, where N = dailyTarget)

Getting ahead repopulates `taskQueue` with the next N tasks after today's batch.

## Greeting Card

The existing `.welcome` state serves as the greeting card. It appears before every batch. Does not count toward `dailyDoseCompletedCount`.

## Timeline View

Unaffected. Daily dose only controls what `taskQueue` (home card stack) contains.
