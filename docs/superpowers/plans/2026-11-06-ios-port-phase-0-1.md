# iOS Port, Phases 0–1: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get her daily drivers onto her iPhone: the habit list, habit editing (yes/no and measurable), the interactive check-off widget, reminders, and the detail screen with streaks, past-day editing and notes. All habit logic comes from the existing Kotlin core.

**Architecture:** `uhabits-core` gains iOS targets. A new KMP module `uhabits-ios-kit` exposes a small Swift-friendly facade (`LoopKit`, plain DTOs, ISO date strings) and builds the `LoopKit.xcframework`. A SwiftUI app and a WidgetKit extension in `ios/`, generated with XcodeGen, call only that facade. They share one SQLite DB and one `UserDefaults` suite through an App Group. CI on GitHub macOS runners compiles and tests everything iOS-related, because development happens on Windows.

**Tech Stack:** Kotlin 2.3.20 Multiplatform (jvm, js, iosArm64, iosSimulatorArm64), SQLite via cinterop, kotlin-inject (existing), SwiftUI, WidgetKit, App Intents, UserNotifications, XcodeGen, GitHub Actions (`ubuntu-latest`, `macos-latest`).

**Spec:** `docs/superpowers/specs/2026-11-06-ios-port-design.md`. Read it first. Section references (§) below point there.

## Global Constraints

- Swift never computes habit logic: streaks, scores, completion, which days are done, reminder eligibility. Swift renders facade values (§4).
- Android behavior and its tests stay unchanged. `./gradlew :uhabits-core:jvmTest :uhabits-core:jsTest :uhabits-android:assembleDebug` stays green after every task (§4).
- No Swift lands without a green `ios.yml` CI run in the same task (§4).
- iOS deployment target is **17.0** (§5).
- The Xcode project is generated from `ios/project.yml` by XcodeGen. Never commit `.xcodeproj` (§5).
- Bundle ID prefix and App Group ID live only in `ios/project.yml` as settings `LOOP_BUNDLE_PREFIX` (placeholder `com.example.loop`) and `LOOP_APP_GROUP` (placeholder `group.com.example.loop`). The App Group ID reaches Swift through an `Info.plist` key `LoopAppGroup` (§7, C7).
- Facade dates are ISO strings `yyyy-MM-dd`. Weekday arrays at the facade boundary are indexed by `daysSinceSunday` (0 = Sunday … 6 = Saturday).
- Numerical entry values are stored ×1000 in the core. The facade converts: display value = raw / 1000.0, raw = round(value × 1000).
- Every facade call from Swift goes through a single Swift `actor` per process (§6.5).
- Reminders: at most **60** pending notification requests in total. Snooze is fixed at **15 minutes** (C4, C5).
- Darwin notification name for cross-process change signals: `org.isoron.loop.dataChanged`.
- Every task ends with a commit on branch `feature/ios-port`. Tasks that need CI push that branch to `origin` (the public fork `ROODAY/uhabits`).

## Review Focus

1. **Day rollover while the app stays open, including midnight delay.** After local midnight (or midnight + delay), "today" moves forward without a relaunch. The facade re-reads today on every call and recomputes habits when it changes. Test: Task 5 `listHabits_reflectsNewTodayAfterRollover`.
2. **Two processes writing to one DB.** A widget check-off must show in the already-open app after `reload()`, and an app edit must show in the next widget run. Test: Task 4 `reload_seesWritesFromSecondInstance`.
3. **Fractional and incremented measurable values.** Entering 2.5 glasses shows 2.5, not 2 or 2.499, and +1 adds exactly 1.0. Test: Task 6 `setNumber_roundTripsFractions` and `increment_addsExactlyOneUnit`.
4. **Reminder rules match Android.** An AT_MOST habit still reminds when already "completed". Today's reminder whose time has passed isn't scheduled. Sunday maps correctly through the core's packed weekday order. Tests: Task 3 and Task 9.
5. **A habit deleted while a widget or pending notification still points at it.** The widget shows a "habit removed" placeholder. A notification action is a no-op and triggers a reschedule. Nothing crashes. Test: Task 8 `habitDetail_unknownIdReturnsNull`, plus the Swift handling in Tasks 14 and 15.

---

### Task 1: CI and an empty iOS shell (phase 0a)

**Files:**
- Create: `.github/workflows/android-core.yml`, `.github/workflows/ios.yml`
- Create: `ios/project.yml`, `ios/App/LoopApp.swift`, `ios/App/Info.plist`, `ios/App/LoopApp.entitlements`, `ios/Widgets/LoopWidgetsBundle.swift`, `ios/Widgets/Info.plist`, `ios/Widgets/LoopWidgets.entitlements`, `ios/Shared/.gitkeep`, `ios/Tests/SmokeTests.swift`, `ios/.gitignore` (ignore `*.xcodeproj`, `build/`)

**Interfaces:**
- Produces: XcodeGen targets `LoopApp` (application), `LoopWidgets` (app-extension, `com.apple.widgetkit-extension`, embedded in LoopApp), `LoopAppTests` (unit tests hosted in LoopApp). The `ios/Shared/` sources compile into both LoopApp and LoopWidgets. The scheme is `LoopApp`. Both entitlements files declare `com.apple.security.application-groups = [$(LOOP_APP_GROUP)]`.
- Produces: the `ios.yml` jobs other tasks extend: `build-test` (generate, build, test) and a `screenshots` step.

