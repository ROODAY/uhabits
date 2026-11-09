package org.isoron.uhabits.ioskit

import org.isoron.platform.time.LocalDate
import org.isoron.uhabits.core.models.Entry
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

private val TODAY = LocalDate(2015, 1, 25) // testKit default today

class ListRowsTest {
    private fun input(
        name: String,
        category: String = "",
        question: String = "",
        description: String = "",
        colorIndex: Int = 5
    ) = HabitInput(
        name = name, question = question, description = description, colorIndex = colorIndex,
        isNumerical = false, unit = "", targetValue = 0.0, targetType = 0,
        freqNumerator = 1, freqDenominator = 1, reminder = null, category = category
    )

    private fun newKit(): Pair<LoopKit, MapStore> = testKit(Files.createTempDirectory("loopkit").toFile())

    private fun keys(kit: LoopKit, query: String = "") = kit.listRows(1, query).map { it.key }

    @Test
    fun rows_uncategorizedFirstThenHeadersAlphabetical() {
        val (kit, _) = newKit()
        val a = kit.createHabit(input("A"))
        val b = kit.createHabit(input("B", "Work"))
        val c = kit.createHabit(input("C", "Health"))
        val d = kit.createHabit(input("D"))
        assertEquals(listOf("h:$a", "h:$d", "c:Health", "h:$c", "c:Work", "h:$b"), keys(kit))
        val rows = kit.listRows(1, "")
        assertEquals("Health", rows[2].categoryTitle)
        assertEquals(null, rows[2].habit)
        assertEquals(a, rows[0].habit!!.id)
        assertEquals(null, rows[0].categoryTitle)
        kit.close()
    }

    @Test
    fun rows_hideArchivedDefault() {
        val (kit, store) = newKit()
        val a = kit.createHabit(input("A"))
        val b = kit.createHabit(input("B"))
        kit.habitList.getById(b)!!.let { it.isArchived = true; kit.habitList.update(listOf(it)) }
        assertTrue(kit.listOptions().hideArchived)
        assertEquals(listOf("h:$a"), keys(kit))
        kit.setHideArchived(false)
        assertFalse(kit.listOptions().hideArchived)
        assertEquals(listOf("h:$a", "h:$b"), keys(kit))
        assertEquals("true", store.map["pref_show_archived"])
        kit.close()
    }

    @Test
    fun rows_hideCompleted_usesCompletedWhenQuestionMarksOff() {
        val (kit, _) = newKit()
        val a = kit.createHabit(input("A"))
        val b = kit.createHabit(input("B"))
        val c = kit.createHabit(input("C"))
        kit.markDone(a, kit.today())
        kit.habitList.getById(c)!!.originalEntries.add(Entry(TODAY, Entry.NO, ""))
        assertEquals(listOf("h:$a", "h:$b", "h:$c"), keys(kit))
        kit.setHideCompleted(true)
        assertTrue(kit.listOptions().hideCompleted)
        assertEquals(listOf("h:$b", "h:$c"), keys(kit))
        kit.close()
    }

    @Test
    fun rows_hideCompleted_usesEnteredWhenQuestionMarksOn() {
        val (kit, _) = newKit()
        kit.setQuestionMarksEnabled(true)
        val a = kit.createHabit(input("A"))
        val b = kit.createHabit(input("B"))
        val c = kit.createHabit(input("C"))
        // Toggle cycles YES -> NO (explicit entry) with question marks on and skip off.
        kit.toggle(a, kit.today())
        kit.toggle(a, kit.today())
        assertEquals(
            Entry.NO,
            kit.habitList.getById(a)!!.originalEntries.get(TODAY).value
        )
        kit.markDone(c, kit.today())
        kit.setHideCompleted(true)
        assertEquals(listOf("h:$b"), keys(kit))
        kit.close()
    }

    @Test
    fun rows_searchMatchesNameQuestionDescription_caseInsensitive() {
        val (kit, _) = newKit()
        val a = kit.createHabit(input("Run"))
        val b = kit.createHabit(input("B", question = "Did you MEDITATE?"))
        val c = kit.createHabit(input("C", description = "Evening stretch"))
        kit.createHabit(input("D"))
        assertEquals(listOf("h:$a"), keys(kit, "rUN"))
        assertEquals(listOf("h:$b"), keys(kit, "meditate"))
        assertEquals(listOf("h:$c"), keys(kit, "STRETCH"))
        kit.close()
    }

    @Test
    fun rows_searchKeepsHeadersOnlyForMatchingGroups() {
        val (kit, _) = newKit()
        kit.createHabit(input("Run", "Health"))
        val b = kit.createHabit(input("Read", "Work"))
        assertEquals(listOf("c:Work", "h:$b"), keys(kit, "read"))
        assertEquals(emptyList(), keys(kit, "zzz"))
        kit.close()
    }

    @Test
    fun sortBy_sameChoiceReverses_andSecondaryInherits() {
        val (kit, store) = newKit()
        kit.sortBy(SORT_NAME)
        assertEquals(SORT_NAME, kit.listOptions().sort)
        assertFalse(kit.listOptions().isReversed)
        assertEquals("BY_NAME_ASC", store.map["pref_default_order"])
        kit.sortBy(SORT_NAME)
        assertEquals("BY_NAME_DESC", store.map["pref_default_order"])
        assertTrue(kit.listOptions().isReversed)
        assertEquals(SORT_NAME, kit.listOptions().sort)
        kit.sortBy(SORT_COLOR)
        assertEquals("BY_COLOR_ASC", store.map["pref_default_order"])
        assertEquals("BY_NAME_DESC", store.map["pref_default_secondary_order"])
        assertEquals(SORT_COLOR, kit.listOptions().sort)
        kit.close()
    }

    @Test
    fun sortBy_scoreStartsDescending() {
        val (kit, store) = newKit()
        kit.sortBy(SORT_SCORE)
        assertEquals("BY_SCORE_DESC", store.map["pref_default_order"])
        assertFalse(kit.listOptions().isReversed)
        kit.sortBy(SORT_SCORE)
        assertEquals("BY_SCORE_ASC", store.map["pref_default_order"])
        assertTrue(kit.listOptions().isReversed)
        kit.sortBy(SORT_STATUS)
        assertEquals(SORT_STATUS, kit.listOptions().sort)
        kit.close()
    }

    @Test
    fun sortBy_manual_isSortable() {
        val (kit, store) = newKit()
        assertTrue(kit.listOptions().isSortable)
        assertEquals(SORT_MANUAL, kit.listOptions().sort)
        kit.sortBy(SORT_NAME)
        assertFalse(kit.listOptions().isSortable)
        val secondary = store.map["pref_default_secondary_order"]
        kit.sortBy(SORT_MANUAL)
        assertTrue(kit.listOptions().isSortable)
        assertFalse(kit.listOptions().isReversed)
        assertEquals(secondary, store.map["pref_default_secondary_order"])
        assertFailsWith<IllegalArgumentException> { kit.sortBy(99) }
        kit.close()
    }

    @Test
    fun rows_categoryGroupingAppliesUnderNameSort() {
        val (kit, _) = newKit()
        val z = kit.createHabit(input("Zed"))
        val a = kit.createHabit(input("Ann", "Work"))
        val m = kit.createHabit(input("Mia"))
        val b = kit.createHabit(input("Bob", "Work"))
        kit.sortBy(SORT_NAME)
        assertEquals(listOf("h:$m", "h:$z", "c:Work", "h:$a", "h:$b"), keys(kit))
        kit.close()
    }
}
