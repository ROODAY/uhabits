# iOS Port of Loop Habit Tracker (fork) — Design

Date: 2026-11-06
Status: Draft, pending approval

## 1. Intent

This fork of Loop Habit Tracker (`uhabits`) only runs on Android. The owner
wants an iPhone version for one person, their girlfriend, installed through
TestFlight with the owner's Apple Developer Program account. It will not be
released on the App Store.

What matters most is that the app is **correct and not error-prone**. Habit
logic (streaks, scores, schedules, skips, targets) is subtle, and this fork
keeps fixing bugs in it, so that logic must exist in exactly one place. LLMs
will write and maintain the code, so the amount of code matters less than
correctness.

## 2. Goals, by phase

Phases ship in order. Each phase ends with a TestFlight build she can use.

**Phase 0: delivery pipeline (call C8)**
- Phase 0a, at the start, with no Apple account needed: an empty SwiftUI
  app shell plus the widget extension target, built and run on a simulator
  by `ios.yml`. Simulator builds need no signing. Kotlin core and facade
  work can start right away, in parallel.
- Phase 0b, at any point before phase 1 is done: `testflight.yml` delivers
  the current build to her phone. Doing it earlier surfaces signing
  problems sooner, but no work is blocked on it.
- Owner-side setup that 0b needs, done once (only the owner has access to
  the Apple account):
  1. Pick the bundle ID and App Group ID; register the App ID (with App
     Groups) and the App Group in the developer portal
  2. Create the app record in App Store Connect
  3. Create an App Store Connect API key (App Manager role) and add it,
     plus the team ID, as GitHub repo secrets
  4. Add her Apple ID as an internal TestFlight tester; she installs the
     TestFlight app
- The builder writes a step-by-step checklist for these steps
  (`ios/SETUP.md`) as the first task.

**Phase 1: her daily drivers**
- Habit list (main screen) with check-offs for the last few days
- Create and edit habits: name, color, schedule (frequency), reminder time
  and days, yes/no or measurable. Measurable habits are complete in
  phase 1: unit, target value, target type (at least / at most), the
  number entry dialog (call C9)
- **Check-off widget**: interactive (tap to mark done today) on the home
  screen; +/− for measurable habits
- **Reminders**: local notifications at the habit's reminder time on its
  reminder days, not shown when the habit is already done that day, with
  Done and Snooze actions
- **Streak viewing** on the habit detail screen
- Editing past days and notes, on the detail screen and from the list
- A Siri/Shortcuts "mark habit done" action, if it comes for free from the
  widget's App Intent (see §6.4)

**Phase 2: wanted early**
- Categories (recently added to this fork)
- Archive/unarchive, manual reorder, sort (manual, name, color, score,
  status), hide completed, hide archived, search
- Skip days and "?" (unknown) marks, per the existing preferences
- Settings: first day of week, midnight delay ("day ends later"), reversed
  checkmark order, skip enabled, question marks enabled
- Dark mode (system)

**Phase 3: charts and the remaining widgets**
- Detail screen cards: overview, history calendar grid, score over time,
  frequency by weekday, bar chart, target progress
- Widgets: history, score, frequency, streak, target (iOS sizes; §6.3)

**Phase 4: data**
- Full backup export (Loop `.db`) and CSV export, via the iOS share sheet /
  Files
- Import: Loop `.db` backups (including Android backups) and the other
  formats the core already supports (`GenericImporter`)

## 3. Non-goals

- App Store release
- iPad layouts beyond whatever SwiftUI gives by default
- Localization. English only for now (§10, call C3); the Android string
  translations are not ported
- Android-only features: sticky notifications, notification channel tuning,
  public backup folder, the Tasker plugin (`automation/`), rate app, bug
  report, developer sync server settings
- Android's stack widget (iOS Smart Stacks cover this natively)
- Sync between devices
- Matching Loop's look pixel for pixel. The app should feel like a native
  iPhone app, using Loop's palette colors

## 4. Anti-goals (failure even if it works)

- **Swift computing habit logic.** Swift renders values the Kotlin core
  returns and never computes streaks, scores, frequency adherence, which
  days are "done", reminder eligibility, or similar. If Swift needs a
  number, the Kotlin facade (§6.1) provides it.
