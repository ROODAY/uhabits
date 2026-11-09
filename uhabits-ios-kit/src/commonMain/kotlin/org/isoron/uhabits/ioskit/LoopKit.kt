package org.isoron.uhabits.ioskit

import org.isoron.platform.io.Database
import org.isoron.platform.io.DatabaseOpener
import org.isoron.platform.io.FileOpener
import org.isoron.platform.io.getVersion
import org.isoron.platform.io.migrateTo
import org.isoron.platform.io.setVersion
import org.isoron.platform.time.LocalDate
import org.isoron.platform.time.computeToday
import org.isoron.platform.time.getFirstWeekday
import org.isoron.platform.time.setFirstWeekday
import org.isoron.platform.time.setToday
import org.isoron.uhabits.core.DATABASE_VERSION
import org.isoron.uhabits.core.commands.CommandRunner
import org.isoron.uhabits.core.commands.CreateHabitCommand
import org.isoron.uhabits.core.commands.DeleteHabitsCommand
import org.isoron.uhabits.core.commands.EditHabitCommand
import org.isoron.uhabits.core.commands.CreateRepetitionCommand
import org.isoron.uhabits.core.models.Entry
import org.isoron.uhabits.core.models.Habit
import org.isoron.uhabits.core.models.Frequency
import org.isoron.uhabits.core.models.HabitList
import org.isoron.uhabits.core.models.HabitType
import org.isoron.uhabits.core.models.NumericalHabitType
import org.isoron.uhabits.core.models.PaletteColor
import org.isoron.uhabits.core.models.Reminder
import org.isoron.uhabits.core.models.WeekdayList
import org.isoron.uhabits.core.models.sqlite.SQLModelFactory
import org.isoron.uhabits.core.preferences.Preferences
import org.isoron.uhabits.core.preferences.WidgetPreferences
import org.isoron.uhabits.core.reminders.shouldShowReminder
import org.isoron.uhabits.core.ui.NotificationTray
import org.isoron.uhabits.core.ui.widgets.WidgetBehavior
import org.isoron.uhabits.core.ui.views.DarkTheme
import org.isoron.uhabits.core.ui.views.LightTheme
import org.isoron.uhabits.core.ui.views.Theme
import kotlin.math.roundToInt

fun interface TodaySource {
    fun today(midnightDelayHours: Int): LocalDate
}

/** Largest accepted numerical target, keeping the x1000 raw values and Swift formatting in range. */
internal const val MAX_TARGET_VALUE = 1e9

/**
 * Facade over the habit core. NOT thread-safe: callers (the Swift actor) must
 * serialize all calls, including reload() and close().
 */
