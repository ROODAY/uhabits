package org.isoron.uhabits.ioskit

import org.isoron.uhabits.core.models.Entry
import java.io.File
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

class HabitCrudTest {
    private fun tmp(): File = Files.createTempDirectory("loopkit").toFile()

    private fun input(
        name: String = "Run",
        numerical: Boolean = false,
        reminder: ReminderDto? = null,
        num: Int = 1,
        den: Int = 1
    ) = HabitInput(
        name = name, question = "Did you run?", description = "notes", colorIndex = 5,
        isNumerical = numerical, unit = "km", targetValue = 3.5, targetType = 1,
        freqNumerator = num, freqDenominator = den, reminder = reminder, category = ""
    )

    @Test
    fun create_thenListed() {
        val (kit, _) = testKit(tmp())
        val id = kit.createHabit(input())
        val rows = kit.listHabits(0, false)
        assertEquals(1, rows.size)
        assertEquals(id, rows[0].id)
        assertEquals("Run", rows[0].name)
        assertEquals(5, rows[0].colorIndex)
        val i = kit.habitInput(id)!!
        assertEquals("Did you run?", i.question)
        assertEquals("notes", i.description)
        assertEquals(1, i.freqNumerator)
        assertEquals(1, i.freqDenominator)
        kit.close()
    }

    @Test
    fun create_numericalFieldsRoundTrip() {
        val (kit, _) = testKit(tmp())
        val id = kit.createHabit(input(numerical = true, num = 2, den = 7))
        val i = kit.habitInput(id)!!
        assertTrue(i.isNumerical)
        assertEquals("km", i.unit)
        assertEquals(3.5, i.targetValue)
        assertEquals(1, i.targetType)
        assertEquals(2, i.freqNumerator)
        assertEquals(7, i.freqDenominator)
        kit.close()
    }

    @Test
    fun create_yesNo_storesNeutralNumericFields() {
        val (kit, _) = testKit(tmp())
        val id = kit.createHabit(input())
        val i = kit.habitInput(id)!!
        assertEquals("", i.unit)
        assertEquals(0.0, i.targetValue)
        assertEquals(0, i.targetType)
        kit.close()
    }

    @Test
    fun edit_changesNameKeepsEntries() {
        val (kit, _) = testKit(tmp())
        val id = kit.createHabit(input())
        kit.markDone(id, "2015-01-25")
        kit.editHabit(id, input(name = "Jog"))
        val row = kit.listHabits(1, false)[0]
        assertEquals("Jog", row.name)
        assertEquals(Entry.YES_MANUAL, row.days[0].rawValue)
        kit.close()
    }

    @Test
    fun edit_typeChange_throws() {
        val (kit, _) = testKit(tmp())
        val id = kit.createHabit(input())
        val e = assertFailsWith<IllegalArgumentException> { kit.editHabit(id, input(numerical = true)) }
        assertEquals("habit type cannot change", e.message)
        kit.close()
    }

    @Test
    fun edit_unknownId_noop() {
        val (kit, _) = testKit(tmp())
        kit.editHabit(999, input())
        assertEquals(0, kit.listHabits(0, true).size)
        kit.close()
    }

    @Test
    fun delete_removes() {
        val (kit, _) = testKit(tmp())
        val id = kit.createHabit(input())
        val other = kit.createHabit(input(name = "Other"))
        kit.deleteHabit(id)
        kit.deleteHabit(id)
        kit.deleteHabit(12345)
        val rows = kit.listHabits(0, true)
        assertEquals(listOf(other), rows.map { it.id })
        assertNull(kit.habitInput(id))
        kit.close()
    }

    @Test
    fun habitInput_unknownId_null() {
        val (kit, _) = testKit(tmp())
        assertNull(kit.habitInput(42))
        kit.close()
    }

    @Test
    fun reminderDays_sundayMapsToCorePackedIndex1() {
        val (kit, _) = testKit(tmp())
        val days = listOf(true, false, false, false, false, false, false)
        val id = kit.createHabit(input(reminder = ReminderDto(8, 30, days)))
        val core = kit.habitList.getById(id)!!.reminder!!
        val arr = core.days.toArray()
        assertTrue(arr[1])
        assertEquals(1, arr.count { it })
        val r = kit.habitInput(id)!!.reminder!!
        assertEquals(8, r.hour)
        assertEquals(30, r.minute)
        assertEquals(days, r.days)
        kit.close()
    }

    @Test
    fun reminderDto_badDays_throws() {
        assertFailsWith<IllegalArgumentException> { ReminderDto(8, 0, listOf(true, false)) }
        assertFailsWith<IllegalArgumentException> { ReminderDto(24, 0, List(7) { true }) }
        assertFailsWith<IllegalArgumentException> { ReminderDto(8, 60, List(7) { true }) }
    }

    @Test
    fun create_blankName_throws() {
        val (kit, _) = testKit(tmp())
        assertFailsWith<IllegalArgumentException> { kit.createHabit(input(name = "  ")) }
        assertEquals(0, kit.listHabits(0, true).size)
        kit.close()
    }

    @Test
    fun create_badFrequency_throws() {
        val (kit, _) = testKit(tmp())
        assertFailsWith<IllegalArgumentException> { kit.createHabit(input(num = 0, den = 1)) }
        assertFailsWith<IllegalArgumentException> { kit.createHabit(input(num = 3, den = 2)) }
        assertFailsWith<IllegalArgumentException> { kit.createHabit(input(numerical = true).copy(targetValue = -1.0)) }
        assertFailsWith<IllegalArgumentException> { kit.createHabit(input().copy(colorIndex = 20)) }
        kit.close()
    }

    @Test
    fun create_nonFiniteOrHugeTarget_throws() {
        val (kit, _) = testKit(tmp())
        for (bad in listOf(Double.POSITIVE_INFINITY, Double.NaN, 1e30, 1e9 + 1)) {
            assertFailsWith<IllegalArgumentException> { kit.createHabit(input(numerical = true).copy(targetValue = bad)) }
        }
        val id = kit.createHabit(input(numerical = true).copy(targetValue = 1e9))
        assertFailsWith<IllegalArgumentException> {
            kit.editHabit(id, input(numerical = true).copy(targetValue = Double.POSITIVE_INFINITY))
        }
        assertEquals(1e9, kit.habitInput(id)!!.targetValue)
        kit.close()
    }
}
