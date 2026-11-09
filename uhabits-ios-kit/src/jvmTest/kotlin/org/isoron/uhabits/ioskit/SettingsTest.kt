package org.isoron.uhabits.ioskit

import org.isoron.platform.time.LocalDate
import org.isoron.platform.time.resetFirstWeekday
import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SettingsTest {
    private fun tmp(): File = Files.createTempDirectory("loopkit").toFile()

    // First weekday is process-global state in the core; restore it for other test classes.
    @AfterTest
    fun restoreFirstWeekday() = resetFirstWeekday()

    @Test
    fun defaults_matchAndroidExceptShortToggle() {
        val (kit, _) = testKit(tmp())
        val s = kit.settings()
        assertTrue(s.shortToggle)
        assertFalse(s.midnightDelay)
        assertFalse(s.skipEnabled)
        assertFalse(s.questionMarksEnabled)
        assertFalse(s.reverseCheckmarks)
        assertEquals(-1, s.firstWeekdayChoice)
        assertTrue(s.resolvedFirstWeekday in 1..7)
        kit.close()
    }

    @Test
    fun shortToggle_explicitFalsePersists() {
        val (kit, store) = testKit(tmp())
        kit.setShortToggle(false)
        assertEquals("false", store.map["pref_short_toggle"])
        kit.reload()
        assertFalse(kit.settings().shortToggle)
        kit.close()
    }

    @Test
    fun setters_writeAndroidKeys() {
        val (kit, store) = testKit(tmp())
        kit.setMidnightDelay(true)
        kit.setSkipEnabled(true)
        kit.setQuestionMarksEnabled(true)
        kit.setReverseCheckmarks(true)
        kit.setFirstWeekday(2)
        assertEquals("true", store.map["pref_midnight_delay"])
        assertEquals("true", store.map["pref_skip_enabled"])
        assertEquals("true", store.map["pref_unknown_enabled"])
        assertEquals("true", store.map["pref_checkmark_reverse_order"])
        assertEquals("2", store.map["pref_first_weekday"])
        kit.reload()
        val s = kit.settings()
        assertTrue(s.midnightDelay)
        assertTrue(s.skipEnabled)
        assertTrue(s.questionMarksEnabled)
        assertTrue(s.reverseCheckmarks)
        assertEquals(2, s.firstWeekdayChoice)
        assertEquals(2, s.resolvedFirstWeekday)
        kit.close()
    }

    @Test
    fun midnightDelay_changesToday() {
        val dir = tmp()
        val kit = LoopKit(
            org.isoron.platform.io.JavaDatabaseOpener(),
            org.isoron.platform.io.JavaFileOpener(),
            File(dir, "loop.db").absolutePath,
            MapStore(),
            TodaySource { delay -> if (delay > 0) LocalDate(2015, 1, 24) else LocalDate(2015, 1, 25) }
        )
        assertEquals("2015-01-25", kit.today())
        kit.setMidnightDelay(true)
        assertEquals("2015-01-24", kit.today())
        kit.close()
    }

    @Test
    fun firstWeekday_drivesWeeklyPeriod() {
        val (kit, _) = testKit(tmp())
        val id = kit.createHabit(
            HabitInput(
                name = "Run", question = "", description = "", colorIndex = 1,
                isNumerical = true, unit = "km", targetValue = 3.0, targetType = 0, // AT_LEAST,
                freqNumerator = 1, freqDenominator = 7, reminder = null, category = ""
            )
        )
        kit.setNumber(id, "2015-01-24", 3.0, "")
        kit.setFirstWeekday(1)
        assertFalse(kit.listHabits(1, false)[0].isCompletedToday)
        kit.setFirstWeekday(2)
        assertTrue(kit.listHabits(1, false)[0].isCompletedToday)
        kit.close()
    }

    @Test
    fun setFirstWeekday_rejectsOutOfRange() {
        val (kit, _) = testKit(tmp())
        assertFailsWith<IllegalArgumentException> { kit.setFirstWeekday(0) }
        assertFailsWith<IllegalArgumentException> { kit.setFirstWeekday(8) }
        kit.close()
    }

    @Test
    fun toggle_cyclesThroughSkipAndUnknown() {
        val (kit, _) = testKit(tmp())
        kit.setSkipEnabled(true)
        kit.setQuestionMarksEnabled(true)
        val id = kit.createHabit(
            HabitInput(
                name = "Read", question = "", description = "", colorIndex = 1,
                isNumerical = false, unit = "", targetValue = 0.0, targetType = 0,
                freqNumerator = 1, freqDenominator = 1, reminder = null, category = ""
            )
        )
        val seen = (1..4).map {
            kit.toggle(id, "2015-01-25")
            kit.listHabits(1, false)[0].days[0].rawValue
        }
        assertEquals(listOf(2, 3, 0, -1), seen)
        kit.close()
    }
}