- [ ] **Step 1:** Write `android-core.yml`: on push and pull_request, `ubuntu-latest`, JDK 17 (temurin), Gradle cache. Run `./gradlew :uhabits-core:jvmTest :uhabits-core:jsTest :uhabits-android:testDebugUnitTest :uhabits-android:assembleDebug`.
- [ ] **Step 2:** Write `project.yml`: deployment target 17.0, `LOOP_BUNDLE_PREFIX` and `LOOP_APP_GROUP` settings, bundle IDs `$(LOOP_BUNDLE_PREFIX).app` and `$(LOOP_BUNDLE_PREFIX).app.widgets`, Swift 5 mode. `LoopApp` shows a `Text("Loop")`. `LoopWidgets` contains one static placeholder widget so the extension compiles. `SmokeTests` has `testTruth() { XCTAssertTrue(true) }`.
- [ ] **Step 3:** Write `ios.yml`: on push and pull_request, `macos-latest`. Steps: `brew install xcodegen`, `cd ios && xcodegen generate`. Then `xcodebuild test -scheme LoopApp -destination 'platform=iOS Simulator,name=<first available iPhone>' CODE_SIGNING_ALLOWED=NO`, choosing the device name from `xcrun simctl list devices available` at runtime. Boot the simulator, install the built app, launch it, run `xcrun simctl io booted screenshot list.png`, and upload `*.png` as artifact `screenshots`.
- [ ] **Step 4:** Commit, push, and watch both runs.
  Run: `git push -u origin feature/ios-port && gh run watch --exit-status $(gh run list -b feature/ios-port -w ios.yml -L1 --json databaseId -q '.[0].databaseId')`. Do the same for `android-core.yml`.
  Expected: both green; the `screenshots` artifact shows "Loop".

### Task 2: `uhabits-core` on iOS

**Files:**
- Modify: `uhabits-core/build.gradle.kts` (targets, cinterop, test filter); `gradle.properties` if a flag is needed
- Create: `uhabits-core/src/nativeInterop/cinterop/sqlite3.def`
- Create: `uhabits-core/src/iosMain/kotlin/org/isoron/platform/io/IosDatabase.kt`, `IosFiles.kt`, `IosStrings.kt`, `Zip.kt`
- Create: `uhabits-core/src/iosMain/kotlin/org/isoron/platform/time/IosDates.kt`
- Create: `uhabits-core/src/iosTest/kotlin/org/isoron/platform/io/TestDatabaseHelper.kt`, `TestPlatformHelper.kt`
- Modify: `.github/workflows/ios.yml` (new job `core-ios-tests`)

**Interfaces:**
- Produces (iosMain): `class IosDatabaseOpener : DatabaseOpener`. Its `open(path)` creates parent dirs, opens with `sqlite3_open_v2(READWRITE|CREATE|FULLMUTEX)` and runs `PRAGMA busy_timeout = 3000` (the §6.3 choice: keep rollback journaling, which matches Android).
- Produces: `class IosFileOpener(resourceRoots: List<String>, userRoot: String) : FileOpener`. It resolves a resource against each root in order and uses the first that exists, mirroring `JavaResourceFile`'s main-then-test lookup.
- Produces: `class IosLocalDateFormatter(localeIdentifier: String) : LocalDateFormatter`.
- Reference: the legacy implementations at `git show 3330014f^:uhabits-core-legacy/src/main/ios/org/isoron/platform/...` (`IosDatabase.kt`, `IosFiles.kt`, `IosDates.kt`, `Strings.kt`, `c_interop/sqlite3.def`).

- [ ] **Step 1:** Add `iosArm64()` and `iosSimulatorArm64()` targets, with an `sqlite3` cinterop on both (`linkerOpts = -lsqlite3`). If Kotlin/Native rejects `compileOnly(libs.kotlin.inject.runtime)` in commonMain, change it to `implementation` (§6.2.1). On Windows, `./gradlew :uhabits-core:jvmTest :uhabits-core:jsTest` must stay green and iOS tasks may be skipped. Record in the commit message whether `compileKotlinIosArm64` ran on Windows.
- [ ] **Step 2:** Implement the iosMain actuals:
  - `format(...)` via `NSString.stringWithFormat`. If variadic interop fails, use the legacy `sprintf` approach.
  - `computeToday(hourOffset, minuteOffset)`: from `NSDate()` plus `NSTimeZone.localTimeZone.secondsFromGMT`, using the same arithmetic as the JVM `JvmDates.kt`.
  - `getFirstWeekdayNumberAccordingToLocale()`: `NSCalendar.currentCalendar.firstWeekday`.
  - `ZipReader` / `ZipWriter`: throw `UnsupportedOperationException("zip: phase 4")`.
  - Database: a port of legacy `IosDatabase.kt`, adding `bindNull`.
  - Files: a port of legacy `IosFiles.kt` onto the current `FileOpener` / `UserFile` / `ResourceFile` interfaces. `ResourceFile.toImage()` throws.
- [ ] **Step 3:** Implement the iosTest helpers. `createTestFileOpener()` reads env var `LOOP_TEST_ASSETS` (absolute path to `uhabits-core/assets`) and uses roots `["$it/main", "$it/test"]` with a temp user root. `TestDatabaseHelper` mirrors the jvmTest version on `IosDatabaseOpener`, using `":memory:"`. `createTestCanvas` and `ensureFontsLoaded` throw. In Gradle, pass `SIMCTL_CHILD_LOOP_TEST_ASSETS=${projectDir}/assets` to the `iosSimulatorArm64Test` task. Exclude the canvas-dependent classes with the test filter: `*CanvasTest`, `*BarChartTest`, `*HistoryChartTest`, and any class using `ViewTestHelper`.
- [ ] **Step 4:** Add CI job `core-ios-tests` (`macos-latest`, JDK 17, cache `~/.konan` and Gradle) running `./gradlew :uhabits-core:iosSimulatorArm64Test`. Push and watch.
  Expected: green. Every commonTest class except the excluded canvas tests runs and passes.
