package org.isoron.uhabits.ioskit

import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ReorderTest {
    private fun input(name: String, category: String = "") = HabitInput(
        name = name, question = "", description = "", colorIndex = 5,
        isNumerical = false, unit = "", targetValue = 0.0, targetType = 0,
        freqNumerator = 1, freqDenominator = 1, reminder = null, category = category
    )

    private class Fixture(val kit: LoopKit, val ids: Map<String, Long>)

    /** Rows: [h:A, c:Health, h:B, h:C, c:Work, h:D]. */
    private fun fixture(): Fixture {
        val (kit, _) = testKit(Files.createTempDirectory("loopkit").toFile())
        val ids = linkedMapOf<String, Long>()
        ids["A"] = kit.createHabit(input("A"))
        ids["B"] = kit.createHabit(input("B", "Health"))
        ids["C"] = kit.createHabit(input("C", "Health"))
        ids["D"] = kit.createHabit(input("D", "Work"))
        return Fixture(kit, ids)
    }

    private fun Fixture.order(): List<String> =
        kit.listRows(1, "").mapNotNull { r -> r.habit?.let { h -> ids.entries.first { e -> e.value == h.id }.key } }

    private fun Fixture.cat(n: String) = kit.habitInput(ids[n]!!)!!.category

    @Test
    fun setup_rows() {
        val f = fixture()
        val i = f.ids
        assertEquals(
            listOf("h:${i["A"]}", "c:Health", "h:${i["B"]}", "h:${i["C"]}", "c:Work", "h:${i["D"]}"),
            f.kit.listRows(1, "").map { it.key }
        )
    }

    @Test
    fun move_withinCategory() {
        val f = fixture()
        assertTrue(f.kit.moveHabit(f.ids["B"]!!, 2, 4, ""))
        assertEquals(listOf("A", "C", "B", "D"), f.order())
        assertEquals("Health", f.cat("B"))
        assertEquals("Work", f.cat("D"))
    }

    @Test
    fun move_intoOtherCategory_underHeader() {
        val f = fixture()
        assertTrue(f.kit.moveHabit(f.ids["A"]!!, 0, 5, ""))
        assertEquals("Work", f.cat("A"))
        val o = f.order()
        assertEquals(o.indexOf("D") - 1, o.indexOf("A"))
    }

    @Test
    fun move_toTop_clearsCategory() {
        val f = fixture()
        assertTrue(f.kit.moveHabit(f.ids["D"]!!, 5, 0, ""))
        assertEquals("", f.cat("D"))
        val o = f.order()
        assertEquals(o.indexOf("A") - 1, o.indexOf("D"))
    }

    @Test
    fun move_toEnd() {
        val f = fixture()
        assertTrue(f.kit.moveHabit(f.ids["B"]!!, 2, 6, ""))
        assertEquals("Work", f.cat("B"))
        val o = f.order()
        assertEquals(o.indexOf("D") + 1, o.indexOf("B"))
    }

    @Test
    fun move_staleIndex_returnsFalse() {
        val f = fixture()
        val before = f.order()
        assertFalse(f.kit.moveHabit(f.ids["B"]!!, 3, 0, ""))
        assertEquals(before, f.order())
        assertEquals("Health", f.cat("B"))
        assertEquals("Health", f.cat("C"))
        assertEquals("", f.cat("A"))
    }

    @Test
    fun move_headerOrNonManualOrSearch_returnsFalse() {
        val f = fixture()
        val before = f.order()
        assertFalse(f.kit.moveHabit(f.ids["B"]!!, 1, 0, ""))
        assertFalse(f.kit.moveHabit(f.ids["B"]!!, 2, 7, ""))
        assertFalse(f.kit.moveHabit(f.ids["B"]!!, 2, -1, ""))
        assertFalse(f.kit.moveHabit(f.ids["B"]!!, 9, 0, ""))
        assertFalse(f.kit.moveHabit(f.ids["B"]!!, 2, 4, "B"))
        f.kit.sortBy(SORT_NAME)
        assertFalse(f.kit.moveHabit(f.ids["B"]!!, 2, 4, ""))
        f.kit.sortBy(SORT_MANUAL)
        assertEquals(before, f.order())
    }

    @Test
    fun move_noChange_returnsFalse() {
        val f = fixture()
        assertFalse(f.kit.moveHabit(f.ids["B"]!!, 2, 2, ""))
        assertFalse(f.kit.moveHabit(f.ids["B"]!!, 2, 3, ""))
        assertEquals(listOf("A", "B", "C", "D"), f.order())
    }

    @Test
    fun move_onlyHabit_returnsFalse() {
        val (kit, _) = testKit(Files.createTempDirectory("loopkit").toFile())
        val id = kit.createHabit(input("Solo", "Health"))
        assertFalse(kit.moveHabit(id, 1, 0, ""))
        assertEquals("Health", kit.habitInput(id)!!.category)
    }
}
