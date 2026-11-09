package org.isoron.uhabits.ioskit

import org.isoron.uhabits.core.models.HabitList.Order
import org.isoron.uhabits.core.models.HabitMatcher
import org.isoron.uhabits.core.preferences.Preferences

const val SORT_MANUAL = 0
const val SORT_NAME = 1
const val SORT_COLOR = 2
const val SORT_SCORE = 3
const val SORT_STATUS = 4

/** (default, reversed) order pair for a sort choice, as in ListHabitsMenuBehavior. Null for manual. */
internal fun orderPair(sort: Int): Pair<Order, Order>? = when (sort) {
    SORT_MANUAL -> null
    SORT_NAME -> Pair(Order.BY_NAME_ASC, Order.BY_NAME_DESC)
    SORT_COLOR -> Pair(Order.BY_COLOR_ASC, Order.BY_COLOR_DESC)
    SORT_SCORE -> Pair(Order.BY_SCORE_DESC, Order.BY_SCORE_ASC)
    SORT_STATUS -> Pair(Order.BY_STATUS_ASC, Order.BY_STATUS_DESC)
    else -> throw IllegalArgumentException("unknown sort $sort")
}

internal fun sortOf(order: Order): Int = when (order) {
    Order.BY_POSITION -> SORT_MANUAL
    Order.BY_NAME_ASC, Order.BY_NAME_DESC -> SORT_NAME
    Order.BY_COLOR_ASC, Order.BY_COLOR_DESC -> SORT_COLOR
    Order.BY_SCORE_ASC, Order.BY_SCORE_DESC -> SORT_SCORE
    Order.BY_STATUS_ASC, Order.BY_STATUS_DESC -> SORT_STATUS
}

internal fun readListOptions(prefs: Preferences): ListOptions {
    val primary = prefs.defaultPrimaryOrder
    return ListOptions(
        sort = sortOf(primary),
        isReversed = primary == Order.BY_NAME_DESC || primary == Order.BY_COLOR_DESC ||
            primary == Order.BY_SCORE_ASC || primary == Order.BY_STATUS_DESC,
        isSortable = primary == Order.BY_POSITION,
        hideArchived = !prefs.showArchived,
        hideCompleted = !prefs.showCompleted
    )
}

/** Port of ListHabitsMenuBehavior.onSortToggleBy over the stored preferences. */
internal fun applySortToggle(prefs: Preferences, sort: Int) {
    val pair = orderPair(sort)
    if (pair == null) {
        prefs.defaultPrimaryOrder = Order.BY_POSITION
        return
    }
    val (default, reversed) = pair
    val primary = prefs.defaultPrimaryOrder
    if (primary != default) {
        if (primary != reversed) prefs.defaultSecondaryOrder = primary
        prefs.defaultPrimaryOrder = default
    } else {
        prefs.defaultPrimaryOrder = reversed
    }
}

/** Port of ListHabitsMenuBehavior.updateAdapterFilter. */
internal fun listMatcher(prefs: Preferences, searchQuery: String): HabitMatcher =
    if (prefs.areQuestionMarksEnabled) {
        HabitMatcher(
            isArchivedAllowed = prefs.showArchived,
            isEnteredAllowed = prefs.showCompleted,
            searchQuery = searchQuery
        )
    } else {
        HabitMatcher(
            isArchivedAllowed = prefs.showArchived,
            isCompletedAllowed = prefs.showCompleted,
            searchQuery = searchQuery
        )
    }

/** Inserts a header before a habit whose category differs from the last header (HabitCardListAdapter.buildRows). */
internal fun <T> withHeaders(
    habits: List<T>,
    categoryOf: (T) -> String,
    habitRow: (T) -> ListRow
): List<ListRow> {
    val rows = mutableListOf<ListRow>()
    var lastHeader = ""
    for (h in habits) {
        val category = categoryOf(h)
        if (category.isNotBlank() && category != lastHeader) {
            rows.add(ListRow("c:$category", category, null))
            lastHeader = category
        }
        rows.add(habitRow(h))
    }
    return rows
}

/** Outcome of a drop: where to put the habit, in terms of the neighbouring habit and the header above. */
internal data class MovePlan(val refId: Long?, val placeBefore: Boolean, val category: String, val newIndex: Int)

/**
 * Port of HabitCardListAdapter.onDragEnd applied to a SwiftUI onMove (insert-before offset in the pre-removal list).
 * [keys] are row keys ("h:<id>" / "c:<title>"). Returns null if the move is invalid or would change nothing.
 */
internal fun planMove(keys: List<String>, habitId: Long, fromIndex: Int, toOffset: Int, currentCategory: String): MovePlan? {
    if (fromIndex !in keys.indices || toOffset < 0 || toOffset > keys.size) return null
    if (keys[fromIndex] != "h:$habitId") return null
    if (keys.count { it.startsWith("h:") } < 2) return null
    val insertAt = if (toOffset > fromIndex) toOffset - 1 else toOffset
    val rows = keys.toMutableList()
    val moved = rows.removeAt(fromIndex)
    rows.add(insertAt, moved)
    val k = insertAt
    var category = ""
    for (i in (k - 1) downTo 0) {
        if (rows[i].startsWith("c:")) {
            category = rows[i].removePrefix("c:")
            break
        }
    }
    if (k == fromIndex && category == currentCategory) return null
    val above = rows.getOrNull(k - 1)
    val below = rows.getOrNull(k + 1)
    return when {
        above != null && above.startsWith("h:") -> MovePlan(above.removePrefix("h:").toLong(), false, category, k)
        below != null && below.startsWith("h:") -> MovePlan(below.removePrefix("h:").toLong(), true, category, k)
        else -> MovePlan(null, false, category, k)
    }
}
