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
import org.isoron.uhabits.core.models.Habit
import org.isoron.uhabits.core.models.NumericalHabitType

/**
 * Returns true if a reminder for the given habit should be shown on the given date.
 *
 * A reminder is shown only if the habit has a reminder, is not archived, the reminder
 * is enabled for the weekday of [date], and the habit has not already been completed
 * on [completionDate] (habits with an AT_MOST target are still reminded when completed).
 *
 * [date] is the calendar day of the reminder; [completionDate] is the day whose completion
 * state suppresses it. Android passes the midnight-delay-aware "today" here, which can
 * differ from [date].
 */
fun shouldShowReminder(habit: Habit, date: LocalDate, completionDate: LocalDate): Boolean {
    val reminder = habit.reminder ?: return false
    if (habit.isArchived) return false
    val weekday = (date.dayOfWeek.daysSinceSunday + 1) % 7
    if (!reminder.days.toArray()[weekday]) return false
    if (habit.isCompletedOn(completionDate) && habit.targetType != NumericalHabitType.AT_MOST) return false
    return true
}
