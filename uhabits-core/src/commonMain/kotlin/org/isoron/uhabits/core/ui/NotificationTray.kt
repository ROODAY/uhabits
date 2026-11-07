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

import me.tatarka.inject.annotations.Inject
import org.isoron.platform.time.LocalDate
import org.isoron.uhabits.core.AppScope
import org.isoron.uhabits.core.commands.Command
import org.isoron.uhabits.core.commands.CommandRunner
import org.isoron.uhabits.core.commands.CreateRepetitionCommand
import org.isoron.uhabits.core.commands.DeleteHabitsCommand
import org.isoron.uhabits.core.models.Habit
import org.isoron.uhabits.core.preferences.Preferences
import org.isoron.uhabits.core.reminders.shouldShowReminder
import org.isoron.uhabits.core.tasks.Task
import org.isoron.uhabits.core.tasks.TaskRunner

@AppScope
@Inject
open class NotificationTray(
    private val taskRunner: TaskRunner,
    private val commandRunner: CommandRunner,
    private val preferences: Preferences,
    private val systemTray: SystemTray
) : CommandRunner.Listener, Preferences.Listener {
    private val active: MutableMap<Habit, NotificationData> = mutableMapOf()
    open fun cancel(habit: Habit) {
        val notificationId = getNotificationId(habit)
        systemTray.removeNotification(notificationId)
        active.remove(habit)
    }

    override fun onCommandFinished(command: Command) {
        if (command is CreateRepetitionCommand) {
            val (_, habit) = command
            cancel(habit)
        }
        if (command is DeleteHabitsCommand) {
            val (_, deleted) = command
            for (habit in deleted) cancel(habit)
        }
    }

    override fun onNotificationsChanged() {
        reshowAll()
    }

    open fun show(habit: Habit, date: LocalDate, reminderTime: Long) {
        val data = NotificationData(date, reminderTime)
        active[habit] = data
        taskRunner.execute(ShowNotificationTask(habit, data))
    }

    open fun startListening() {
        commandRunner.addListener(this)
        preferences.addListener(this)
    }

    open fun stopListening() {
        commandRunner.removeListener(this)
        preferences.removeListener(this)
    }

    private fun getNotificationId(habit: Habit): Int {
        val id = habit.id ?: return 0
        return (id % Int.MAX_VALUE).toInt()
    }

    private fun reshowAll() {
        for ((habit, data) in active.entries) {
            taskRunner.execute(ShowNotificationTask(habit, data))
        }
    }

    open fun reshow(habit: Habit) {
        active[habit]?.let {
            taskRunner.execute(ShowNotificationTask(habit, it))
        }
    }

    interface SystemTray {
        fun removeNotification(notificationId: Int)
        fun showNotification(
            habit: Habit,
            notificationId: Int,
            date: LocalDate,
            reminderTime: Long
        )

        fun log(msg: String)
    }

    internal class NotificationData(val date: LocalDate, val reminderTime: Long)
    private inner class ShowNotificationTask(private val habit: Habit, data: NotificationData) :
        Task {
        private val date: LocalDate = data.date
        private val reminderTime: Long = data.reminderTime

        override suspend fun doInBackground() {
            // Warm up computed entries off the main thread before the check.
            habit.isCompletedOn(date)
        }

        override fun onPostExecute() {
            systemTray.log("Showing notification for habit=" + habit.id)
            if (!shouldShowReminder(habit, date)) {
                systemTray.log("Habit ${habit.id} should not be reminded on $date. Skipping.")
                return
            }
            systemTray.showNotification(
                habit,
                getNotificationId(habit),
                date,
                reminderTime
            )
        }
    }

    companion object {
        const val REMINDERS_CHANNEL_ID = "REMINDERS"
    }
}
