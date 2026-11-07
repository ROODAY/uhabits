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
package org.isoron.uhabits.core.ui

import org.isoron.platform.time.LocalDate
import org.isoron.uhabits.core.BaseUnitTest
import org.isoron.uhabits.core.models.Entry
import org.isoron.uhabits.core.models.Habit
import org.isoron.uhabits.core.models.Reminder
import org.isoron.uhabits.core.models.WeekdayList
import org.isoron.uhabits.core.preferences.MemoryStorage
import org.isoron.uhabits.core.preferences.Preferences
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class NotificationTrayTest : BaseUnitTest() {
    private class FakeSystemTray : NotificationTray.SystemTray {
        val shown = mutableListOf<LocalDate>()
        val logs = mutableListOf<String>()
        override fun removeNotification(notificationId: Int) {}
        override fun showNotification(habit: Habit, notificationId: Int, date: LocalDate, reminderTime: Long) {
            shown.add(date)
        }
        override fun log(msg: String) {
            logs.add(msg)
        }
    }

    private lateinit var systemTray: FakeSystemTray
    private lateinit var tray: NotificationTray
    private lateinit var habit: Habit

    @BeforeTest
    override fun setUp() {
        super.setUp()
        systemTray = FakeSystemTray()
        tray = NotificationTray(taskRunner, commandRunner, Preferences(MemoryStorage()), systemTray)
        habit = fixtures.createEmptyHabit()
        habit.reminder = Reminder(8, 30, WeekdayList.EVERY_DAY)
    }

    @Test
    fun show_notCompleted_shows() {
        tray.show(habit, LocalDate(2015, 1, 25), 0)
        assertEquals(listOf(LocalDate(2015, 1, 25)), systemTray.shown)
    }

    @Test
    fun show_checksCompletionAgainstToday_notPassedDate() {
        // today = 2015-01-25 and the habit is completed today but not on 01-26.
        habit.originalEntries.add(Entry(LocalDate(2015, 1, 25), Entry.YES_MANUAL))
        habit.recompute()
        tray.show(habit, LocalDate(2015, 1, 26), 0)
        assertTrue(systemTray.shown.isEmpty())
        assertTrue(systemTray.logs.any { it.contains("already checked") })
    }

    @Test
    fun show_archived_logsReason() {
        habit.isArchived = true
        tray.show(habit, LocalDate(2015, 1, 25), 0)
        assertTrue(systemTray.shown.isEmpty())
        assertTrue(systemTray.logs.any { it.contains("is archived") })
    }
}