- [ ] **Step 5:** Commit. `feat(core): add iOS targets and platform actuals`.

### Task 3: Shared reminder-eligibility rule

**Files:**
- Create: `uhabits-core/src/commonMain/kotlin/org/isoron/uhabits/core/reminders/ReminderRules.kt`
- Modify: `uhabits-core/src/commonMain/kotlin/org/isoron/uhabits/core/ui/NotificationTray.kt:120-152` (call the new function; behavior unchanged)
- Test: `uhabits-core/src/commonTest/kotlin/org/isoron/uhabits/core/reminders/ReminderRulesTest.kt`

**Interfaces:**
- Produces: `fun shouldShowReminder(habit: Habit, date: LocalDate): Boolean`. It returns true iff the habit has a reminder, is not archived, the reminder's `WeekdayList` includes `date` (core packed index `(date.dayOfWeek.daysSinceSunday + 1) % 7`), and `!(habit.isCompletedOn(date) && habit.targetType != NumericalHabitType.AT_MOST)`. This extracts what `NotificationTray.ShowNotificationTask` checks today. The spec's §6.2.3 move of `ReminderScheduler` is unnecessary: iOS only needs this rule plus Task 9's enumeration, and Android's `ReminderScheduler` stays untouched.

- [ ] **Step 1: Write failing tests** (extend `BaseUnitTest`; today = 2015-01-25, a Sunday):
  `noReminder_false`, `archived_false`, `dayNotInReminderDays_false` (days = only Monday), `sundayIncluded_true` (packed index 1 set → date 2015-01-25 → true), `completedYesNo_false`, `completedAtMost_stillTrue`, `notCompleted_true`.
- [ ] **Step 2:** Run `./gradlew :uhabits-core:jvmTest --tests '*ReminderRulesTest*'`. Expected: FAIL (unresolved `shouldShowReminder`).
- [ ] **Step 3:** Implement `shouldShowReminder` and make `NotificationTray` use it.
- [ ] **Step 4:** Run `./gradlew :uhabits-core:jvmTest :uhabits-core:jsTest`. Expected: all pass, including the existing `NotificationTrayTest`.
- [ ] **Step 5:** Commit. `refactor(core): extract shouldShowReminder`.

### Task 4: `uhabits-ios-kit` module: open, reload, close

**Files:**
- Modify: `settings.gradle.kts` (include `:uhabits-ios-kit`; also remove the duplicated `include` line)
- Create: `uhabits-ios-kit/build.gradle.kts`
- Create: `uhabits-ios-kit/src/commonMain/kotlin/org/isoron/uhabits/ioskit/LoopKit.kt`, `KeyValueStore.kt`, `SyncRunner.kt`
- Create: `uhabits-ios-kit/src/iosMain/kotlin/org/isoron/uhabits/ioskit/LoopKitFactory.kt`
- Test: `uhabits-ios-kit/src/jvmTest/kotlin/org/isoron/uhabits/ioskit/LoopKitOpenTest.kt`, `TestKit.kt`

**Interfaces:**
- Produces: `interface KeyValueStore { fun getString(key: String): String?; fun putString(key: String, value: String); fun remove(key: String); fun clear() }`. Swift implements this over `UserDefaults(suiteName:)`.
- Produces: `internal class KeyValueStorage(store: KeyValueStore) : Preferences.Storage`. Bools, ints and longs are stored as their `toString()`, and parse failures fall back to the default.
- Produces: `internal fun <T> runSync(block: suspend () -> T): T`. It starts the coroutine with `startCoroutine` on `EmptyCoroutineContext` and throws `IllegalStateException("suspended")` if the coroutine didn't complete synchronously. Also `internal class SyncTaskRunner : TaskRunner`. Its `execute` calls `onAttached`, `onPreExecute`, `runSync { doInBackground() }` and `onPostExecute` inline; `activeTaskCount` = 0; `await()` returns immediately.
- Produces: `fun interface TodaySource { fun today(midnightDelayHours: Int): LocalDate }`. The default is `TodaySource { computeToday(it, 0) }`.
- Produces: `class LoopKit(databaseOpener: DatabaseOpener, fileOpener: FileOpener, dbPath: String, store: KeyValueStore, todaySource: TodaySource)` with `fun reload()` and `fun close()`. Construction opens the DB and migrates to `DATABASE_VERSION` (26), loading `migrations/%02d.sql` through `fileOpener.openResourceFile`. A brand-new file starts at `setVersion(8)`, exactly as `HabitsDatabaseOpener.onCreate` does. It then builds `SQLModelFactory`, the `HabitList`, `Preferences(KeyValueStorage(store))`, `WidgetPreferences`, `CommandRunner(SyncTaskRunner())`. `reload()` closes the DB and rebuilds all of these. Every public method calls a private `refreshToday()` first: `setToday(todaySource.today(prefs.midnightDelayHours))` and `setFirstWeekday(prefs.firstWeekday)`. If today changed since the last call, or on first load, it runs `habit.recompute()` for every habit.
- Produces (iosMain): `fun createLoopKit(dbPath: String, resourcesPath: String, store: KeyValueStore): LoopKit`, using `IosDatabaseOpener` and `IosFileOpener(listOf(resourcesPath), dbPath's directory)`.
- Produces (Gradle): the module targets `jvm()`, `iosArm64()` and `iosSimulatorArm64()`, and builds an XCFramework with `baseName = "LoopKit"`, `isStatic = true`, and `export(project(":uhabits-core"))` **not** set (only the facade API is exposed). The Gradle task is `:uhabits-ios-kit:assembleLoopKitReleaseXCFramework`.
- Produces (jvmTest): `fun testKit(dir: java.io.File, today: LocalDate = LocalDate(2015, 1, 25)): Pair<LoopKit, MapStore>`, using `JavaDatabaseOpener` and `JavaFileOpener`. Gradle sets the jvmTest working directory to `../uhabits-core` so `assets/main/migrations` resolves. `MapStore` is an in-memory `KeyValueStore`.

