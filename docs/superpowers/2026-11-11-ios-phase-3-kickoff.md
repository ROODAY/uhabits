# iOS port: phase 3 kickoff (2026-11-11)

A starting point for the agent that designs and builds phase 3 (charts and the remaining widgets). Read this, then the documents it points to. Nothing in phase 3 has been designed or built yet.

## Where things stand
- Branch `feature/ios-port` on `ROODAY/uhabits`. Phases 0, 1 and 2 are done. `dev` was fast-forwarded to `6ad70ade` (end of phase 2) and pushed. CI (`ios`, `android-core`) is green there.
- Overall state, what works, and the on-device checklist: `docs/superpowers/2026-11-07-ios-handoff.md`.
- Parent design (binding for all phases): `docs/superpowers/specs/2026-11-06-ios-port-design.md`. Phase 3 scope is in §2, the facade shape is in §6.2, widgets are in §6.3, and the calls made are in §10.
- Phase 2 design and plan, as examples of the expected format: `docs/superpowers/specs/2026-11-08-ios-phase-2-design.md`, `docs/superpowers/plans/2026-11-08-ios-phase-2.md`.

## Phase 3 scope (from the parent spec §2 and §6.3)
- **Detail screen cards:** overview, score over time, frequency by weekday, bar chart, target progress. History (an editable grid) and streaks already exist (`ios/App/HistoryEditorCard.swift`, `ios/App/StreaksCard.swift`).
- **Widgets:** history, score, frequency, streak and target. Each one shows one habit, picked the same way as the existing check-off widget (`AppIntentConfiguration`), in small and medium sizes. They carry over Android's choice of habit per widget, not its grid sizes. Android's stack widget and widget opacity are dropped (C6).
- **Charts** use SwiftUI or Swift Charts and draw exactly the series the facade returns. The builder picks Swift Charts or custom shapes per chart (§10).

## The owner's rules (carried over, confirm in brainstorming)
- In phase 2 the owner set this rule: **"match the Android experience, with iPhone-style interactions."** If unsure how something should behave, do what Android does (read the Android code). It is likely to apply to phase 3, but the owner has not confirmed it yet. Ask first.
- TestFlight, on-phone checks and fixes all wait until phase 4 is coded. The owner has no Mac. A phase is "done" when CI is green and the CI screenshots look right.
- Swift never computes habit logic. It does no bucketing, scoring, frequency counting or target math. The facade returns finished series.
- No changes to `uhabits-android`. Avoid `uhabits-core` changes. If one is unavoidable, Android's behavior must stay identical and `android-core` must stay green.

## The open question to settle first
Android's **score** and **bar** cards have an interval picker. Score offers day, week, month, quarter and year. Bar offers week, month, quarter and year, and for numerical habits also a sum/average choice. Both charts can be **dragged sideways to scroll back through history**. The frequency and history cards also scroll. This decides how much data the facade returns: a fixed window, or paged or offset queries. It also decides how much gesture handling Swift needs, so it shapes the facade API. A pending question to the owner: should phase 3 match Android here, including the interval picker and scrolling back, or something simpler?

Other things worth asking or deciding:
- Which widget families each new widget gets (small and medium per spec; lock-screen accessory "only if cheap" per C2).
- Whether the chosen interval should be saved. Android saves it per card in `Preferences`, as `scoreCardSpinnerPosition` and `barCardBoolSpinnerPosition` / `barCardNumericalSpinnerPosition`. Check the exact names in `uhabits-core/.../preferences/Preferences.kt`.
- The memory ceiling for widgets. The Kotlin/Native runtime already loads in the widget process. More widget kinds mean more timeline work, and the series sent to a widget must stay small.

