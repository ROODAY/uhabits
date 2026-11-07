package org.isoron.uhabits.ioskit

import org.isoron.platform.time.LocalDate
import org.isoron.uhabits.core.models.Entry
import org.isoron.uhabits.core.models.Habit
import org.isoron.uhabits.core.models.NumericalHabitType
import java.io.File
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ListHabitsTest {
    private fun tmp(): File = Files.createTempDirectory("loopkit").toFile()

    private fun addHabit(kit: LoopKit, configure: Habit.() -> Unit = {}): Habit {
        val h = kit.modelFactory.buildHabit()
        h.name = "Habit"
        h.configure()
        kit.today() // sets the global today needed by recompute()
        kit.habitList.add(h)
        return h
    }

    private fun Habit.put(date: LocalDate, value: Int, notes: String = "") {
        originalEntries.add(Entry(date, value, notes))
        recompute()
    }

    @Test
    fun listHabits_returnsDaysNewestFirst() {
        val (kit, _) = testKit(tmp())
        val h = addHabit(kit) { name = "Run" }
        h.put(LocalDate(2015, 1, 25), Entry.YES_MANUAL, "good")
        h.put(LocalDate(2015, 1, 23), Entry.YES_MANUAL)
        val row = kit.listHabits(5, false)[0]
        assertEquals("Run", row.name)
        assertEquals("2015-01-25", row.today)
        assertEquals(5, row.days.size)
        assertEquals("2015-01-25", row.days[0].date)
        assertEquals(2, row.days[0].rawValue)
        assertTrue(row.days[0].isCompleted)
        assertEquals(1.0, row.days[0].value)
        assertEquals("good", row.days[0].notes)
        assertEquals("2015-01-24", row.days[1].date)
        assertFalse(row.days[1].isCompleted)
        assertTrue(row.isCompletedToday)
        kit.close()
    }

    @Test
    fun listHabits_numericalValueScaled() {
        val (kit, _) = testKit(tmp())
        val h = addHabit(kit) {
            type = org.isoron.uhabits.core.models.HabitType.NUMERICAL
            targetType = NumericalHabitType.AT_LEAST
            targetValue = 2.0
            unit = "glasses"
        }
        h.put(LocalDate(2015, 1, 25), 2500)
        val row = kit.listHabits(2, false)[0]
        assertTrue(row.isNumerical)
        assertEquals(2500, row.days[0].rawValue)
        assertEquals(2.5, row.days[0].value)
        assertEquals("glasses", row.unit)
        assertEquals(0.0, row.days[1].value)
        kit.close()
    }

    @Test
    fun listHabits_excludesArchivedUnlessAsked() {
        val (kit, _) = testKit(tmp())
        addHabit(kit) { name = "A" }
        addHabit(kit) {
            name = "B"
            isArchived = true
        }
        assertEquals(listOf("A"), kit.listHabits(1, false).map { it.name })
        assertEquals(listOf("A", "B"), kit.listHabits(1, true).map { it.name })
        kit.close()
    }

    @Test
    fun listHabits_nonPositiveDayCountGivesEmptyDays() {
        val (kit, _) = testKit(tmp())
        addHabit(kit)
        assertTrue(kit.listHabits(0, false)[0].days.isEmpty())
        assertTrue(kit.listHabits(-3, false)[0].days.isEmpty())
        kit.close()
    }

    @Test
    fun listHabits_reflectsNewTodayAfterRollover() {
        var now = LocalDate(2015, 1, 25)
        val kit = LoopKit(
            org.isoron.platform.io.JavaDatabaseOpener(),
            org.isoron.platform.io.JavaFileOpener(),
            File(tmp(), "loop.db").absolutePath,
            MapStore(),
            TodaySource { now }
        )
        addHabit(kit)
        assertEquals("2015-01-25", kit.listHabits(3, false)[0].today)
        now = LocalDate(2015, 1, 26)
        val row = kit.listHabits(3, false)[0]
        assertEquals("2015-01-26", row.today)
        assertEquals("2015-01-26", row.days[0].date)
        assertEquals("2015-01-26", kit.today())
        kit.close()
    }

    @Test
    fun palette_hasTwentyColors_firstIsRed() {
        val (kit, _) = testKit(tmp())
        assertEquals(20, kit.palette(false).size)
        assertEquals(20, kit.palette(true).size)
        assertEquals(0xD32F2F, kit.palette(false)[0])
        kit.close()
    }

    @Test
    fun iso_roundTrips() {
        for (d in listOf(LocalDate(2000, 1, 1), LocalDate(2015, 1, 25), LocalDate(2024, 2, 29))) {
            assertEquals(d, parseIso(d.iso()))
        }
        assertEquals("2000-01-01", LocalDate(2000, 1, 1).iso())
    }

    @Test
    fun afterClose_listHabitsThrows() {
        val (kit, _) = testKit(tmp())
        kit.close()
        val e = assertFailsWith<IllegalStateException> { kit.listHabits(1, false) }
        assertEquals("LoopKit is closed", e.message)
        assertFailsWith<IllegalStateException> { kit.today() }
    }

    @Test
    fun reloadAfterClose_works() {
        val (kit, _) = testKit(tmp())
        addHabit(kit)
        kit.close()
        kit.reload()
        assertEquals(1, kit.listHabits(1, false).size)
        kit.close()
    }
}
