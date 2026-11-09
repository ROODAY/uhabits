package org.isoron.uhabits.ioskit

import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals

class CategoryTest {
    private fun input(name: String = "Run", category: String = "") = HabitInput(
        name = name, question = "", description = "", colorIndex = 5,
        isNumerical = false, unit = "", targetValue = 0.0, targetType = 0,
        freqNumerator = 1, freqDenominator = 1, reminder = null, category = category
    )

    @Test
    fun createHabit_storesTrimmedCategory() {
        val (kit, _) = testKit(Files.createTempDirectory("loopkit").toFile())
        val id = kit.createHabit(input(category = "  Health "))
        assertEquals("Health", kit.habitInput(id)!!.category)
        assertEquals("Health", kit.listHabits(1, false)[0].category)
        assertEquals("Health", kit.habitDetail(id, 1)!!.category)
        kit.close()
    }

    @Test
    fun editHabit_changesCategory_blankClears() {
        val (kit, _) = testKit(Files.createTempDirectory("loopkit").toFile())
        val id = kit.createHabit(input(category = "Health"))
        kit.editHabit(id, input(category = "Work"))
        assertEquals("Work", kit.habitInput(id)!!.category)
        kit.editHabit(id, input(category = "   "))
        assertEquals("", kit.habitInput(id)!!.category)
        assertEquals("", kit.listHabits(1, false)[0].category)
        kit.close()
    }

    @Test
    fun categories_distinctCaseSensitive_sortedCaseInsensitive() {
        val (kit, _) = testKit(Files.createTempDirectory("loopkit").toFile())
        listOf("work", "Health", "", "Work", "Health ").forEachIndexed { i, c ->
            kit.createHabit(input(name = "H$i", category = c))
        }
        assertEquals(listOf("Health", "Work", "work"), kit.categories())
        kit.close()
    }
}