- [ ] **Step 1: Write failing tests:**
  - `open_newFileMigratesToCurrentVersion`: open a kit on a temp file, then reopen the raw DB and assert `getVersion() == 26`.
  - `reload_seesWritesFromSecondInstance`: two kits on the same file. Kit B creates a habit through the core (a test-only internal accessor is fine until Task 7), kit A reloads and its internal habit list size == 1.
  - `preferencesPersistInStore`: set `isSkipEnabled = true` through the internal prefs, then a new kit on the same store reads true.
  - `syncTaskRunner_runsCommandBeforeReturning`.
- [ ] **Step 2:** Run `./gradlew :uhabits-ios-kit:jvmTest`. Expected: FAIL (classes missing).
- [ ] **Step 3:** Implement the module per Interfaces.
- [ ] **Step 4:** Run `./gradlew :uhabits-ios-kit:jvmTest`. Expected: PASS.
- [ ] **Step 5:** Add to `ios.yml` a step that runs `./gradlew :uhabits-ios-kit:assembleLoopKitReleaseXCFramework` before `xcodegen` (JDK 17, `~/.konan` cache), and add `:uhabits-ios-kit:jvmTest` to `android-core.yml`. Push and watch. Expected: both green and the XCFramework is built.
- [ ] **Step 6:** Commit. `feat(ioskit): facade module with open/reload/close`.

### Task 5: `listHabits`, the palette, and today

**Files:**
- Create: `uhabits-ios-kit/src/commonMain/kotlin/org/isoron/uhabits/ioskit/Dtos.kt`, `Dates.kt`
- Modify: `LoopKit.kt`
- Test: `uhabits-ios-kit/src/jvmTest/kotlin/org/isoron/uhabits/ioskit/ListHabitsTest.kt`

**Interfaces:**
- Produces (`Dates.kt`): `internal fun LocalDate.iso(): String` (`yyyy-MM-dd`, zero-padded) and `internal fun parseIso(s: String): LocalDate`.
- Produces (`Dtos.kt`):
  - `data class DayCell(val date: String, val rawValue: Int, val value: Double, val isCompleted: Boolean, val notes: String)`. `rawValue` is the computed entry's value: for yes/no one of `Entry.UNKNOWN/NO/YES_AUTO/YES_MANUAL/SKIP`, for numerical the raw ×1000 value. `value`: numerical → `max(raw, 0) / 1000.0`; yes/no → 1.0 if YES_AUTO or YES_MANUAL, else 0.0. `notes` comes from `originalEntries`.
  - `data class HabitRow(val id: Long, val name: String, val question: String, val colorIndex: Int, val isNumerical: Boolean, val unit: String, val targetValue: Double, val targetType: Int, val isArchived: Boolean, val score: Double, val isCompletedToday: Boolean, val today: String, val days: List<DayCell>)`. `days` is newest first, starting at today. `score` is `habit.scores[today].value`.
- Produces (`LoopKit`): `fun listHabits(dayCount: Int, includeArchived: Boolean): List<HabitRow>` (order `BY_POSITION`); `fun palette(dark: Boolean): List<Int>` returning 20 RGB ints (`0xRRGGBB`) for palette indices 0–19 from `LightTheme()` or `DarkTheme()`; `fun today(): String`; `fun midnightDelayHours(): Int`; `fun areQuestionMarksEnabled(): Boolean` (the Swift glyph choice in Task 11 needs it).

- [ ] **Step 1: Write failing tests:**
  - `listHabits_returnsDaysNewestFirst`: a habit with YES_MANUAL on 2015-01-25 and 2015-01-23. `days[0].date == "2015-01-25"`, `days[0].rawValue == 2`, `days[0].isCompleted`, and `days[1].date == "2015-01-24"`.
  - `listHabits_numericalValueScaled`: raw 2500 → `value == 2.5`.
  - `listHabits_excludesArchivedUnlessAsked`.
  - `listHabits_reflectsNewTodayAfterRollover`: a mutable `TodaySource`. Change it from 2015-01-25 to 2015-01-26, then `listHabits(...)[0].today == "2015-01-26"` and `days[0].date == "2015-01-26"`.
  - `palette_hasTwentyColors_firstIsRed`: `palette(false)[0] == 0xD32F2F`.
  - `iso_roundTrips`: for 2000-01-01, 2015-01-25 and 2024-02-29.
- [ ] **Step 2:** Run `./gradlew :uhabits-ios-kit:jvmTest --tests '*ListHabitsTest*'`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `./gradlew :uhabits-ios-kit:jvmTest`. Expected: PASS.
- [ ] **Step 5:** Commit. `feat(ioskit): listHabits, palette, today`.

### Task 6: Entry mutations

**Files:**
- Modify: `LoopKit.kt`
- Test: `uhabits-ios-kit/src/jvmTest/kotlin/org/isoron/uhabits/ioskit/EntryMutationsTest.kt`

**Interfaces:**
- Produces (`LoopKit`), each going through `WidgetBehavior` or `CreateRepetitionCommand` via `commandRunner`, with notes preserved unless the method sets them. Each returns `Unit`, and an unknown habit ID is a no-op:
  - `fun toggle(habitId: Long, date: String)`: `WidgetBehavior.onToggleRepetition` (honors `isSkipEnabled` and `areQuestionMarksEnabled`)
  - `fun markDone(habitId: Long, date: String)`: `onAddRepetition` (YES_MANUAL), used by notification Done
  - `fun increment(habitId: Long, date: String)` / `fun decrement(habitId: Long, date: String)`: `onIncrement` / `onDecrement` with amount 1000
  - `fun setNumber(habitId: Long, date: String, value: Double, notes: String)`: raw = `round(value * 1000).toInt()`
  - `fun setNotes(habitId: Long, date: String, notes: String)`: keeps the existing original value