## Where the logic already lives (wrap it, don't re-derive it)
Core card presenters are in `uhabits-core/src/commonMain/kotlin/org/isoron/uhabits/core/ui/screens/habits/show/views/`:
- `OverviewCard.kt`: `OverviewCardPresenter.buildState(habit, theme)` gives scoreToday, scoreMonthDiff, scoreYearDiff and totalCount.
- `ScoreCard.kt`: `ScoreCardPresenter.buildState(...)` uses `BUCKET_SIZES[spinnerPosition]` and `getTruncateField(bucketSize)` to produce `scores: List<Score>`.
- `BarCard.kt`: `BarCardPresenter.buildState(...)` gives `entries` grouped by bucket for boolean and numerical habits, plus the spinner positions.
- `FrequencyCard.kt`: `FrequencyCardPresenter.buildState(...)` gives `frequency: HashMap<LocalDate, Array<Int>>` (month → counts per weekday) and `firstWeekday`.
- `TargetCard.kt`: `TargetCardPresenter.buildState(...)` gives values, targets and intervals (for numerical habits).
- `HistoryCard.kt` and `StreakCart.kt` back the parts that already exist.

These presenters take a `Theme` and `PaletteColor`. The facade already maps palette colors to RGB (`palette(dark:)`). Look at how Android's `ShowHabitPresenter` / `ShowHabitActivity` wire them together (search `uhabits-android` and `uhabits-core` for `ScoreCardPresenter`). Android widgets live in `uhabits-android/src/main/java/org/isoron/uhabits/widgets/` (`ScoreWidget.kt`, `HistoryWidget.kt`, `FrequencyWidget.kt`, `StreakWidget.kt`, `TargetWidget.kt`). They reuse the same card presenters.

The facade: `uhabits-ios-kit/src/commonMain/kotlin/org/isoron/uhabits/ioskit/`. `LoopKit.kt` holds the lifecycle and public methods. `LoopKit.habitDetail(habitId, historyDays)` and `HabitDetail` in `Dtos.kt` are what the detail screen uses today. Phase 2 put list logic in `LoopKitList.kt` and settings in `LoopKitSettings.kt`. A `LoopKitCharts.kt` would follow that pattern.

## Lessons from phases 1-2 (save time)
- **Process that worked:** brainstorm, then a spec in `docs/superpowers/specs/`, then a plan in `docs/superpowers/plans/`, then subagent-driven execution. Each task gets an implementer and a task reviewer. A final whole-branch review and one fix wave finish the phase. Per the owner's global CLAUDE.md, every subagent runs on `model: "sonnet"`. Kotlin tasks first (JVM tests on Windows), then Swift tasks, each pushed and CI-checked before the next is stacked on it.
- **Kotlin to Swift interop gotchas** that caused CI failures before:
  - Top-level Kotlin consts are reached as `LoopKitKt.X` / `LoopKitListKt.X`.
  - `List<Long>` parameters need `[KotlinLong(value:)]` boxing.
  - Kotlin `Int` is `Int32`.
  - `@Throws` methods need `try`.
  - Labels follow Kotlin parameter names.
  - XCTest calls to `@MainActor` statics fail unless they're `nonisolated`.
  - Adding a case to a shared Swift enum (`ListSheet`) breaks `switch`es in other files.
- **Binding app rules:**
  - All DB access goes through `LoopStore`: `withKit` for reads, `mutate` for writes, so reminders get rescheduled and widgets reloaded.
  - Every new read path must close the store when the app isn't active, following the pattern in `HabitListModel.mutate` / `HabitDetailView` / `SettingsView` (`isActive` closures). Reviewers flagged this three times in phase 2.
- **CI:**
  - Swift only compiles in CI (`gh run watch <id> -R ROODAY/uhabits --exit-status`). macOS runners sometimes queue for over an hour.
  - Screenshots come from `--screen <name>` launch args in `ios/App/LoopApp.swift` / `HabitListView.swift`, plus steps in `.github/workflows/ios.yml`. Read them from the `screenshots` artifact.
  - The demo seed (`ios/App/DemoSeed.swift`, `--seed-demo`) needs enough history for charts to look real.
  - SwiftUI menus can't be opened in CI, so menu states go on the on-device checklist.
  - Widget screenshots already exist (`widget*.png`). Check how they're produced before adding new ones.
- **Never** push `ios-v*` tags or run `testflight.yml`. Commit signing goes through 1Password. If it's locked, follow the owner's CLAUDE.md: retry once, then commit unsigned and don't push.

## Suggested first step
Invoke `superpowers:brainstorming` for phase 3. Ask the owner the interval-picker and scrolling question above first, then widget families. Write `docs/superpowers/specs/2026-11-1x-ios-phase-3-design.md`. After the owner approves it, write the plan and execute it with subagent-driven development.
