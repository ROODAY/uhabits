package org.isoron.uhabits.ioskit

data class DayCell(
    val date: String,
    val rawValue: Int,
    val value: Double,
    val isCompleted: Boolean,
    val notes: String
)

data class HabitRow(
    val id: Long,
    val name: String,
    val question: String,
    val colorIndex: Int,
    val isNumerical: Boolean,
    val unit: String,
    val targetValue: Double,
    val targetType: Int,
    val isArchived: Boolean,
    val score: Double,
    val isCompletedToday: Boolean,
    val today: String,
    val days: List<DayCell>,
    val category: String
)

/** Reminder time. `days` has size 7, indexed by daysSinceSunday (0 = Sunday). */
data class ReminderDto(
    val hour: Int,
    val minute: Int,
    val days: List<Boolean>
) {
    init {
        require(hour in 0..23) { "hour out of range: $hour" }
        require(minute in 0..59) { "minute out of range: $minute" }
        require(days.size == 7) { "days must have size 7" }
    }
}

data class HabitInput(
    val name: String,
    val question: String,
    val description: String,
    val colorIndex: Int,
    val isNumerical: Boolean,
    val unit: String,
    val targetValue: Double,
    val targetType: Int,
    val freqNumerator: Int,
    val freqDenominator: Int,
    val reminder: ReminderDto?,
    val category: String
)

data class StreakDto(
    val start: String,
    val end: String,
    val length: Int
)

data class HabitDetail(
    val row: HabitRow,
    val description: String,
    val freqNumerator: Int,
    val freqDenominator: Int,
    val reminder: ReminderDto?,
    val currentStreak: Int,
    val bestStreaks: List<StreakDto>,
    val category: String
)

data class ReminderOccurrence(
    val habitId: Long,
    val habitName: String,
    val question: String,
    val isNumerical: Boolean,
    val date: String,
    val hour: Int,
    val minute: Int
)

/** firstWeekdayChoice: -1 = system, 1..7 = Sun..Sat. resolvedFirstWeekday is always 1..7. */
data class AppSettings(
    val shortToggle: Boolean,
    val midnightDelay: Boolean,
    val skipEnabled: Boolean,
    val questionMarksEnabled: Boolean,
    val reverseCheckmarks: Boolean,
    val firstWeekdayChoice: Int,
    val resolvedFirstWeekday: Int
)

/** One row of the flat list: either a category header or a habit. Exactly one field is non-null. */
data class ListRow(
    val key: String,
    val categoryTitle: String?,
    val habit: HabitRow?
)

data class ListOptions(
    val sort: Int,
    val isReversed: Boolean,
    val isSortable: Boolean,
    val hideArchived: Boolean,
    val hideCompleted: Boolean
)