- `WidgetBehavior` needs a `NotificationTray`. Pass a no-op subclass, since iOS notification cancelling is handled in Swift (Task 14).

- [ ] **Step 1: Write failing tests:**
  - `toggle_cyclesYesThenNo` (default prefs: UNKNOWN → YES_MANUAL → NO)
  - `toggle_withSkipEnabled_goesToSkip`
  - `markDone_setsYesManual`
  - `increment_addsExactlyOneUnit` (2.5 → 3.5)
  - `setNumber_roundTripsFractions` (0.1, 2.5, 1234.567 round-trip to 3 decimals)
  - `setNotes_keepsValue`
  - `mutation_unknownHabit_noop`
  - `mutation_updatesStreakImmediately` (after `markDone` on today, `listHabits` shows `isCompletedToday`)
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `./gradlew :uhabits-ios-kit:jvmTest`. Expected: PASS.
- [ ] **Step 5:** Commit. `feat(ioskit): entry mutations`.

### Task 7: Create, edit and delete habits

**Files:**
- Modify: `Dtos.kt`, `LoopKit.kt`
- Test: `uhabits-ios-kit/src/jvmTest/kotlin/org/isoron/uhabits/ioskit/HabitCrudTest.kt`

**Interfaces:**
- Produces: `data class ReminderDto(val hour: Int, val minute: Int, val days: List<Boolean>)`, where `days` has size 7 and index = `daysSinceSunday`. Conversion to `WeekdayList`: core index `(i + 1) % 7` = `days[i]`.
- Produces: `data class HabitInput(val name: String, val question: String, val description: String, val colorIndex: Int, val isNumerical: Boolean, val unit: String, val targetValue: Double, val targetType: Int, val freqNumerator: Int, val freqDenominator: Int, val reminder: ReminderDto?)`
- Produces: `fun createHabit(input: HabitInput): Long` (via `CreateHabitCommand`, returns the new ID), `fun editHabit(habitId: Long, input: HabitInput)` (via `EditHabitCommand`), `fun deleteHabit(habitId: Long)` (via `DeleteHabitsCommand`), `fun habitInput(habitId: Long): HabitInput?` (pre-fills the edit screen).
- Validation (throw `IllegalArgumentException`): blank name; `freqNumerator < 1` or `freqDenominator < freqNumerator`; numerical with `targetValue < 0`; `colorIndex !in 0..19`.

- [ ] **Step 1: Write failing tests:**
  - `create_thenListed`
  - `create_numericalFieldsRoundTrip`
  - `edit_changesNameKeepsEntries`
  - `delete_removes`
  - `reminderDays_sundayMapsToCorePackedIndex1` (days[0] = true only → `WeekdayList.toArray()[1]`, and the round-trip through `habitInput` returns days[0] = true only)
  - `create_blankName_throws`
  - `create_badFrequency_throws`
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `./gradlew :uhabits-ios-kit:jvmTest`. Expected: PASS.
- [ ] **Step 5:** Commit. `feat(ioskit): habit create/edit/delete`.

### Task 8: Habit detail and streaks

**Files:**
- Modify: `Dtos.kt`, `LoopKit.kt`
- Test: `uhabits-ios-kit/src/jvmTest/kotlin/org/isoron/uhabits/ioskit/HabitDetailTest.kt`

**Interfaces:**
- Produces: `data class StreakDto(val start: String, val end: String, val length: Int)`
- Produces: `data class HabitDetail(val row: HabitRow, val description: String, val freqNumerator: Int, val freqDenominator: Int, val reminder: ReminderDto?, val currentStreak: Int, val bestStreaks: List<StreakDto>)`. `row.days` covers `historyDays` days.
- Produces: `fun habitDetail(habitId: Long, historyDays: Int): HabitDetail?`, which returns null for an unknown ID. `bestStreaks` = `habit.streaks.getBest(10)` in the order the core returns. `currentStreak` = the length of the streak whose `end` is today or yesterday (it's still alive until today's day ends), else 0. This is my call on the meaning of "current streak", since Android shows only the best streaks.

- [ ] **Step 1: Write failing tests:**
  - `habitDetail_unknownIdReturnsNull`
  - `currentStreak_countsThroughToday` (done 01-23..01-25 → 3)
  - `currentStreak_aliveIfDoneYesterdayOnly` (done 01-22..01-24 → 3)
  - `currentStreak_zeroIfGap` (last done 01-23 → 0)
  - `bestStreaks_matchCoreGetBest` (compare against `habit.streaks.getBest(10)` on the same fixture, `HabitFixtures.createLongHabit()`)
  - `history_includesNotes`
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `./gradlew :uhabits-ios-kit:jvmTest`. Expected: PASS.
- [ ] **Step 5:** Commit. `feat(ioskit): habit detail and streaks`.

### Task 9: Upcoming reminders

**Files:**
- Modify: `Dtos.kt`, `LoopKit.kt`
- Test: `uhabits-ios-kit/src/jvmTest/kotlin/org/isoron/uhabits/ioskit/UpcomingRemindersTest.kt`

