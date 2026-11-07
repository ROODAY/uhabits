package org.isoron.uhabits.ioskit

import org.isoron.platform.time.LocalDate
import org.isoron.uhabits.core.models.Entry
import org.isoron.uhabits.core.models.Habit
import org.isoron.uhabits.core.models.HabitType
import org.isoron.uhabits.core.models.NumericalHabitType
import java.io.File
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class EntryMutationsTest {
    private val day = "2015-01-25"
    private val date = LocalDate(2015, 1, 25)

    private fun tmp(): File = Files.createTempDirectory("loopkit").toFile()

    private fun addHabit(kit: LoopKit, numerical: Boolean = false): Habit {
        val h = kit.modelFactory.buildHabit()
        h.name = "Habit"
        if (numerical) {
            h.type = HabitType.NUMERICAL
            h.targetType = NumericalHabitType.AT_LEAST
            h.targetValue = 2.0
        }
        kit.today()
        kit.habitList.add(h)
        return h
    }

    private fun raw(kit: LoopKit, h: Habit): Int {
        kit.today()
        return h.originalEntries.get(date).value
    }

    @Test
    fun toggle_cyclesYesThenNo() {
        val (kit, _) = testKit(tmp())
        val h = addHabit(kit)
        assertEquals(Entry.UNKNOWN, raw(kit, h))
        kit.toggle(h.id!!, day)
        assertEquals(Entry.YES_MANUAL, raw(kit, h))
        kit.toggle(h.id!!, day)
        assertEquals(Entry.NO, raw(kit, h))
        kit.close()
    }

    @Test
    fun toggle_withSkipEnabled_goesToSkip() {
        val (kit, _) = testKit(tmp())
        val h = addHabit(kit)
        kit.prefs.isSkipEnabled = true
        kit.toggle(h.id!!, day)
        kit.toggle(h.id!!, day)
        assertEquals(Entry.SKIP, raw(kit, h))
        kit.close()
    }

    @Test
    fun markDone_setsYesManual() {
        val (kit, _) = testKit(tmp())
        val h = addHabit(kit)
        kit.markDone(h.id!!, day)
        assertEquals(Entry.YES_MANUAL, raw(kit, h))
        kit.close()
    }

    @Test
    fun increment_addsExactlyOneUnit() {
        val (kit, _) = testKit(tmp())
        val h = addHabit(kit, numerical = true)
        kit.setNumber(h.id!!, day, 2.5, "")
        kit.increment(h.id!!, day)
        assertEquals(3500, raw(kit, h))
        kit.decrement(h.id!!, day)
        assertEquals(2500, raw(kit, h))
        kit.close()
    }

    @Test
    fun setNumber_roundTripsFractions() {
        val (kit, _) = testKit(tmp())
        val h = addHabit(kit, numerical = true)
        for (v in listOf(0.1, 2.5, 1234.567)) {
            kit.setNumber(h.id!!, day, v, "n")
            val cell = kit.listHabits(1, false)[0].days[0]
            assertEquals(v, cell.value)
            assertEquals("n", cell.notes)
        }
        kit.close()
    }

    @Test
    fun setNotes_keepsValue() {
        val (kit, _) = testKit(tmp())
        val h = addHabit(kit)
        kit.markDone(h.id!!, day)
        kit.setNotes(h.id!!, day, "hello")
        assertEquals(Entry.YES_MANUAL, raw(kit, h))
        assertEquals("hello", h.originalEntries.get(date).notes)
        kit.toggle(h.id!!, day)
        assertEquals("hello", h.originalEntries.get(date).notes)
        kit.close()
    }

    @Test
    fun mutation_unknownHabit_noop() {
        val (kit, _) = testKit(tmp())
        val h = addHabit(kit)
        kit.toggle(999, day)
        kit.markDone(999, day)
        kit.increment(999, day)
        kit.decrement(999, day)
        kit.setNumber(999, day, 1.0, "")
        kit.setNotes(999, day, "x")
        assertEquals(Entry.UNKNOWN, raw(kit, h))
        kit.close()
    }

    @Test
    fun mutation_typeMismatch_noop() {
        val (kit, _) = testKit(tmp())
        val yn = addHabit(kit)
        val num = addHabit(kit, numerical = true)
        kit.setNumber(yn.id!!, day, 3.0, "")
        kit.increment(yn.id!!, day)
        kit.decrement(yn.id!!, day)
        kit.toggle(num.id!!, day)
        assertEquals(Entry.UNKNOWN, raw(kit, yn))
        assertEquals(0, maxOf(raw(kit, num), 0))
        assertTrue(num.originalEntries.get(date).value < 0)
        kit.close()
    }

    @Test
    fun mutation_malformedDate_throws() {
        val (kit, _) = testKit(tmp())
        val h = addHabit(kit)
        assertFailsWith<IllegalArgumentException> { kit.toggle(h.id!!, "2015-02-31") }
        kit.close()
    }

    @Test
    fun mutation_updatesStreakImmediately() {
        val (kit, _) = testKit(tmp())
        val h = addHabit(kit)
        kit.markDone(h.id!!, day)
        assertTrue(kit.listHabits(1, false)[0].isCompletedToday)
        kit.close()
    }

    @Test
    fun parseIso_rejectsImpossibleDate() {
        assertFailsWith<IllegalArgumentException> { parseIso("2015-02-31") }
        assertFailsWith<IllegalArgumentException> { parseIso("2015-13-01") }
        assertEquals(LocalDate(2024, 2, 29), parseIso("2024-02-29"))
    }
}
