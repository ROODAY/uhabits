package org.isoron.uhabits.ioskit

import org.isoron.platform.time.LocalDate
import java.io.File
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class HabitDetailTest {
    private val today = LocalDate(2015, 1, 25)

    private fun tmp(): File = Files.createTempDirectory("loopkit").toFile()

    private fun input() = HabitInput(
        name = "Run", question = "", description = "Every day", colorIndex = 3,
        isNumerical = false, unit = "", targetValue = 0.0, targetType = 0,
        freqNumerator = 1, freqDenominator = 1, reminder = null, category = ""
    )

    /** Marks done every day whose offset (days before today) is in [offsets]. */
    private fun fixture(offsets: Iterable<Int>): Pair<LoopKit, Long> {
        val (kit, _) = testKit(tmp(), today)
        val id = kit.createHabit(input())
        for (o in offsets) kit.markDone(id, today.minus(o).iso())
        return Pair(kit, id)
    }

    private fun doneDays(vararg days: Int): List<Int> = days.map { 25 - it }

    @Test
    fun habitDetail_unknownIdReturnsNull() {
        val (kit, _) = testKit(tmp())
        assertNull(kit.habitDetail(999, 7))
        kit.close()
    }

    @Test
    fun currentStreak_countsThroughToday() {
        val (kit, id) = fixture(doneDays(23, 24, 25))
        assertEquals(3, kit.habitDetail(id, 7)!!.currentStreak)
        kit.close()
    }

    @Test
    fun currentStreak_aliveIfDoneYesterdayOnly() {
        val (kit, id) = fixture(doneDays(22, 23, 24))
        assertEquals(3, kit.habitDetail(id, 7)!!.currentStreak)
        kit.close()
    }

    @Test
    fun currentStreak_zeroIfGap() {
        val (kit, id) = fixture(doneDays(21, 22, 23))
        assertEquals(0, kit.habitDetail(id, 7)!!.currentStreak)
        kit.close()
    }

    @Test
    fun currentStreak_foundEvenIfNotAmongBest10() {
        val offsets = mutableListOf(0, 1)
        // 11 older 4-day runs separated by one-day gaps.
        for (k in 0 until 11) {
            val start = 3 + k * 5
            for (j in 0 until 4) offsets.add(start + j)
        }
        val (kit, id) = fixture(offsets)
        val d = kit.habitDetail(id, 7)!!
        assertEquals(10, d.bestStreaks.size)
        assertEquals(2, d.currentStreak)
        kit.close()
    }

    @Test
    fun bestStreaks_matchCoreGetBest() {
        val offsets = mutableListOf<Int>()
        var pos = 0
        for (i in 0 until 14) {
            val len = (i % 5) + 1
            for (j in 0 until len) offsets.add(pos + j)
            pos += len + 1
        }
        val (kit, id) = fixture(offsets)
        val d = kit.habitDetail(id, 7)!!
        val expected = kit.habitList.getById(id)!!.streaks.getBest(10)
        assertEquals(10, d.bestStreaks.size)
        assertEquals(
            expected.map { StreakDto(it.start.iso(), it.end.iso(), it.length) },
            d.bestStreaks
        )
        kit.close()
    }

    @Test
    fun history_includesNotes() {
        val (kit, id) = fixture(doneDays(24))
        kit.setNotes(id, "2015-01-23", "felt great")
        val d = assertNotNull(kit.habitDetail(id, 5))
        assertEquals(5, d.row.days.size)
        assertEquals("felt great", d.row.days.first { it.date == "2015-01-23" }.notes)
        assertEquals("Every day", d.description)
        assertEquals(1, d.freqNumerator)
        assertEquals(1, d.freqDenominator)
        assertNull(d.reminder)
        kit.close()
    }
}
