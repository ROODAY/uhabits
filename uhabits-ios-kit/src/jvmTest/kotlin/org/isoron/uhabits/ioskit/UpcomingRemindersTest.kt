package org.isoron.uhabits.ioskit

import org.isoron.platform.time.LocalDate
import java.io.File
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class UpcomingRemindersTest {
    private val today = LocalDate(2015, 1, 25) // a Sunday
    private val todayIso = today.iso()

    private fun tmp(): File = Files.createTempDirectory("loopkit").toFile()

    private fun input(
        name: String = "Run",
        hour: Int = 9,
        minute: Int = 0,
        days: List<Boolean> = List(7) { true },
        numerical: Boolean = false,
        targetType: Int = 0,
        withReminder: Boolean = true
    ) = HabitInput(
        name = name, question = "Did $name?", description = "", colorIndex = 3,
        isNumerical = numerical, unit = if (numerical) "x" else "", targetValue = if (numerical) 5.0 else 0.0,
        targetType = targetType, freqNumerator = 1, freqDenominator = 1,
        reminder = if (withReminder) ReminderDto(hour, minute, days) else null
    )

    @Test
    fun excludesTodayIfTimePassed() {
        val (kit, _) = testKit(tmp(), today)
        kit.createHabit(input(hour = 9))
        val r = kit.upcomingReminders(todayIso, 9 * 60, 2, 10)
        assertEquals(listOf("2015-01-26"), r.map { it.date })
        kit.close()
    }

    @Test
    fun includesTodayIfTimeAhead() {
        val (kit, _) = testKit(tmp(), today)
        val id = kit.createHabit(input(hour = 9))
        val r = kit.upcomingReminders(todayIso, 9 * 60 - 1, 2, 10)
        assertEquals(listOf("2015-01-25", "2015-01-26"), r.map { it.date })
        assertEquals(ReminderOccurrence(id, "Run", "Did Run?", false, "2015-01-25", 9, 0), r[0])
        kit.close()
    }

    @Test
    fun respectsReminderDays() {
        val (kit, _) = testKit(tmp(), today)
        // index 0 = Sunday ... 6 = Saturday; only Sunday and Wednesday
        kit.createHabit(input(days = listOf(true, false, false, true, false, false, false)))
        val r = kit.upcomingReminders(todayIso, 0, 7, 10)
        assertEquals(listOf("2015-01-25", "2015-01-28"), r.map { it.date })
        kit.close()
    }

    @Test
    fun skipsDayAlreadyCompleted_yesNo() {
        val (kit, _) = testKit(tmp(), today)
        val id = kit.createHabit(input())
        kit.markDone(id, "2015-01-26")
        val r = kit.upcomingReminders(todayIso, 0, 3, 10)
        assertEquals(listOf("2015-01-25", "2015-01-27"), r.map { it.date })
        kit.close()
    }

    @Test
    fun atMostHabit_includedEvenIfCompleted() {
        val (kit, _) = testKit(tmp(), today)
        val id = kit.createHabit(input(numerical = true, targetType = 1))
        kit.setNumber(id, todayIso, 2.0, "")
        assertTrue(kit.habitDetail(id, 1)!!.row.isCompletedToday)
        val r = kit.upcomingReminders(todayIso, 0, 1, 10)
        assertEquals(listOf(todayIso), r.map { it.date })
        kit.close()
    }

    @Test
    fun excludesArchived() {
        val (kit, _) = testKit(tmp(), today)
        val id = kit.createHabit(input())
        val h = kit.habitList.getById(id)!!
        h.isArchived = true
        kit.habitList.update(h)
        assertEquals(emptyList(), kit.upcomingReminders(todayIso, 0, 3, 10))
        kit.close()
    }

    @Test
    fun truncatesChronologically() {
        val (kit, _) = testKit(tmp(), today)
        kit.createHabit(input(name = "A", hour = 8))
        kit.createHabit(input(name = "B", hour = 9))
        kit.createHabit(input(name = "C", hour = 10))
        val r = kit.upcomingReminders(todayIso, 0, 30, 60)
        assertEquals(60, r.size)
        assertEquals(today.plus(19).iso(), r.last().date)
        kit.close()
    }

    @Test
    fun sortedByDateThenTime() {
        val (kit, _) = testKit(tmp(), today)
        kit.createHabit(input(name = "Late", hour = 20, minute = 30))
        kit.createHabit(input(name = "Early", hour = 7, minute = 15))
        val r = kit.upcomingReminders(todayIso, 0, 2, 10)
        assertEquals(
            listOf("2015-01-25 07:15", "2015-01-25 20:30", "2015-01-26 07:15", "2015-01-26 20:30"),
            r.map { "${it.date} %02d:%02d".format(it.hour, it.minute) }
        )
        kit.close()
    }

    @Test
    fun midnightDelay_usesPreviousHabitDayForEarlyReminder() {
        val (kit, _) = testKit(tmp(), today)
        kit.prefs.isMidnightDelayEnabled = true // 3h
        val id = kit.createHabit(input(hour = 1))
        kit.markDone(id, "2015-01-25")
        val r = kit.upcomingReminders("2015-01-26", 0, 2, 10)
        assertEquals(listOf("2015-01-27"), r.map { it.date })
        kit.close()
    }

    @Test
    fun nonPositiveHorizonOrMaxCount_returnsEmpty() {
        val (kit, _) = testKit(tmp(), today)
        kit.createHabit(input())
        assertEquals(emptyList(), kit.upcomingReminders(todayIso, 0, 0, 10))
        assertEquals(emptyList(), kit.upcomingReminders(todayIso, 0, 5, 0))
        assertFailsWith<IllegalArgumentException> { kit.upcomingReminders(todayIso, 1440, 5, 5) }
        kit.close()
    }

    private fun periodInput(numerical: Boolean, num: Int, den: Int) = HabitInput(
        name = "P", question = "Did P?", description = "", colorIndex = 3,
        isNumerical = numerical, unit = if (numerical) "km" else "", targetValue = if (numerical) 20.0 else 0.0,
        targetType = 0, freqNumerator = num, freqDenominator = den,
        reminder = ReminderDto(9, 0, List(7) { true })
    )

    @Test
    fun weeklyNumerical_metEarlierInPeriod_suppressesRestOfPeriodOnly() {
        val wednesday = LocalDate(2015, 1, 28)
        val (kit, _) = testKit(tmp(), wednesday)
        val id = kit.createHabit(periodInput(numerical = true, num = 1, den = 7))
        val before = kit.upcomingReminders("2015-01-28", 0, 7, 20).map { it.date }
        assertTrue("2015-01-29" in before && "2015-01-31" in before)

        kit.setNumber(id, "2015-01-28", 20.0, "")
        val after = kit.upcomingReminders("2015-01-28", 0, 7, 20).map { it.date }
        // Rest of the current week is suppressed; the next week (starts Feb 1 or Feb 2) is not.
        assertTrue(after.none { it < "2015-02-01" }, "got $after")
        assertTrue("2015-02-02" in after && "2015-02-03" in after, "got $after")
        kit.close()
    }

    @Test
    fun weeklyNumerical_notMet_keepsReminders() {
        val (kit, _) = testKit(tmp(), LocalDate(2015, 1, 28))
        val id = kit.createHabit(periodInput(numerical = true, num = 1, den = 7))
        kit.setNumber(id, "2015-01-28", 5.0, "")
        val dates = kit.upcomingReminders("2015-01-28", 0, 4, 20).map { it.date }
        assertEquals(listOf("2015-01-28", "2015-01-29", "2015-01-30", "2015-01-31"), dates)
        kit.close()
    }

    @Test
    fun threePerWeekYesNo_metEarlierInPeriod_suppressesFollowingDays() {
        val (kit, _) = testKit(tmp(), LocalDate(2015, 1, 28))
        val id = kit.createHabit(periodInput(numerical = false, num = 3, den = 7))
        val before = kit.upcomingReminders("2015-01-28", 0, 4, 20).map { it.date }
        assertTrue("2015-01-29" in before && "2015-01-30" in before)
        for (d in listOf("2015-01-26", "2015-01-27", "2015-01-28")) kit.markDone(id, d)
        val after = kit.upcomingReminders("2015-01-28", 0, 4, 20).map { it.date }
        assertTrue("2015-01-29" !in after && "2015-01-30" !in after, "got $after")
        kit.close()
    }
}