- **Breaking Android.** The Android app's behavior and its tests must be
  unchanged. Every core change keeps the JVM and JS tests green, and the
  Android app still builds.
- **Large amounts of Swift that have never been compiled.** Swift is
  written in small increments, each built by CI (§7) before more is stacked
  on top.

## 5. Constraints

- **No Mac at the start.** Development happens on Windows. All compiling,
  testing and signing for iOS runs on GitHub Actions macOS runners. The fork
  (`ROODAY/uhabits`) is public, so standard runners are free. A Mac may come
  later; nothing should depend on one.
- **Apple Developer Program account**: available. Distribution is through
  TestFlight internal testing, so there is no App Review.
- **Minimum iOS version: 17**, which interactive widgets require. Her
  phone: iPhone 13, iOS 26.5.
- **Toolchain**: Kotlin 2.3.20 (from `gradle/libs.versions.toml`), JDK 17,
  Swift/SwiftUI with whatever Xcode the GitHub macOS image provides. The
  Xcode project is generated with **XcodeGen** from a checked-in
  `project.yml`. Hand-edited `.pbxproj` files are not allowed.
- **License**: GPLv3. Fine for personal TestFlight distribution. The iOS
  sources stay in this public fork under the same license.

## 6. Architecture (chosen approach: Kotlin core as an iOS framework, SwiftUI on top)

```
┌──────────────────────── iPhone ────────────────────────┐
│  App (SwiftUI)      Widget extension      Notification │
│      │             (SwiftUI + App Intents)  actions    │
│      └────────────┬──────────┴───────────────┘         │
│                   ▼                                    │
│         LoopKit.xcframework (Kotlin/Native)            │
│           Facade API → uhabits-core                    │
│                   ▼                                    │
│     App Group container: SQLite DB + shared prefs      │
└────────────────────────────────────────────────────────┘
```

### 6.1 Kotlin facade module (new)

