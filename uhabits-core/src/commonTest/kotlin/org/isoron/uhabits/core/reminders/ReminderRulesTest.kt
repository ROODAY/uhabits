/*
 * Copyright (C) 2016-2025 Álinson Santos Xavier <git@axavier.org>
 *
 * This file is part of Loop Habit Tracker.
 *
 * Loop Habit Tracker is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or (at your
 * option) any later version.
 *
 * Loop Habit Tracker is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */
package org.isoron.uhabits.core.reminders

import org.isoron.platform.time.LocalDate
import org.isoron.uhabits.core.BaseUnitTest
import org.isoron.uhabits.core.models.Entry
import org.isoron.uhabits.core.models.Habit
import org.isoron.uhabits.core.models.NumericalHabitType
import org.isoron.uhabits.core.models.Reminder
import org.isoron.uhabits.core.models.WeekdayList
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ReminderRulesTest : BaseUnitTest() {
    // today = 2015-01-25, a Sunday
    private val sunday = LocalDate(2015, 1, 25)

    private fun habitWithReminder(days: WeekdayList = WeekdayList.EVERY_DAY): Habit {
        val habit = fixtures.createEmptyHabit()
        habit.reminder = Reminder(8, 30, days)
        return habit
    }

    @Test
    fun noReminder_false() {
        val habit = fixtures.createEmptyHabit()
        assertFalse(shouldShowReminder(habit, sunday, sunday))
    }

    @Test
    fun archived_false() {
        val habit = habitWithReminder()
        habit.isArchived = true
        assertFalse(shouldShowReminder(habit, sunday, sunday))
    }

    @Test
    fun dayNotInReminderDays_false() {
        val days = BooleanArray(7)
        days[2] = true // Monday
        val habit = habitWithReminder(WeekdayList(days))
        assertFalse(shouldShowReminder(habit, sunday, sunday))
    }

    @Test
    fun sundayIncluded_true() {
        val days = BooleanArray(7)
        days[1] = true // Sunday
        val habit = habitWithReminder(WeekdayList(days))
        assertTrue(shouldShowReminder(habit, sunday, sunday))
    }

    @Test
    fun completedYesNo_false() {
        val habit = habitWithReminder()
        habit.originalEntries.add(Entry(sunday, Entry.YES_MANUAL))
        habit.recompute()
        assertFalse(shouldShowReminder(habit, sunday, sunday))
    }

    @Test
    fun completedAtMost_stillTrue() {
        val habit = fixtures.createEmptyNumericalHabit(NumericalHabitType.AT_MOST)
        habit.reminder = Reminder(8, 30, WeekdayList.EVERY_DAY)
        habit.originalEntries.add(Entry(sunday, 1000))
        habit.recompute()
        assertTrue(habit.isCompletedOn(sunday))
        assertTrue(shouldShowReminder(habit, sunday, sunday))
    }

    @Test
    fun notCompleted_true() {
        val habit = habitWithReminder()
        assertTrue(shouldShowReminder(habit, sunday, sunday))
    }

    @Test
    fun completionDateDiffersFromDate_usesCompletionDate() {
        val habit = habitWithReminder()
        val saturday = LocalDate(2015, 1, 24)
        habit.originalEntries.add(Entry(saturday, Entry.YES_MANUAL))
        habit.recompute()
        assertFalse(shouldShowReminder(habit, sunday, saturday))
        assertTrue(shouldShowReminder(habit, sunday, sunday))
    }
}
