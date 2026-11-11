# iOS port: handoff (2026-11-07)

Branch `feature/ios-port` on `ROODAY/uhabits` (forked from `dev`, not merged). Phases 0, 1 and 2 are done: the whole branch was reviewed and the review's fixes are in. CI was green at `752d0b95` after phase 1 and is green after the phase 2 dark mode pass (workflows `ios` and `android-core`).

- Design: `docs/superpowers/specs/2026-11-06-ios-port-design.md` (phases 0-4, process/lock model §6.3, reminders §6.4)
- Phase 2 design: `docs/superpowers/specs/2026-11-08-ios-phase-2-design.md`
- Phase 0-1 plan: `docs/superpowers/plans/2026-11-06-ios-port-phase-0-1.md`
- TestFlight setup: `ios/SETUP.md`

## What works now
- **Kotlin side:**
  - `uhabits-core` builds for iOS (sqlite cinterop).
  - The `uhabits-ios-kit` facade (`LoopKit`) is shipped as the static XCFramework `LoopKit`. Swift never computes habit logic.
- **App (SwiftUI):**
  - Habit list with check-off, plus long-press or number entry for measurable habits.
  - Create, edit and delete habits (yes/no and measurable, frequency, reminder).
  - Detail screen with an editable history grid, notes, and streaks.
  - Phase 2: categories (section headers, rename, set from edit/detail/list), archive/unarchive, select mode with bulk actions and drag reorder, sort and hide archived/completed from the ☰ menu, search, skip and "?" marks, a settings screen (first weekday, midnight delay, short toggle, question marks, skip, reverse checkmarks, reminder defaults, notification settings link), and dark mode.
- **Reminders:**
  - Local notifications with Done and Snooze (15 min) actions, capped at 60 pending.
  - Rescheduled on launch, on every change, on day change, by background refresh, and from widget/intent check-offs.
- **Widget:** an interactive check-off widget (pick a habit, tap to toggle) and App Shortcuts/Siri intents.
- **Shared data:** the app and widget share one SQLite DB in the App Group. The DB is closed whenever the app is not active, so iOS doesn't kill it (`0xdead10cc`).

## Next step 1: get it on her iPhone (owner only)
TestFlight now waits until phase 4 (backup/import) is done, so she gets export and import in the first build (spec §1). The steps below can be prepared earlier (Apple account, App IDs, secrets), but don't tag until then.

Follow `ios/SETUP.md` in order. In short:
1. Pick a prefix (e.g. `com.yourname.loop`).
2. On developer.apple.com:
   - Register the App Group `group.<prefix>`.
   - Register the App IDs `<prefix>.app` and `<prefix>.app.widgets`, both with App Groups enabled.
   - **Register her iPhone's UDID** (step 3b). Automatic signing fails without at least one device.
3. Create the app record in App Store Connect with bundle ID `<prefix>.app`.
4. Create an App Store Connect API key with the App Manager role, and download the `.p8`.
5. Set the GitHub secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `APPLE_TEAM_ID` and `ASC_KEY_P8` (base64 of the `.p8`). Set the variables `LOOP_BUNDLE_PREFIX` and `LOOP_APP_GROUP`. SETUP.md step 6 has the exact `gh` commands, including a PowerShell variant.
6. Add her as a TestFlight tester (internal tester if she's on your team, otherwise external, which needs beta review).
7. `git tag ios-v1 && git push origin ios-v1`, then `gh run watch -R ROODAY/uhabits`.
8. She installs the TestFlight app and accepts the invite. Builds expire after 90 days; push `ios-v2` and so on to refresh.

If the run fails, see the troubleshooting list in SETUP.md §10. The workflow uploads build logs as an artifact. The first real run is the first time signing and export are exercised, so expect one or two fix-ups there.

**Checks on her phone once installed** (CI can't verify these):
- Check something off, then immediately background the app. It should not crash or get killed, and reopening should show the change.
- Add the widget and check off from it. Open the app; the change should be there.
- Untick in the widget. Today's reminder should come back.
- Make sure the widget doesn't fail to load, which would point to the widget's memory limit (the Kotlin runtime is loaded in the widget).
- Reminders fire at the set time, and Done and Snooze work from the notification.
- A measurable weekly habit stops reminding once its weekly target is met.

Phase 2 checks (menus can't be opened in CI, so these have no screenshots):
- Drag-reorder across categories feels right: dropping under a header takes that category, dropping at the very top makes it uncategorized.
- The row context menu and the check-cell long-press don't conflict (long-press on a cell opens the entry sheet, long-press elsewhere on the row opens the menu).
- Long-pressing a category header opens Rename.
- The ☰ menu: hide archived, hide completed, and sort (the checkmark and ascending/descending arrow show the current choice).
- Settings "Notification settings" opens the iOS Settings page for the app.
- Dark mode on the phone: lists, detail, history grid, streaks and settings are all readable, and habit colors look right.
- Category suggestion chips tap correctly while the text field is focused.
- Select mode: search field behaviour (typing, clearing, and selecting while a search is active).

## Next step 2: the remaining phases (need a plan each)
Per the design doc. Start each one with brainstorming/writing-plans against the spec.
- **Phase 2: done.** Categories, archive/unarchive, reorder, sort, hide completed/archived, search, skip and "?" marks, settings, and dark mode.
- **Phase 3, charts and widgets:** calendar/heatmap grid, score, frequency and bar charts on the detail screen, plus the remaining widgets (history/progress, streak, score, multi-habit list).
- **Phase 4, backup/import:** export to CSV/DB and import a Loop DB.
  - Re-enable the iOS test exclusions in `uhabits-core/build.gradle.kts`: `*ZipTest`, `*HabitsCSVExporterTest`, `ListHabitsBehaviorTest.testOnExportCSV`, `ShowHabitMenuPresenterTest.testOnExport`.
  - Implement zip on iOS; the zip stubs currently throw "zip: phase 4".
  - `IosStrings` uses snprintf, which rounds half-even (the JVM rounds half-up) and truncates at 1024 bytes. Fix it before CSV output depends on it.

## Known limits and accepted minors
- The reminder horizon is 60 pending notifications, about 12 days of one daily reminder if the app is never opened.
- Targets are capped at 1e9 by validation.
- When an intent runs inside the app process, reminders get rescheduled twice. Harmless.
- Siri phrases for newly created habits may lag (no `updateAppShortcutParameters()`).
- The privacy manifests cover UserDefaults and file timestamps. If Apple emails about another required-reason API (e.g. system boot time from the Kotlin runtime), add it to both `PrivacyInfo.xcprivacy` files.

## Rules for whoever continues
- Swift never computes habit logic. Add a facade method in `uhabits-ios-kit` with `@Throws(Exception::class)` and a jvmTest.
- Any new DB access in the app must respect the close-when-inactive rule (`AppActivity.isForeground`, `closeStoreIfInactive`).
- Swift only compiles in CI (no Mac). Push and check the `ios` workflow, and look at the `screenshots` artifact for UI changes.
- Only the owner pushes `ios-v*` tags or runs `testflight.yml`.
- Commits are signed via 1Password, so it must be unlocked.
