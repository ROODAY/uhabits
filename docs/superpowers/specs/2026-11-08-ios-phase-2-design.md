# iOS port, phase 2 (organize + settings): design

Date: 2026-11-08
Status: Draft, pending approval
Parent spec: `docs/superpowers/specs/2026-11-06-ios-port-design.md` (the "parent"). Its anti-goals, constraints, process/lock model (§6.3) and reminder model (§6.4) all still apply. Handoff state: `docs/superpowers/2026-11-07-ios-handoff.md`.

## 1. Intent

Phase 1 gave her the daily drivers. Phase 2 gives her the tools for organizing habits and the settings that Android Loop has: categories, archive, reorder, sort, filter, search, skip and "?" marks, a settings screen, and dark mode.

**The owner's rule for this phase: match the Android experience, with iPhone-style interactions.** Android has a feature, so iOS has it, with the same behavior and defaults. Only the gestures and controls change to what an iPhone user expects. If a builder isn't sure how something should behave, the answer is "what Android does". They should check the Android code (`uhabits-android/.../activities/habits/list/**`, `ListHabitsMenuBehavior`, `ListHabitsSelectionMenuBehavior`, `preferences.xml`) and use it.

**Change to the parent's delivery plan:** the parent said each phase ends with a TestFlight build. The owner has no Mac handy, so phases 2, 3 and 4 are all coded first. TestFlight, the on-phone checks and fixing come after phase 4. Phase 2 is "done" when CI is green and the CI screenshots look right. Nothing in phase 2 should make that later on-device round harder (see §7).

## 2. Goals