**Interfaces:**
- Consumes: `shouldShowReminder(habit, date)` (Task 3).
- Produces: `data class ReminderOccurrence(val habitId: Long, val habitName: String, val question: String, val isNumerical: Boolean, val date: String, val hour: Int, val minute: Int)`
- Produces: `fun upcomingReminders(nowDate: String, nowMinuteOfDay: Int, horizonDays: Int, maxCount: Int): List<ReminderOccurrence>`. For each day `d` from `nowDate` through `nowDate + horizonDays - 1`, and each habit, emit when `shouldShowReminder(habit, d)` holds and, if `d == nowDate`, `hour * 60 + minute > nowMinuteOfDay`. Sort by (date, hour, minute, habitId) and take the first `maxCount`. Chronological truncation gives every habit the same covered days, which satisfies C5's "split evenly, nearest first". `nowDate` is the *calendar* date from Swift, not the midnight-delayed habit day. Reminders fire on calendar days, as on Android.

- [ ] **Step 1: Write failing tests:**
  - `excludesTodayIfTimePassed`
  - `includesTodayIfTimeAhead`
  - `respectsReminderDays`
  - `skipsDayAlreadyCompleted_yesNo`
  - `atMostHabit_includedEvenIfCompleted`
  - `excludesArchived`
  - `truncatesChronologically` (3 habits daily, horizon 30, max 60 → exactly 60, last date = start + 19)
  - `sortedByDateThenTime`
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `./gradlew :uhabits-ios-kit:jvmTest`. Expected: PASS.
- [ ] **Step 5:** Commit. `feat(ioskit): upcomingReminders`.

### Task 10: Swift shared layer

**Files:**
- Modify: `ios/project.yml`: link `../uhabits-ios-kit/build/XCFrameworks/release/LoopKit.xcframework` into LoopApp and LoopWidgets. Add `../uhabits-core/assets/main/migrations` as a folder reference resource to both. Add the `LoopAppGroup` Info.plist key = `$(LOOP_APP_GROUP)`.
- Create: `ios/Shared/AppGroup.swift`, `UserDefaultsStore.swift`, `LoopStore.swift`, `DateKey.swift`, `ChangeSignal.swift`
- Test: `ios/Tests/DateKeyTests.swift`, `ios/Tests/LoopStoreTests.swift`

**Interfaces:**
- Produces:
  - `enum AppGroup { static var id: String; static var containerURL: URL; static var dbPath: String; static var defaults: UserDefaults }`. The DB file is `containerURL/Loop.db`. If `containerURL(forSecurityApplicationGroupIdentifier:)` returns nil (unsigned simulator builds), fall back to the app's Application Support directory.
  - `final class UserDefaultsStore: KeyValueStore`
  - `enum DateKey { static func iso(_ date: Date, calendar: Calendar = .current) -> String; static func date(fromIso: String) -> DateComponents; static func minuteOfDay(_ date: Date) -> Int }`
  - `actor LoopStore { static let shared; func open(); func close(); func reload(); func withKit<T>(_ body: (LoopKit) throws -> T) rethrows -> T; func mutate(_ body: (LoopKit) throws -> Void) rethrows }`. `mutate` runs the body, then calls `ChangeSignal.post()` and `WidgetCenter.shared.reloadAllTimelines()`, then calls the `afterMutation` hook. The hook is a settable `@Sendable () async -> Void`; Task 14 uses it for rescheduling.
  - `enum ChangeSignal { static func post(); static func observe(_ handler: @escaping @Sendable () -> Void) }` over `CFNotificationCenterGetDarwinNotifyCenter` with name `org.isoron.loop.dataChanged`.
- Lifecycle rule (§6.3): the app opens the store on scene `.active` and closes it on `.background`. The extension and intents open the store, do their work and close it within one call.

- [ ] **Step 1:** Write XCTests:
  - `testIsoFormat`: Nov 6, 2026 → `"2026-11-06"`
  - `testMinuteOfDay`
  - `testStoreCreateToggleList`: temp DB path; `createHabit`, `toggle` today, `listHabits` → completed today
  - `testReloadSeesOtherInstance`
  - `testUserDefaultsStoreRoundTrip`
- [ ] **Step 2:** Implement. Push and watch `ios.yml`. Expected: green (the XCFramework builds and links, and the tests pass).
- [ ] **Step 3:** Commit. `feat(ios): shared LoopStore layer`.

### Task 11: Habit list screen

**Files:**
- Create: `ios/App/HabitListView.swift`, `HabitRowView.swift`, `CheckmarkCell.swift`, `NumberEntrySheet.swift`, `Palette.swift`, `DemoSeed.swift`
- Modify: `ios/App/LoopApp.swift`, `.github/workflows/ios.yml` (screenshots)

**Interfaces:**
- Consumes: `listHabits`, `toggle`, `setNumber`, `setNotes`, `palette` (Tasks 5–6) through `LoopStore`.
- Produces: `struct HabitListView`. Each row shows the habit name in its palette color, a score ring (a SwiftUI `Circle().trim` driven by `row.score`), and the last 5 days as `CheckmarkCell`s, today first.
  - Yes/no cells: tap = `toggle`. Glyph by `rawValue`: YES_MANUAL ✓, YES_AUTO faded ✓, NO ✗, SKIP ⤏, UNKNOWN "?" if question marks are enabled, else ✗.
  - Numerical cells show `value` with the unit. Tap opens `NumberEntrySheet(value, notes)`, which saves through `setNumber`.
  - Long-press on any cell opens a notes editor (`setNotes`).
  - A toolbar "+" button opens the edit screen (Task 12), and tapping a row's name opens the detail screen (Task 13). Use placeholder destinations until those tasks land.
