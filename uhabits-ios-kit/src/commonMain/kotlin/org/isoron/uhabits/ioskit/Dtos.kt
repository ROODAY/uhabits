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