New Gradle module **`uhabits-ios-kit`** (name is the builder's call). It is
Kotlin Multiplatform with targets `jvm` (so tests run on Windows) and
`iosArm64` + `iosSimulatorArm64`. It depends on `uhabits-core` and produces
the `LoopKit` XCFramework.

It exposes a small, **Swift-friendly** API:
- Plain immutable data classes (DTOs) built from Kotlin primitives,
  `String` and `List`. Not exposed to Swift: core model classes (`Habit`,
  `HabitList`, `EntryList`), generics beyond `List`, sealed hierarchies,
  `suspend` functions, Kotlin `Long` timestamps without a clear unit.
  Habit IDs are `Long`.
- Synchronous calls, run on one serial queue chosen by the Swift side
  (§6.5).
- Roughly these operations (the exact shape is the builder's call):
  - `open(dbPath, prefsStorage)` / `close()` / `reload()`
  - `listHabits(filter/sort options) → [HabitRow]`. Each row has name,
    color, type, archived, category, today's and the last N days' entry
    states and values, current score, and whether it's done today.
  - `habitDetail(id) → HabitDetail`: streaks (current, best, list), notes,
    and the data each chart needs (phase 3)
  - `setEntry(habitId, date, value, notes)`, `toggle(habitId, date)`,
    `increment` / `decrement`. These mirror `WidgetBehavior` and
    `ListHabitsBehavior`.
  - `createHabit(...)`, `editHabit(...)`, `archive`, `unarchive`,
    `delete`, `reorder`, `setCategory`, `renameCategory`
  - `upcomingReminders(now, horizonDays, maxCount) → [ReminderOccurrence]`
    (§6.4)
  - Preference getters and setters for the settings in phase 2
  - Phase 4: `exportDb(toPath)`, `exportCsv(toPath)`, `import(fromPath)`
- Every facade operation goes through the core's existing commands, models
  and behaviors (`CommandRunner`, `CreateRepetitionCommand`,
  `WidgetBehavior`, `ListHabitsBehavior`, `ScoreList`, `StreakList`, and so
  on), so undo-capable commands and listeners behave as on Android.
- **Tests**: the facade's tests live in its `commonTest`/`jvmTest` and run
  on the JVM with the same JDBC SQLite test setup the core uses. These
  tests are the main safety net, and they run on Windows.

Dependency injection: the core uses kotlin-inject. The facade can wire
objects by hand or with a kotlin-inject `@Component`. Builder's call.

### 6.2 `uhabits-core` changes

1. **Add iOS targets** (`iosArm64`, `iosSimulatorArm64`) next to the
   existing `jvm` and `js`. Known risk: `kotlin-inject-runtime` is
   `compileOnly` in `commonMain`, and Kotlin/Native may reject
   `compileOnly` dependencies. If it does, switching it to `implementation`
   is acceptable.
2. **New `iosMain` actuals and interface implementations.** The legacy
   implementations deleted in `3330014f` (`uhabits-core-legacy/src/main/ios/**`)
   are reference material:
   - `expect` functions: `format(String/Int/Double)`, `computeToday`,
     `getFirstWeekdayNumberAccordingToLocale`, `ZipReader`/`ZipWriter`.
     Zip can throw "not supported" until phase 4.
   - `Synchronized` / `JvmStatic` are `@OptionalExpectation`, so no actual
     is required. Thread safety comes from §6.5 instead.
   - `Database` / `PreparedStatement` / `DatabaseOpener` on SQLite through
     cinterop. Legacy `IosDatabase.kt` is a near-direct port; the current
     interface adds `bindNull` and `open(path: String)`.
   - `FileOpener` / `UserFile` / `ResourceFile` on Foundation. Migration SQL
     files (`uhabits-core/assets/main/migrations/*.sql`) are bundled as app
     resources.
   - `LocalDateFormatter` on `NSDateFormatter`.
   - `Canvas` / `Image`: **not needed**, because the UI is drawn in SwiftUI
     (§6.3). If the core's iOS compilation needs them, stub them.
3. **Move reminder-time logic into `commonMain`.** It currently lives in
   `jvmMain`: `core/reminders/ReminderScheduler.kt` uses the JVM-only
   `platform/time/DateUtils`. Move the *pure computation* (the next
   reminder times for a habit given its `Reminder`, `WeekdayList`, snooze
   state, archived state, today's entry and "now") into common code so iOS
   gets the same rules. Android's `ReminderScheduler` keeps its current
   behavior: one alarm per habit, rescheduled when it fires. Common code
   has no time-zone support today. Whether to add an `expect` for time
   zone and offset or add `kotlinx-datetime` is the builder's call, as long
   as Android's results don't change, verified by the existing
   `ReminderSchedulerTest` and new common tests.
4. All existing JVM and JS tests stay green. Run `commonTest` on the iOS
   simulator target in CI as well (`iosSimulatorArm64Test`) to catch bugs
   in the iOS actuals.

### 6.3 SwiftUI app and widgets

**App target** (SwiftUI, iOS 17+):
- Screens: Habit list → Habit detail → Edit habit; Settings. Dialogs for
  number entry and notes. Phase 2 adds category, sort, filter and search
  controls.
- All values come from facade DTOs. Charts (phase 3) use SwiftUI or Swift
  Charts and draw exactly the series the facade returns.
- Colors come from Loop's palette (`PaletteColor` and the core themes),
  exposed by the facade as RGB.

**Widget extension** (WidgetKit + App Intents):
- *Check-off widget* (phase 1). It shows one habit: name, color, today's
  state or value, and possibly the score ring as a simple SwiftUI shape.
  Tapping runs `ToggleHabitIntent` (yes/no) or `IncrementHabitIntent` /
  `DecrementHabitIntent` (measurable) in the widget process. The habit is
  chosen with `AppIntentConfiguration` (the iOS counterpart of Android's
  `HabitPickerDialog`). Families: small; accessory (lock screen) if cheap.
- *Phase 3 widgets*: history, score, frequency, streak, target, each with
  a habit chosen the same way, in small/medium sizes. They carry over
  Android's choice of habit per widget, not its exact grid sizes.
- Widget timelines refresh at local midnight (taking midnight delay into
  account) and whenever the app or an intent changes data
  (`WidgetCenter.shared.reloadAllTimelines()`).
- The Android "widget opacity" setting is dropped.

**Process model and data sharing:**
- The app, the widget extension and notification-action handling all use
  one **App Group** container. It holds the SQLite database file and the
  shared preferences (`UserDefaults(suiteName:)` backing
  `Preferences.Storage` and `WidgetPreferences`).
- Each process opens its own facade instance. The core caches habits in
  memory (`SQLiteHabitList` → `MemoryHabitList`), so after another process
  writes, a process's view goes stale. Rules:
  - The widget extension and each intent open the facade fresh for every
    timeline or intent run, then close it.
  - The app calls `reload()` (discard and rebuild the core object graph)
    whenever it comes to the foreground. It also reloads when it gets a
    Darwin notification that the widget or an intent posts after a write.
- **SQLite settings**: Android disables WAL. On iOS, choosing a journal
  mode that's safe with two processes is the builder's call. Hard
  constraint: iOS kills a suspended app that still holds a file lock in a
  shared container (crash code `0xdead10cc`). Transactions must be short,
  and the app must not hold a lock or open transaction when it's
  backgrounded. Closing the database when the app goes to the background
  is acceptable.

### 6.4 Reminders on iOS

iOS can't run code when a notification fires, and only 64 local
notifications can be pending per app. So reminders are **pre-scheduled
ahead of time**, computed by the facade:

- The facade's `upcomingReminders(now, horizonDays, maxCount)` returns
  concrete occurrences `(habitId, date, fire time)`. It uses the common
  logic from §6.2.3 and excludes days the habit is already done, archived
  habits, and days not in the reminder's `WeekdayList`. It applies snooze.
- Swift replaces all pending requests with that list, capped below 64
  (call C5), using `UNCalendarNotificationTrigger` with stable identifiers
  `habit-<id>-<yyyy-mm-dd>`.
- **Rescheduling triggers**: app launch and foreground; every data change
  in the app; every widget or notification intent that changes data (the
  intent reschedules before it finishes); a best-effort `BGAppRefreshTask`.
  Marking a habit done removes that day's pending notification right away.
- **Notification actions**: *Done* marks the habit done for that date
  without opening the app, then reschedules. *Snooze* re-adds a single
  notification after a delay. Android has a snooze-delay picker; iOS uses
  one fixed default (call C4). For measurable habits, the *Done* action is
  left out and tapping the notification opens the number entry for that
  habit.
- **Siri/Shortcuts**: the toggle and increment App Intents are also
  exposed as `AppShortcuts` ("Mark <habit> done in Loop"). This costs
  almost nothing extra; drop it if it causes trouble.
- **Known limit**: if she doesn't open the app or use a widget or
  notification for longer than the scheduling horizon, reminders run out
  until one of those happens or background refresh runs. This is
  acceptable. With the 64 cap shared evenly across habits with reminders,
  the horizon is about 64 / (number of habits with reminders) days.

### 6.5 Threading

Kotlin/Native objects are thread-safe to *pass around*, but the core
expects JVM `@Synchronized` locking, which does nothing on iOS. **Every
facade call runs on one serial `DispatchQueue`, or a Swift actor, per
process.** The core's `TaskRunner` must run commands synchronously inside
facade calls on iOS, so a command has finished when the call returns. Use
a synchronous `TaskRunner` implementation, like the one the core's tests
use, rather than coroutines on background dispatchers.

## 7. Build, CI and delivery

- **Repo layout**: `ios/` holds `project.yml` (XcodeGen), `App/`,
  `Widgets/`, `Shared/` (Swift shared between targets) and `Tests/`.
  Builder's call on the details.
- **Workflows** (GitHub Actions):
  1. `android-core.yml` (ubuntu): core JVM and JS tests, facade JVM tests,
     Android build and unit tests. Guards the "don't break Android" rule.
     There is existing workflow content on the `origin/gh-actions` branch to
     start from.
  2. `ios.yml` (macOS, arm64): build the XCFramework; run core `commonTest`
     on the iOS simulator; `xcodegen`; `xcodebuild` build and test the app
     and widget on a simulator; save simulator screenshots of key screens
     and widgets as artifacts for visual review.
  3. `testflight.yml` (macOS, manual or on tag): archive and upload to
     TestFlight with an App Store Connect API key stored as repo secrets,
     using automatic signing (`-allowProvisioningUpdates` with the API
     key).
- Kotlin/Native builds are slow, so cache Gradle and Kotlin/Native
  (`~/.konan`).
- Bundle ID and App Group ID live as variables in one place (`project.yml`)
  under the owner's team. Placeholders are fine until the owner fills them
  in.

## 8. Testing strategy

| Layer | Where it runs | What it proves |
|---|---|---|
| Core `commonTest` (existing, 274 tests) | JVM and JS on Windows; iOS simulator in CI | Logic unchanged; iOS actuals behave like JVM/JS |
| Moved reminder logic | JVM (Windows) + iOS simulator | Same results as before the move; iOS occurrence lists respect days, done-today, snooze, archive, cap |
| Facade tests | JVM on Windows | Each facade operation on a real SQLite DB matches the core's behavior, DTOs are complete, and reload after an outside write sees the new data |
| Swift unit tests (XCTest) | CI simulator | Notification request building, identifier scheme, intent handlers calling the facade, App Group paths |
| Screenshots | CI simulator → artifacts | Screens and widgets render without crashing; visual review |

Test-first is the default for Kotlin code. Swift tests cover glue code
only, not layout.

## 9. Approaches considered

| | Approach | Verdict |
|---|---|---|
| **A** | **Kotlin core as an iOS framework + a facade; SwiftUI app and widgets** | **Chosen.** It keeps all the subtle logic in its one tested place, and the fork's future logic fixes apply to both platforms. It matches the original author's planned direction. Costs: two-process DB coordination (§6.3), which affects C as well, and slower CI builds. |
| B | Compose Multiplatform for app screens, SwiftUI for widgets | Rejected. The Android UI is XML Views, so nothing gets reused. Widgets still need SwiftUI, which means two UI stacks, and CMP's iOS quirks are hard to debug without a Mac. |
| C | Pure Swift rewrite reading and writing the same DB schema (like upstream PR #2224) | Rejected. It would mean re-porting all logic and tests, with the risk of making the same mistake in both. Every future logic fix would be done twice, and phase 4 import/migrations would be rewritten. It's viable only with JVM-generated parity tests. Its one advantage, faster CI, isn't worth that. The owner wasn't sure whether C avoided the widget reload cost. It doesn't: that cost comes from the iOS process model. |

Also decided: **SwiftUI drawing instead of reusing the Kotlin `Canvas`
views.** Interactive widgets must be SwiftUI anyway. A CoreGraphics `Canvas`
plus bridging is low-level, rarely written code that's hard to debug
through CI screenshots. It also adds memory pressure inside widgets.

## 10. Open questions and calls made

**Answered by the owner:**
- Q1. Her phone is an iPhone 13 on iOS 26.5, so the iOS 17+ minimum is
  fine.
- Q2. She has no history to import, so import stays in phase 4.
- Q3. The owner prefers not to do the Apple setup up front. It's needed
  only for phase 0b (TestFlight), not to start (C8).

**Calls I made (the owner can override):**
- C1. Kotlin facade as a separate module rather than inside `uhabits-core`,
  to keep Swift-facing API concerns out of the core.
- C2. The phase 1 check-off widget is small-family only; lock-screen
  widgets only if cheap.
- C3. English only.
- C4. Snooze uses a fixed default delay (15 min) on iOS rather than a
  picker.
- C5. Pending notifications are capped at about 60, split evenly across
  habits with reminders, nearest dates first.
- C6. Drop Android's widget opacity setting and stack widget.
- C7. Bundle ID and App Group ID are placeholders until the owner supplies
  their team's values in phase 0.
- C8. Phase 0 is split. 0a (CI simulator build of an empty shell) comes
  first and needs no Apple account. 0b (TestFlight to her phone) happens
  whenever the owner does the Apple setup, at the latest by the end of
  phase 1.
- C9. Measurable habits are fully in phase 1, not split across phases 1
  and 2. Targets decide "done today" for the widget, for suppressing
  reminders, and for the notification Done action, so a partial version
  would leave those undefined.

**Left to the builder:**
- Exact facade API shape and DTO fields; module name; DI wiring
- Time-zone approach for the common reminder logic (`expect` vs
  `kotlinx-datetime`), as long as Android's behavior is unchanged
- SQLite journal mode and locking details, within the §6.3 constraint
- Swift project layout under `ios/`, the screen structure, and which
  charts use Swift Charts vs custom shapes
- Order of tasks inside each phase, as long as each phase ends with a
  TestFlight build
