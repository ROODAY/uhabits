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
    val days: List<DayCell>
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
    val reminder: ReminderDto?
)