- Produces: `DemoSeed`. When the app launches with argument `--seed-demo` and the habit list is empty, it creates 3 yes/no habits and 1 measurable habit ("Water", unit "glasses", target 8) with 30 days of varied entries, all through the facade. The `--screen list` launch argument opens the list.
- Refresh: the list re-queries on `.active`, after every mutation, and on `ChangeSignal`. It also re-queries when the calendar day changes (`.NSCalendarDayChanged`) and on a timer at the next midnight-delay boundary (from `midnightDelayHours()`, Task 5).

- [ ] **Step 1:** Write an XCTest, `testDemoSeedCreatesFourHabits`, against a temp store.
- [ ] **Step 2:** Implement. In CI, take the screenshot after launching with `--seed-demo --screen list` and save it as `list.png`.
- [ ] **Step 3:** Push and watch. Expected: green, and `list.png` shows 4 rows with colored names, rings and checkmarks.
- [ ] **Step 4:** Commit. `feat(ios): habit list`.

### Task 12: Edit habit screen

**Files:**
- Create: `ios/App/HabitEditView.swift`, `FrequencyPicker.swift`, `ReminderPicker.swift`, `ColorPicker.swift`
- Modify: `.github/workflows/ios.yml` (`--screen edit` screenshot)

**Interfaces:**
- Consumes: `createHabit`, `editHabit`, `deleteHabit`, `habitInput`, `palette` (Task 7).
- Produces: `struct HabitEditView(habitId: Long?)`. It's a SwiftUI `Form` with: name, question, a type selector (yes/no or measurable; locked after creation, as on Android), a color grid of 20 swatches, and frequency presets (every day, every week, N times per week, N times per month, every N days). Presets map to numerator/denominator the way Android's frequency picker does: N/7 per week, N/30 per month, 1/N every N days. Measurable habits add unit, target and AT_LEAST/AT_MOST. A reminder toggle reveals a time picker and 7 weekday toggles, ordered by the facade's `daysSinceSunday` index and displayed starting from the locale's first weekday. Delete (edit mode only) asks for confirmation. Facade validation errors show inline.

- [ ] **Step 1:** Write an XCTest, `testFrequencyPresetMapping`, covering every preset → (numerator, denominator).
- [ ] **Step 2:** Implement. Push and watch. Expected: green, and `edit.png` renders.
- [ ] **Step 3:** Commit. `feat(ios): edit habit screen`.

### Task 13: Habit detail screen

**Files:**
- Create: `ios/App/HabitDetailView.swift`, `StreaksCard.swift`, `HistoryEditorCard.swift`
- Modify: `.github/workflows/ios.yml` (`--screen detail` screenshot of the first seeded habit)

**Interfaces:**
- Consumes: `habitDetail`, `toggle`, `setNumber`, `setNotes` (Tasks 6 and 8).
- Produces: `struct HabitDetailView(habitId: Long)`. It has:
  - A header with name, question, frequency text and reminder text.
  - `StreaksCard`: the current streak as a big number, plus `bestStreaks` as horizontal bars proportional to `length`, labeled with start–end dates. Only the bar widths are scaled in Swift; the lengths come from the facade.
  - `HistoryEditorCard`: the last 8 weeks as a 7-row grid (`historyDays = 56`), starting from the locale's first weekday. Tap toggles a yes/no day or opens `NumberEntrySheet` for a measurable one. Long-press edits notes. Days with notes show a small dot.
  - A notes list: the days in the window that have non-empty notes, newest first.
  - Edit opens `HabitEditView(habitId)`. A nil `habitDetail` (deleted habit) pops back to the list.

- [ ] **Step 1:** Implement. Push and watch. Expected: green, and `detail.png` shows the streak bars and a grid with a mix of states.
- [ ] **Step 2:** Commit. `feat(ios): habit detail with streaks, history, notes`.

### Task 14: Reminders

**Files:**
- Create: `ios/App/NotificationPlanner.swift`, `NotificationHandler.swift`, `BackgroundRefresh.swift`
- Modify: `ios/App/LoopApp.swift`, `ios/App/Info.plist` (`BGTaskSchedulerPermittedIdentifiers = [org.isoron.loop.refresh]`, `UIBackgroundModes = [fetch]`)
- Test: `ios/Tests/NotificationPlannerTests.swift`

**Interfaces:**
- Consumes: `upcomingReminders`, `markDone` (Tasks 6 and 9). Uses the `LoopStore.afterMutation` hook (Task 10).
- Produces: `enum NotificationPlanner`:
  - `static func requests(for occurrences: [ReminderOccurrence], calendar: Calendar) -> [UNNotificationRequest]`, a pure function. Identifier `habit-<id>-<yyyy-MM-dd>`. `UNCalendarNotificationTrigger` with year/month/day/hour/minute and `repeats: false`. Title = habit name, body = question if not empty. Category `HABIT_YESNO` or `HABIT_NUMERICAL`. `userInfo = ["habitId": id, "date": iso]`.
  - `static func reschedule() async`: calls `upcomingReminders(nowDate: DateKey.iso(.now), nowMinuteOfDay:, horizonDays: 14, maxCount: 60)`, removes all pending requests whose identifier starts with `habit-` (keeping those starting with `snooze-`), and adds the new ones.
  - `static let maxPending = 60`; `snoozeMinutes = 15`.
- Produces: categories. `HABIT_YESNO` has actions `DONE` ("Done", no foreground) and `SNOOZE` ("Snooze 15 min", no foreground). `HABIT_NUMERICAL` has `SNOOZE` only; tapping its body opens `NumberEntrySheet` for that habit and date.
- Produces: `NotificationHandler: UNUserNotificationCenterDelegate`.
  - `DONE` → `LoopStore.mutate { markDone }` (which reschedules), then removes delivered notifications for that habit.
  - `SNOOZE` → adds `snooze-<id>` with a 15-minute interval trigger and the same content.
  - Unknown habit IDs → no-op, then `reschedule()`.
  - Foreground presentation: banner + sound.
