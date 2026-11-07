package org.isoron.uhabits.ioskit

import org.isoron.platform.io.Database
import org.isoron.platform.io.DatabaseOpener
import org.isoron.platform.io.FileOpener
import org.isoron.platform.io.getVersion
import org.isoron.platform.io.migrateTo
import org.isoron.platform.io.setVersion
import org.isoron.platform.time.LocalDate
import org.isoron.platform.time.computeToday
import org.isoron.platform.time.setFirstWeekday
import org.isoron.platform.time.setToday
import org.isoron.uhabits.core.DATABASE_VERSION
import org.isoron.uhabits.core.commands.CommandRunner
import org.isoron.uhabits.core.models.Entry
import org.isoron.uhabits.core.models.HabitList
import org.isoron.uhabits.core.models.sqlite.SQLModelFactory
import org.isoron.uhabits.core.preferences.Preferences
import org.isoron.uhabits.core.preferences.WidgetPreferences
import org.isoron.uhabits.core.ui.views.DarkTheme
import org.isoron.uhabits.core.ui.views.LightTheme
import org.isoron.uhabits.core.ui.views.Theme
import kotlin.math.roundToInt

fun interface TodaySource {
    fun today(midnightDelayHours: Int): LocalDate
}

/**
 * Facade over the habit core. NOT thread-safe: callers (the Swift actor) must
 * serialize all calls, including reload() and close().
 */
class LoopKit(
    private val databaseOpener: DatabaseOpener,
    private val fileOpener: FileOpener,
    private val dbPath: String,
    private val store: KeyValueStore,
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

    private var lastToday: LocalDate? = null
    private var loaded = false

    init {
        load()
    }

    /** Closes and reopens the database, picking up writes made by other processes. */
    fun reload() {
        close()
        load()
    }

    fun close() {
        loaded = false
        try {
            database?.close()
        } finally {
            database = null
        }
    }

    fun listHabits(dayCount: Int, includeArchived: Boolean): List<HabitRow> {
        val today = refreshToday()
        return habitList
            .filter { includeArchived || !it.isArchived }
            .sortedBy { it.position }
            .map { h ->
                val days = (0 until maxOf(dayCount, 0)).map { i ->
                    val date = today.minus(i)
                    val e = h.computedEntries.get(date)
                    val raw = e.value
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
                HabitRow(
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
                    days = days
                )
            }
    }

    /** 20 RGB ints (0xRRGGBB) for palette indices 0..19. */
    fun palette(dark: Boolean): List<Int> {
        val theme: Theme = if (dark) DarkTheme() else LightTheme()
        return (0 until 20).map { i ->
            val c = theme.color(i)
            (channel(c.red) shl 16) or (channel(c.green) shl 8) or channel(c.blue)
        }
    }

    private fun channel(v: Double): Int = (v * 255.0).roundToInt().coerceIn(0, 255)

    fun today(): String = refreshToday().iso()

    fun midnightDelayHours(): Int {
        refreshToday()
        return prefs.midnightDelayHours
    }

    fun areQuestionMarksEnabled(): Boolean {
        refreshToday()
        return prefs.areQuestionMarksEnabled
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
