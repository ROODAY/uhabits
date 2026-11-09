package org.isoron.uhabits.ioskit

import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

class HabitActionsTest {
    private fun input(name: String, category: String = "") = HabitInput(
        name = name, question = "", description = "", colorIndex = 5,
        isNumerical = false, unit = "", targetValue = 0.0, targetType = 0,
        freqNumerator = 1, freqDenominator = 1, reminder = null, category = category
    )

    private fun newKit(): LoopKit = testKit(Files.createTempDirectory("loopkit").toFile()).first

    private fun keys(kit: LoopKit) = kit.listRows(1, "").map { it.key }

    @Test
    fun archiveUnarchive_roundTrip() {
        val kit = newKit()
        val a = kit.createHabit(input("A"))
        val b = kit.createHabit(input("B"))
        kit.setHideArchived(false)
        kit.archive(listOf(a, b))
        assertEquals(listOf(true, true), kit.listRows(1, "").map { it.habit!!.isArchived })
        kit.unarchive(listOf(a))
        val m = kit.listRows(1, "").associate { it.habit!!.id to it.habit.isArchived }
        assertEquals(false, m[a]); assertEquals(true, m[b])
        kit.close()
    }

    @Test
    fun setCategory_movesUnderHeader() {
        val kit = newKit()
        val a = kit.createHabit(input("A"))
        val b = kit.createHabit(input("B"))
        kit.setCategory(listOf(a), "  Gym ")
        assertEquals(listOf("h:$b", "c:Gym", "h:$a"), keys(kit))
        kit.close()
    }

    @Test
    fun setColor_rejectsOutOfRange() {
        val kit = newKit()
        val a = kit.createHabit(input("A"))
        assertFailsWith<IllegalArgumentException> { kit.setColor(listOf(a), 20) }
        assertFailsWith<IllegalArgumentException> { kit.setColor(listOf(a), -1) }
        assertFailsWith<IllegalArgumentException> { kit.setColor(emptyList(), 20) }
        kit.setColor(listOf(a), 7)
        assertEquals(7, kit.listHabits(1, false)[0].colorIndex)
        kit.close()
    }

    @Test
    fun renameCategory_emptyClears() {
        val kit = newKit()
        val a = kit.createHabit(input("A", "Gym"))
        val b = kit.createHabit(input("B", "Gym"))
        kit.renameCategory("Gym", "  ")
        assertEquals(listOf("h:$a", "h:$b"), keys(kit))
        kit.close()
    }

    @Test
    fun renameCategory_intoExistingMerges() {
        val kit = newKit()
        val a = kit.createHabit(input("A", "Gym"))
        val b = kit.createHabit(input("B", "Health"))
        kit.renameCategory("Gym", "Health")
        assertEquals(listOf("c:Health", "h:$a", "h:$b"), keys(kit))
        kit.close()
    }

    @Test
    fun deleteHabits_removesAll_skipsUnknown() {
        val kit = newKit()
        val a = kit.createHabit(input("A"))
        val b = kit.createHabit(input("B"))
        val c = kit.createHabit(input("C"))
        kit.deleteHabits(listOf(a, b, 9999L))
        assertEquals(listOf("h:$c"), keys(kit))
        assertNull(kit.habitInput(a))
        kit.close()
    }

    @Test
    fun actions_skipUnknownIds() {
        val kit = newKit()
        val a = kit.createHabit(input("A"))
        kit.archive(listOf(9999L)); kit.unarchive(listOf(9999L))
        kit.setCategory(listOf(9999L, a), "X")
        kit.setColor(listOf(9999L), 3)
        kit.deleteHabits(emptyList())
        kit.archive(emptyList())
        assertEquals(listOf("c:X", "h:$a"), keys(kit))
        kit.close()
    }
}