- Triggers for `reschedule()`: app `.active`; `LoopStore.afterMutation`; `BGAppRefreshTask` `org.isoron.loop.refresh`, which is re-submitted every run with an earliest date 6h ahead; and the widget intents (Task 15). When a habit is marked done for a date, also remove `snooze-<id>` and delivered notifications for that habit.
- Permission: request `.alert, .sound, .badge` when a habit with a reminder is first saved, or on launch if any reminders exist. If permission is denied, show a one-line notice in Settings/the edit screen.

- [ ] **Step 1: Write failing XCTests:**
  - `testIdentifierScheme`
  - `testTriggerComponents` (2026-11-06 21:30 → matching components, repeats false)
  - `testCategoryByType`
  - `testCapRespected` (100 occurrences in → at most 60 requests; the planner also enforces the cap on its own)
  - `testBodyUsesQuestion`
- [ ] **Step 2:** Implement. Push and watch. Expected: green.
- [ ] **Step 3:** Commit. `feat(ios): reminders`.

### Task 15: Check-off widget, intents and Shortcuts

**Files:**
- Create: `ios/Shared/HabitEntity.swift` (`AppEntity` + `EntityQuery`), `ios/Shared/HabitIntents.swift`, `ios/Widgets/CheckmarkWidget.swift`, `ios/App/LoopShortcuts.swift`
- Modify: `ios/Widgets/LoopWidgetsBundle.swift` (replace the placeholder), `.github/workflows/ios.yml` (widget preview snapshot)

**Interfaces:**
- Consumes: `listHabits`, `toggle`, `increment`, `decrement`, `palette`; `NotificationPlanner.reschedule()`. The planner lives in the app target, so the intents call it only when compiled in the app. In the extension, the intent posts `ChangeSignal`, and the app reschedules on its next `ChangeSignal`, `.active` or background refresh. The extension also removes that habit's pending notification for the date, using identifier `habit-<id>-<date>` via `UNUserNotificationCenter` (allowed from extensions).
- Produces:
  - `struct HabitEntity: AppEntity` (`id: Int64`, `name: String`), with a query that lists non-archived habits through the facade.
  - `ToggleHabitIntent(habit: HabitEntity)`, `IncrementHabitIntent(habit:)`, `DecrementHabitIntent(habit:)`. Each `perform()` opens the store, mutates for today (`LoopStore.shared.withKit { $0.today() }`), closes it, posts `ChangeSignal` and reloads timelines.
  - `CheckmarkWidget`: `AppIntentConfiguration` with `SelectHabitIntent: WidgetConfigurationIntent`, family `.systemSmall`. The entry is built from the selected habit's `HabitRow`. Yes/no shows the name, the score ring and a big check `Button(intent: ToggleHabitIntent)`. Measurable shows the name, today's value / target, and −/+ buttons. A missing habit shows "Habit removed — edit widget". The timeline has one entry now and policy `.after(next local midnight + midnightDelayHours)`.
  - `LoopShortcuts: AppShortcutsProvider` exposing `ToggleHabitIntent` with the phrase "Check off \(\.$habit) in \(.applicationName)". Drop it if it fails to build (§6.4).

- [ ] **Step 1:** Write an XCTest, `testWidgetEntryForDeletedHabit`, for the entry-building function `CheckmarkEntry.make(row: HabitRow?)`, which must be pure and testable.
- [ ] **Step 2:** Implement. In CI, render `CheckmarkWidgetView` for a seeded habit via `ImageRenderer` in a test, attach it, and upload `widget.png`.
- [ ] **Step 3:** Push and watch. Expected: green, and `widget.png` shows a habit with a check button.
- [ ] **Step 4:** Commit. `feat(ios): interactive check-off widget and shortcuts`.

### Task 16: TestFlight delivery (phase 0b, needs the owner's Apple setup)

**Files:**
- Create: `ios/SETUP.md`, `.github/workflows/testflight.yml`, `ios/ExportOptions.plist`

**Interfaces:**
- Consumes: repo secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (base64), `APPLE_TEAM_ID`, plus repo variables `LOOP_BUNDLE_PREFIX` and `LOOP_APP_GROUP`.
- Produces: `testflight.yml` (`workflow_dispatch`). It builds the XCFramework, runs `xcodegen` with the variables substituted, then `xcodebuild archive -allowProvisioningUpdates -authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID DEVELOPMENT_TEAM=$APPLE_TEAM_ID` and `CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER`. It exports with `method = app-store-connect` and uploads with `xcrun altool --upload-app` (or `xcodebuild -exportArchive` with `destination = upload`).
- Produces: `SETUP.md`, a numbered click-path for the owner:
  1. Choose the prefix
  2. Register both App IDs with App Groups and the App Group
  3. Create the App Store Connect app record
  4. Create the API key (App Manager role)
  5. Add the secrets and variables (with the exact `gh secret set` / `gh variable set` commands)
  6. Add her as an internal tester
  7. Run the workflow with `gh workflow run testflight.yml`
  8. She installs it from TestFlight and adds the widget

- [ ] **Step 1:** Write `SETUP.md` and the workflow. Validate the YAML with `gh workflow view testflight.yml` after pushing.
- [ ] **Step 2:** **Stop and hand off to the owner** to follow `SETUP.md`. Once the secrets exist, run `gh workflow run testflight.yml --ref feature/ios-port` and watch.
  Expected: the upload succeeds and the build appears in TestFlight. Phase 1 is done when she has installed it and checked a habit off from the home-screen widget.
- [ ] **Step 3:** Commit. `ci(ios): TestFlight delivery`.
