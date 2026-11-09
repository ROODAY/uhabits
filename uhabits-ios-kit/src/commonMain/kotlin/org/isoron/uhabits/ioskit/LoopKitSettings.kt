package org.isoron.uhabits.ioskit

import org.isoron.uhabits.core.preferences.Preferences

private const val KEY_SHORT_TOGGLE = "pref_short_toggle"
private const val KEY_FIRST_WEEKDAY = "pref_first_weekday"

internal fun readSettings(prefs: Preferences, store: KeyValueStore): AppSettings {
    val choice = store.getString(KEY_FIRST_WEEKDAY)?.toIntOrNull()?.takeIf { it == -1 || it in 1..7 } ?: -1
    return AppSettings(
        // Unlike Android's default (false), an unset short toggle reads as true on iOS.
        shortToggle = if (store.getString(KEY_SHORT_TOGGLE) == null) true else prefs.isShortToggleEnabled,
        midnightDelay = prefs.isMidnightDelayEnabled,
        skipEnabled = prefs.isSkipEnabled,
        questionMarksEnabled = prefs.areQuestionMarksEnabled,
        reverseCheckmarks = prefs.isCheckmarkSequenceReversed,
        firstWeekdayChoice = choice,
        resolvedFirstWeekday = prefs.firstWeekday.daysSinceSunday + 1
    )
}

internal fun writeFirstWeekday(store: KeyValueStore, choice: Int) {
    require(choice == -1 || choice in 1..7) { "first weekday choice must be -1 or 1..7" }
    store.putString(KEY_FIRST_WEEKDAY, choice.toString())
}
