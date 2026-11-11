package org.isoron.uhabits.ioskit

import org.isoron.uhabits.core.models.Entry
import org.isoron.uhabits.core.models.Habit
import org.isoron.uhabits.core.models.HabitType
import org.isoron.uhabits.core.models.NumericalHabitType
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class EntryValuesTest {
    private val day = "2015-01-25"

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

    private fun cell(kit: LoopKit) = kit.listHabits(1, false)[0].days[0]

    @Test
    fun constants_matchEntry() {
        assertEquals(Entry.YES_MANUAL, ENTRY_YES)
        assertEquals(Entry.NO, ENTRY_NO)
        assertEquals(Entry.SKIP, ENTRY_SKIP)
        assertEquals(Entry.UNKNOWN, ENTRY_UNKNOWN)
    }

    @Test
    fun yesNo_allowedValuesRoundTrip() {
        val (kit, _) = testKit(Files.createTempDirectory("loopkit").toFile())
        val h = addHabit(kit)
        for (v in listOf(ENTRY_YES, ENTRY_NO, ENTRY_SKIP, ENTRY_UNKNOWN)) {
            kit.setEntry(h.id!!, day, v, "n$v")
            assertEquals(v, cell(kit).rawValue)
            assertEquals("n$v", cell(kit).notes)
        }
        kit.close()
    }

    @Test
    fun skipOnNumerical_isRaw3() {
        val (kit, _) = testKit(Files.createTempDirectory("loopkit").toFile())
        val h = addHabit(kit, numerical = true)
        kit.setEntry(h.id!!, day, ENTRY_SKIP, "")
        assertEquals(3, cell(kit).rawValue)
        kit.close()
    }

    @Test
    fun invalidValues_rejected() {
        val (kit, _) = testKit(Files.createTempDirectory("loopkit").toFile())
        val yn = addHabit(kit)
        assertFailsWith<IllegalArgumentException> { kit.setEntry(yn.id!!, day, Entry.YES_AUTO, "") }
        assertFailsWith<IllegalArgumentException> { kit.setEntry(yn.id!!, day, 42, "") }
        assertEquals(-1, cell(kit).rawValue)
        kit.close()
        val (kit2, _) = testKit(Files.createTempDirectory("loopkit").toFile())
        val num = addHabit(kit2, numerical = true)
        assertFailsWith<IllegalArgumentException> { kit2.setEntry(num.id!!, day, ENTRY_YES, "") }
        assertFailsWith<IllegalArgumentException> { kit2.setEntry(num.id!!, day, ENTRY_NO, "") }
        kit2.close()
    }

    @Test
    fun skipEntry_staysAfterSkipDisabled() {
        val (kit, _) = testKit(Files.createTempDirectory("loopkit").toFile())
        val h = addHabit(kit)
        kit.setSkipEnabled(true)
        kit.setEntry(h.id!!, day, ENTRY_SKIP, "")
        kit.setSkipEnabled(false)
        assertEquals(3, cell(kit).rawValue)
        kit.close()
    }
}