1. **Categories.** Category headers appear in the list, with uncategorized habits first and then categories A to Z (the core's existing sort). The edit screen has a Category field that suggests existing categories. A habit's long-press menu and Select mode can set the category. Long-press a header to rename the category, or clear it to remove it (`RenameCategoryCommand`). The detail screen shows the category.
2. **Archive and unarchive**, from the habit's long-press menu, from Select mode (several at once), and from the detail screen's menu.
3. **Manual reorder** by dragging in Select mode. A habit dropped under a different category header moves into that category (Android's drag-to-re-categorize, which is `ReorderHabitCommand` with a category).
4. **Sort**: manually, by name, by color, by score, or by status. Picking the current sort again reverses it (`ListHabitsMenuBehavior.onSortToggleBy`). Sorting by anything other than manual turns off drag-reorder, as on Android.
5. **Filter**: hide archived (default on), hide completed (default off). The choices are saved in the shared prefs (`showArchived`, `showCompleted`, `defaultPrimaryOrder`, `defaultSecondaryOrder`), using the same keys as Android.
6. **Search** by name, using the core's `HabitMatcher.searchQuery` rules. The query is not saved.
7. **Skip and "?" marks.** Long-press (or tap, see goal 8) on a yes/no check cell opens an entry sheet with Yes, No, and Skip and ? when those are enabled, plus notes. This matches Android's `CheckmarkDialog`. The number entry sheet gains Skip and ? the same way (Android's `NumberDialog`). Toggling a cell cycles through the core's `Entry.nextToggleValue`, which the facade already uses.
8. **Settings screen**, opened from a gear in the list toolbar:
   - Interface: Toggle with short press, Day ends at 3 AM (midnight delay), Enable skip days, Enable question marks, Reverse order of days, First day of the week.
   - Reminders: a "Notification settings" row that opens the iOS Settings page for the app.
   - Database: Export full backup, Export as CSV, Import data, shown disabled with "coming soon". Phase 4 turns them on.
   - About: app version and build, plus a link to the source repo (GPLv3).
   - Every value uses the core `Preferences` keys and defaults, **except** the short-press toggle (see C1).
9. **Dark mode** follows the system. Habit colors come from the facade's palette for the current scheme (`palette(dark:)`, already there). It must look right in both schemes in the CI screenshots.
10. **Settings take effect everywhere**: the list (day order, toggles, skip/?), the detail history grid, widgets, intents and reminders. For example, turning on midnight delay changes "today" and the reminder plan. After a settings change the app reschedules reminders and reloads widget timelines.

## 3. Non-goals

- Anything in phases 3 and 4 (charts, more widgets, export/import). The phase 4 rows are only placeholders.
- These Android settings: pure black (iOS dark mode already uses a black background, see C3), disable animations (iOS has no confetti), widget opacity, sticky notifications, reminder sound/customize (iOS Settings handles these), public backup folder, bug report, repair DB, rate app, developer/sync.
- An in-app light/dark override (Android's night-mode menu item). iOS follows the system (C4).
- Undo. Android has none for these actions either, only confirmations.
- Bulk "edit" of several habits. Android's selection menu only offers Edit when one habit is selected, so iOS does the same.

## 4. Anti-goals

From the parent, restated for this phase:
- **Swift doesn't decide list contents or order.** No sorting, filtering, grouping, search matching or "which category did this drop land in" logic in Swift. The facade returns the finished list and takes gesture results as plain arguments (§6.1).
- **Android doesn't change.** No changes to `uhabits-android`. Any `uhabits-core` change keeps Android's behavior identical and its tests green. The ideal is zero core changes.
- **The close-when-inactive rule holds.** All new DB access goes through `LoopStore` and respects `AppActivity.isForeground` / `closeStoreIfInactive`. Preferences live in the App Group `UserDefaults`, so the widget and intents see the same values.

## 5. Constraints

As in the parent: Windows-only development. Swift compiles only in CI (`ios` workflow). Kotlin facade tests run on the JVM on Windows. Kotlin 2.3.20, iOS 17 minimum, XcodeGen. Each Swift increment is built by CI before more Swift is stacked on it.

## 6. Design

### Approaches considered

| | Approach | Verdict |
|---|---|---|
| **A** | **The facade returns the finished, sectioned list; Swift renders it and reports gestures** | **Chosen by the owner.** All list rules are in Kotlin and tested on Windows. The only duplication is about 30 lines of Android adapter logic (header insertion, drop target), ported into the facade. |
| B | Move the Android adapter's grouping and drop logic into `uhabits-core` and share it | Rejected. It changes Android's adapter and screenshots for little gain, and "don't break Android" is an anti-goal. |
| C | The facade returns a flat sorted list, and Swift groups, filters and searches it | Rejected. It puts list rules in Swift, which can't be tested on Windows and breaks the parent's main anti-goal. |

### 6.1 Facade additions (`uhabits-ios-kit`)

The exact names and shapes are the builder's call. What the facade must provide:

- **List query.** The query returns a **flat list of rows, each either a category header or a habit**, mirroring Android's `HabitCardListAdapter` `Row.Category` / `Row.Habit` (see C7 for why flat). Something like `listRows(dayCount, searchQuery) → [ListRow]`. The facade reads the filter and sort settings from prefs, builds a `HabitMatcher` the way `ListHabitsMenuBehavior.updateAdapterFilter` does, and applies the primary and secondary order. The core's `MemoryHabitList` comparator already puts category first under **every** order. The facade inserts a header row exactly where `HabitCardListAdapter` does (lines ~114-119): before the first habit of each non-blank category. Blank-category habits come first and get no header.
- `HabitRow` gains `category` and keeps `isArchived`. Day cells keep coming back newest first. The facade reports whether the order is reversed, and Swift reverses only the display order (C2).
- **List settings**: get and set `showArchived`, `showCompleted`, and the sort. Sort is set as a choice (manual, name, color, score, status), and the facade applies Android's same-choice-reverses toggle. The facade reports the current sort so the menu can show a checkmark.
- **Habit actions**: `archive(ids)`, `unarchive(ids)`, `setCategory(ids, category)`, `setColor(ids, colorIndex)`, `renameCategory(old, new)` (empty `new` clears the category), each through the core command Android uses.
- **Reorder**: Swift reports a move as source and destination indices into the flat row list it was given, plus the habit id (or the row list's identity) so a stale list can be detected. The facade rebuilds the moved order and works out the drop result exactly as `HabitCardListAdapter` lines ~324-337 do. The result is `ReorderDragResult(id, relativeToId, below, targetCategory)`: the target category is the nearest header above the drop, or "" if there is none, and the reference is the habit above (after it) or below (before it). The facade then runs `ReorderHabitCommand`. Swift does no drop math. A header row itself can't be moved.
- **Categories list**: `categories() → [String]` (distinct, sorted like the list) for the edit-field suggestions and the category picker.
- **Entry values**: set a specific value on a yes/no entry (Yes, No, Skip, Unknown), keeping its notes, for the entry sheet. For measurable habits, set Skip or Unknown. This should go through the same command or behavior Android's `CheckmarkDialog` / `NumberDialog` path uses.
- **Preferences**: get and set short toggle, midnight delay, skip enabled, question marks enabled, reverse checkmark order, and first weekday (including "system default", Android's `-1`). These use the core `Preferences` keys (`pref_short_toggle`, `pref_midnight_delay`, `pref_skip_enabled`, `pref_unknown_enabled`, `pref_checkmark_reverse_order`, `pref_first_weekday`) over the existing `KeyValueStore`. The existing `midnightDelayHours()` and `areQuestionMarksEnabled()` stay or get folded in.
- **First weekday is habit logic, not only display.** The core's `EntryList` uses it for period starts (weekly/monthly frequencies), via `setFirstWeekday` in `platform/time/Dates.kt`. The facade must apply it the way Android does at startup and whenever the setting changes. It must also expose the resolved weekday (system default resolved through the core's `getFirstWeekdayNumberAccordingToLocale`) so Swift's `HistoryGrid.layout` and `ReminderPicker.displayOrder` use it instead of `Calendar.current.firstWeekday`. The grid layout stays in Swift (it's presentation). The builder should check in a CI simulator test that the iOS locale actual agrees with `Calendar.current.firstWeekday`.
- **Detail**: `HabitDetail` gains category.
- `HabitInput` gains `category`, so create and edit can set it.
- Every new method has `@Throws(Exception::class)` and jvmTests. That includes tests that sorting, filtering, grouping and drop results match what Android's adapter and behaviors produce for the same data, and that prefs round-trip through the same keys Android reads.

### 6.2 SwiftUI

The mockups from the brainstorm are in `.superpowers/brainstorm/` (local, not committed). The layout:

- **List toolbar**: "Select" (leading); gear (Settings), ☰ menu, + (trailing). A search field (`.searchable`). The ☰ menu holds Hide archived and Hide completed toggles and a Sort submenu with a checkmark on the current choice.
- **One `List` with one `ForEach` over the facade's flat rows.** Category headers are styled rows inside it, not SwiftUI `Section`s (C7), so `.onMove` can drop a habit under another header. Long-press a header row to get a Rename alert (an empty name removes the category, with no confirmation, as on Android). Uncategorized habits have no header. `.moveDisabled(true)` on header rows.
- **Confirmations match Android**: only Delete asks (single and bulk). Archive, unarchive, category changes and clearing a category don't.
- **Habit row long-press** opens a context menu: Edit, Color, Category…, Reminder… (opens edit), Archive or Unarchive, Delete. This replaces Android's single-selection action bar. The long-press goes on the name area. Long-pressing a check cell keeps its own meaning (goal 7).
- **Select mode** (`EditMode`): rows show selection circles and drag handles. A bottom bar has Color, Category, Archive or Unarchive, and Delete. Drag-reorder is enabled only when the sort is manual **and the search field is empty** (C8). The drop is reported to the facade as in §6.1, and then the list reloads from the facade.
- **Check cells**: if short toggle is on, a tap toggles and a long-press opens the entry sheet. If it's off, the two swap. Measurable cells open the number sheet on tap as today. Archived habits shown via "hide archived" off look dimmed, like Android. Existing Skip and ? entries keep showing as skip and ? even after those settings are turned off, as on Android, and tapping them follows `nextToggleValue` with no special case in Swift.
- **Reverse order of days** applies to the list's day columns and their header only, as on Android (`ButtonPanelView`, `Header`). It doesn't apply to the detail grid or widgets.
- **Entry sheet** for yes/no: Yes, No, Skip (if enabled), ? (if enabled), and notes. It replaces today's notes-only sheet. The number sheet gains Skip and ? buttons when enabled.
- **Settings screen** as in goal 8, a SwiftUI `Form`.
- **Edit screen** gets a Category text field with suggestions from `categories()`. **Detail screen** shows the category under the title, and its menu gets Archive or Unarchive.
- **Dark mode**: check all screens for hard-coded colors. Use system colors for chrome and facade palette colors for habits.

### 6.3 Widgets, intents, reminders

- The widget habit picker already excludes archived habits (`HabitEntity` lists with `includeArchived: false`). Keep it that way. A widget configured for a habit that later gets archived shows the habit as it does now, and the builder doesn't need to handle that case specially.
- Reminders already skip archived habits (facade `upcomingReminders`). Archive, unarchive, delete and settings changes trigger the existing reschedule path.
- The widget toggle intent cycles with skip and ? the same way the app does (it already calls `toggle`). Check this with a jvmTest on the prefs path.
- Settings are stored in the App Group `UserDefaults`, so the widget sees them on its next timeline.

## 7. Testing and verification

- **Kotlin (main safety net):** jvmTests for every facade addition (§6.1), written test-first. The core's JVM and JS tests and the Android build stay green (`android-core` workflow).
- **Swift:** XCTest for glue code only, such as mapping facade sort and pref values to menu state, the select-mode action dispatch, and drop-index mapping to the facade call arguments.
- **CI screenshots** to review visually: the list with categories (light and dark), the ☰ menu open, a row context menu, Select mode, the entry sheet with Skip and ?, Settings, and the edit screen with the category field. The demo seed (`DemoSeed.swift`) gets categories, an archived habit and some skip and ? entries so these screens show real content.
- **Add to the on-device checklist for the later TestFlight round** (put it in the handoff doc): drag-reorder across categories feels right; the context menu and the check-cell long-press don't conflict; the settings link opens iOS Settings; dark mode on her phone.

## 8. Calls made (the owner can override)

- **C1. "Toggle with short press" defaults to ON on iOS**, unlike Android's off. Phase 1 shipped tap-to-toggle, and it's what an iPhone user expects. The facade supplies this default when the key is unset. It can't be done by changing the core default, because that would change Android.
- **C2. Reverse day order** is applied by Swift as display order only, on the list screen only (as on Android). The facade says whether to reverse it. This is presentation, not habit logic.
- **C3. Pure black dropped.** I showed it in the settings mockup, but iOS dark mode backgrounds are already black, so on iOS the toggle would do nothing visible.
- **C4. No in-app theme switch.** It follows the system, per the parent spec.
- **C5. The context menu's "Reminder…" opens the edit screen** scrolled to the reminder section (or just the edit screen), rather than a separate reminder dialog.
- **C6. Phase 4 rows appear disabled** in Settings now, so the layout is final.
- **C7. Flat list, not sections.** SwiftUI's `.onMove` can't move a row between `Section`s, and Android's drag-to-re-categorize needs exactly that. A flat list of header and habit rows is also exactly Android's adapter model, so the drop rules port one-for-one. A UIKit table wrapper was rejected: it's more Swift that can only be checked in CI.
- **C8. No drag while searching.** With a filtered list, the "habit above/below" a drop isn't the real neighbour, so the move would land somewhere surprising.
- **C9. Short toggle only affects the app's check cells.** Widgets and intents always toggle on tap, as now. Settings shows the switch ON when the key is unset (C1). Prefs written by the app are seen by other processes on their next fresh `LoopKit`. The app already rebuilds on foreground (`reload()`), so the cached `Preferences` values aren't a staleness risk.

## 9. Left to the builder

- Exact facade API names, DTO shapes, and how sections are encoded for Swift
- How SwiftUI drag-reorder indices map to the facade's reorder arguments (tested)
- The order of tasks, keeping each Swift step small enough to compile in CI before the next
- Exact visual styling within "native iPhone look, Loop palette for habits"