class LoopKit @Throws(Exception::class) constructor(
    private val databaseOpener: DatabaseOpener,
    private val fileOpener: FileOpener,
    private val dbPath: String,
    internal val store: KeyValueStore,
    private val todaySource: TodaySource = TodaySource { computeToday(it, 0) }
) {
    private var database: Database? = null
    internal lateinit var modelFactory: SQLModelFactory
        private set
    internal lateinit var habitList: HabitList
        private set
    internal lateinit var prefs: Preferences
        private set
    internal lateinit var widgetPrefs: WidgetPreferences
        private set
    internal lateinit var commandRunner: CommandRunner
        private set

    private lateinit var widgetBehavior: WidgetBehavior

    private var lastToday: LocalDate? = null
    private var loaded = false

    init {
        load()
    }

    /** Closes and reopens the database, picking up writes made by other processes. */
    @Throws(Exception::class)
    fun reload() {
        close()
        load()
    }

    @Throws(Exception::class)
    fun close() {
        loaded = false
        try {
            database?.close()
        } finally {
            database = null
        }
    }

    @Throws(Exception::class)
    fun listHabits(dayCount: Int, includeArchived: Boolean): List<HabitRow> {
        val today = refreshToday()
        return habitList
            .filter { includeArchived || !it.isArchived }
            .sortedBy { it.position }
            .map { h -> buildRow(h, today, dayCount) }
    }

    internal fun buildRow(h: Habit, today: LocalDate, dayCount: Int): HabitRow {
        val days = (0 until maxOf(dayCount, 0)).map { i ->
            val date = today.minus(i)
            val raw = h.computedEntries.get(date).value
            val value = if (h.isNumerical) {
                maxOf(raw, 0) / 1000.0
            } else if (raw == Entry.YES_AUTO || raw == Entry.YES_MANUAL) {
                1.0
            } else {
                0.0
            }
            DayCell(
                date = date.iso(),
                rawValue = raw,
                value = value,
                isCompleted = h.isCompletedOn(date),
                notes = h.originalEntries.get(date).notes
            )
        }
        return HabitRow(
            id = h.id!!,
            name = h.name,
            question = h.question,
            colorIndex = h.color.paletteIndex,
            isNumerical = h.isNumerical,
            unit = h.unit,
            targetValue = h.targetValue,
            targetType = h.targetType.value,
            isArchived = h.isArchived,
            score = h.scores[today].value,
            isCompletedToday = h.isCompletedOn(today),
            today = today.iso(),
            days = days,
            category = h.category
        )
    }

    @Throws(Exception::class)
    fun listRows(dayCount: Int, searchQuery: String): List<ListRow> {
        val today = refreshToday()
        val view = habitList.getFiltered(listMatcher(prefs, searchQuery))
        view.primaryOrder = prefs.defaultPrimaryOrder
        view.secondaryOrder = prefs.defaultSecondaryOrder
        val habits = view.toList().filter { it.id != null }
        return withHeaders(habits, { it.category }) { h ->
            ListRow("h:${h.id}", null, buildRow(h, today, dayCount))
        }
    }

    @Throws(Exception::class)
    fun listOptions(): ListOptions {
        refreshToday()
        return readListOptions(prefs)
    }

    /** Selects a sort; choosing the active sort again reverses it. Throws on an unknown sort. */
    @Throws(Exception::class)
    fun sortBy(sort: Int) {
        refreshToday()
        applySortToggle(prefs, sort)
    }

    @Throws(Exception::class)
    fun setHideArchived(hide: Boolean) {
        refreshToday()
        prefs.showArchived = !hide
    }

    @Throws(Exception::class)
    fun setHideCompleted(hide: Boolean) {
        refreshToday()
        prefs.showCompleted = !hide
    }

    private fun reminderDto(h: Habit): ReminderDto? = h.reminder?.let { r ->
        val packed = r.days.toArray()
        ReminderDto(r.hour, r.minute, List(7) { i -> packed[(i + 1) % 7] })
    }

    /**
     * Detail for one habit, or null if it does not exist. `row.days` covers [historyDays] days.
     * `currentStreak` is the length of the streak ending today or yesterday, else 0.
     */
    @Throws(Exception::class)
    fun habitDetail(habitId: Long, historyDays: Int): HabitDetail? {
        val today = refreshToday()
        val h = habitList.getById(habitId) ?: return null
        val yesterday = today.minus(1)
        val current = h.streaks.getBest(Int.MAX_VALUE)
            .firstOrNull { it.end == today || it.end == yesterday }
        return HabitDetail(
            row = buildRow(h, today, historyDays),
            description = h.description,
            freqNumerator = h.frequency.numerator,
            freqDenominator = h.frequency.denominator,
            reminder = reminderDto(h),
            currentStreak = current?.length ?: 0,
            bestStreaks = h.streaks.getBest(10).map { StreakDto(it.start.iso(), it.end.iso(), it.length) },
            category = h.category
        )
    }

    /**
     * Concrete reminder occurrences from [nowDate] (a calendar date, not the midnight-delayed habit day)
     * through [horizonDays] days, sorted by (date, hour, minute, habitId), truncated to [maxCount].
     * Occurrences earlier than or equal to [nowMinuteOfDay] on [nowDate] are skipped. The completion
     * check uses the habit day at the fire moment (previous calendar day while before the midnight delay).
     */
    @Throws(Exception::class)
    fun upcomingReminders(nowDate: String, nowMinuteOfDay: Int, horizonDays: Int, maxCount: Int): List<ReminderOccurrence> {
        val today = refreshToday()
        val start = parseIso(nowDate)
        require(nowMinuteOfDay in 0..1439) { "nowMinuteOfDay out of range" }
        if (horizonDays <= 0 || maxCount <= 0) return emptyList()
        val delayMinutes = prefs.midnightDelayHours * 60
        val result = mutableListOf<ReminderOccurrence>()
        for (offset in 0 until horizonDays) {
            val d = start.plus(offset)
            for (h in habitList) {
                val id = h.id ?: continue
                val r = h.reminder ?: continue
                val minuteOfDay = r.hour * 60 + r.minute
                if (offset == 0 && minuteOfDay <= nowMinuteOfDay) continue
                val completionDate = if (minuteOfDay < delayMinutes) d.minus(1) else d
                // Measurable habits with a period target (e.g. 20 per week) are completed per period. The
                // core only evaluates today's period, so for a later day in that same period use today's
                // completion, as Android does when it re-checks at fire time.
                val checkDate = if (h.isNumerical && h.frequency.denominator > 1 && completionDate > today &&
                    h.computedEntries.periodStart(completionDate, getFirstWeekday(), h.frequency) ==
                    h.computedEntries.periodStart(today, getFirstWeekday(), h.frequency)
                ) today else completionDate
                if (!shouldShowReminder(h, d, checkDate)) continue
                result.add(ReminderOccurrence(id, h.name, h.question, h.isNumerical, d.iso(), r.hour, r.minute))
            }
        }
        return result
            .sortedWith(compareBy({ it.date }, { it.hour }, { it.minute }, { it.habitId }))
            .take(maxCount)
    }

    /** Distinct non-blank categories (case-sensitive), sorted case-insensitively. */
    @Throws(Exception::class)
    fun categories(): List<String> {
        refreshToday()
        return habitList.map { it.category.trim() }
            .filter { it.isNotEmpty() }
            .distinct()
            .sortedWith(compareBy({ it.lowercase() }, { it }))
    }

    /** 20 RGB ints (0xRRGGBB) for palette indices 0..19. */
    @Throws(Exception::class)
    fun palette(dark: Boolean): List<Int> {
        val theme: Theme = if (dark) DarkTheme() else LightTheme()
        return (0 until 20).map { i ->
            val c = theme.color(i)
            (channel(c.red) shl 16) or (channel(c.green) shl 8) or channel(c.blue)
        }
    }

    private fun channel(v: Double): Int = (v * 255.0).roundToInt().coerceIn(0, 255)

    @Throws(Exception::class)
    fun today(): String = refreshToday().iso()

    @Throws(Exception::class)
    fun midnightDelayHours(): Int {
        refreshToday()
        return prefs.midnightDelayHours
    }

    @Throws(Exception::class)
    fun areQuestionMarksEnabled(): Boolean {
        refreshToday()
        return prefs.areQuestionMarksEnabled
    }

    @Throws(Exception::class)
    fun settings(): AppSettings {
        refreshToday()
        return readSettings(prefs, store)
    }

    @Throws(Exception::class)
    fun setShortToggle(enabled: Boolean) {
        refreshToday()
        prefs.isShortToggleEnabled = enabled
    }

    @Throws(Exception::class)
    fun setMidnightDelay(enabled: Boolean) {
        refreshToday()
        prefs.isMidnightDelayEnabled = enabled
        lastToday = null
    }

    @Throws(Exception::class)
    fun setSkipEnabled(enabled: Boolean) {
        refreshToday()
        prefs.isSkipEnabled = enabled
    }

    @Throws(Exception::class)
    fun setQuestionMarksEnabled(enabled: Boolean) {
        refreshToday()
        prefs.areQuestionMarksEnabled = enabled
    }

    @Throws(Exception::class)
    fun setReverseCheckmarks(enabled: Boolean) {
        refreshToday()
        prefs.isCheckmarkSequenceReversed = enabled
    }

    /** [choice]: -1 = system default, 1..7 = Sunday..Saturday. */
    @Throws(Exception::class)
    fun setFirstWeekday(choice: Int) {
        refreshToday()
        writeFirstWeekday(store, choice)
        lastToday = null
        refreshToday()
    }

    private fun mutate(habitId: Long, date: String, requireNumerical: Boolean?, block: (Habit, LocalDate) -> Unit) {
        refreshToday()
        val d = parseIso(date)
        val habit = habitList.getById(habitId) ?: return
        if (requireNumerical != null && habit.isNumerical != requireNumerical) return
        block(habit, d)
    }

    /** Cycles a yes/no entry using the user's skip / question-mark preferences. */
    @Throws(Exception::class)
    fun toggle(habitId: Long, date: String) =
        mutate(habitId, date, false) { h, d -> widgetBehavior.onToggleRepetition(h, d) }

    /** Marks a yes/no entry as done (YES_MANUAL). */
    @Throws(Exception::class)
    fun markDone(habitId: Long, date: String) =
        mutate(habitId, date, false) { h, d -> widgetBehavior.onAddRepetition(h, d) }

    @Throws(Exception::class)
    fun increment(habitId: Long, date: String) =
        mutate(habitId, date, true) { h, d -> widgetBehavior.onIncrement(h, d, 1000) }

    @Throws(Exception::class)
    fun decrement(habitId: Long, date: String) =
        mutate(habitId, date, true) { h, d -> widgetBehavior.onDecrement(h, d, 1000) }

    @Throws(Exception::class)
    fun setNumber(habitId: Long, date: String, value: Double, notes: String) =
        mutate(habitId, date, true) { h, d ->
            require(value.isFinite()) { "value must be finite" }
            widgetBehavior.setValue(h, d, (value * 1000).roundToInt(), notes)
        }

    @Throws(Exception::class)
    fun setNotes(habitId: Long, date: String, notes: String) =
        mutate(habitId, date, null) { h, d ->
            val current = h.originalEntries.get(d).value
            commandRunner.run(CreateRepetitionCommand(habitList, h, d, current, notes))
        }

    /** Creates a habit and returns its new ID. Throws IllegalArgumentException on invalid input. */
    @Throws(Exception::class)
    fun createHabit(input: HabitInput): Long {
        refreshToday()
        validate(input)
        val model = modelFactory.buildHabit()
        apply(model, input)
        val before = habitList.mapNotNull { it.id }.toSet()
        commandRunner.run(CreateHabitCommand(modelFactory, habitList, model))
        return habitList.mapNotNull { it.id }.first { it !in before }
    }

    /** Edits a habit. Unknown ID is a no-op. The habit type cannot change. */
    @Throws(Exception::class)
    fun editHabit(habitId: Long, input: HabitInput) {
        refreshToday()
        validate(input)
        val existing = habitList.getById(habitId) ?: return
        require(existing.isNumerical == input.isNumerical) { "habit type cannot change" }
        val model = modelFactory.buildHabit()
        model.copyFrom(existing)
        apply(model, input)
        commandRunner.run(EditHabitCommand(habitList, habitId, model))
    }

    /** Deletes a habit and its entries. Unknown ID is a no-op. */
    @Throws(Exception::class)
    fun deleteHabit(habitId: Long) {
        refreshToday()
        val habit = habitList.getById(habitId) ?: return
        commandRunner.run(DeleteHabitsCommand(habitList, listOf(habit)))
    }

    /** Current values for pre-filling the edit screen, or null if the habit does not exist. */
    @Throws(Exception::class)
    fun habitInput(habitId: Long): HabitInput? {
        refreshToday()
        val h = habitList.getById(habitId) ?: return null
        return HabitInput(
            name = h.name,
            question = h.question,
            description = h.description,
            colorIndex = h.color.paletteIndex,
            isNumerical = h.isNumerical,
            unit = h.unit,
            targetValue = h.targetValue,
            targetType = h.targetType.value,
            freqNumerator = h.frequency.numerator,
            freqDenominator = h.frequency.denominator,
            reminder = reminderDto(h),
            category = h.category
        )
    }

    private fun validate(input: HabitInput) {
        require(input.name.isNotBlank()) { "name must not be blank" }
        require(input.freqNumerator >= 1) { "frequency numerator must be >= 1" }
        require(input.freqDenominator >= input.freqNumerator) { "frequency denominator must be >= numerator" }
        require(input.colorIndex in 0..19) { "colorIndex out of range" }
        if (input.isNumerical) {
            require(input.targetValue.isFinite() && input.targetValue >= 0 && input.targetValue <= MAX_TARGET_VALUE) {
                "targetValue must be finite and between 0 and $MAX_TARGET_VALUE"
            }
            require(input.targetType == NumericalHabitType.AT_LEAST.value || input.targetType == NumericalHabitType.AT_MOST.value) {
                "invalid targetType"
            }
        }
    }

    private fun apply(h: Habit, input: HabitInput) {
        h.name = input.name.trim()
        h.question = input.question.trim()
        h.description = input.description.trim()
        h.category = input.category.trim()
        h.color = PaletteColor(input.colorIndex)
        h.frequency = Frequency(input.freqNumerator, input.freqDenominator)
        if (input.isNumerical) {
            h.type = HabitType.NUMERICAL
            h.unit = input.unit.trim()
            h.targetValue = input.targetValue
            h.targetType = NumericalHabitType.fromInt(input.targetType)
        } else {
            h.type = HabitType.YES_NO
            h.unit = ""
            h.targetValue = 0.0
            h.targetType = NumericalHabitType.AT_LEAST
        }
        h.reminder = input.reminder?.let { r ->
            val packed = BooleanArray(7)
            for (i in 0..6) packed[(i + 1) % 7] = r.days[i]
            Reminder(r.hour, r.minute, WeekdayList(packed))
        }
    }

    private fun load() {
        loaded = false
        val db = databaseOpener.open(dbPath)
        try {
            if (db.getVersion() == 0) db.setVersion(8)
            runSync {
                db.migrateTo(DATABASE_VERSION) { v ->
                    val name = if (v < 10) "0$v" else "$v"
                    fileOpener.openResourceFile("migrations/$name.sql").lines().joinToString("\n")
                }
            }
        } catch (e: Throwable) {
            db.close()
            throw e
        }
        database = db
        modelFactory = SQLModelFactory(db)
        habitList = modelFactory.buildHabitList()
        val storage = KeyValueStorage(store)
        prefs = Preferences(storage)
        widgetPrefs = WidgetPreferences(storage)
        commandRunner = CommandRunner(SyncTaskRunner())
        widgetBehavior = WidgetBehavior(habitList, commandRunner, NoOpNotificationTray(commandRunner, prefs), prefs)
        lastToday = null
        loaded = true
    }

    /** Must be called first by every public method. */
    internal fun refreshToday(): LocalDate {
        check(loaded && database != null) { "LoopKit is closed" }
        val today = todaySource.today(prefs.midnightDelayHours)
        setToday(today)
        setFirstWeekday(prefs.firstWeekday)
        if (lastToday != today) {
            for (h in habitList) h.recompute()
            lastToday = today
        }
        return today
    }
}

private class NoOpSystemTray : NotificationTray.SystemTray {
    override fun removeNotification(notificationId: Int) {}
    override fun showNotification(habit: Habit, notificationId: Int, date: LocalDate, reminderTime: Long) {}
    override fun log(msg: String) {}
}

/** iOS notification cancelling is handled in Swift. */
private class NoOpNotificationTray(commandRunner: CommandRunner, prefs: Preferences) :
    NotificationTray(SyncTaskRunner(), commandRunner, prefs, NoOpSystemTray()) {
    override fun cancel(habit: Habit) {}
}
