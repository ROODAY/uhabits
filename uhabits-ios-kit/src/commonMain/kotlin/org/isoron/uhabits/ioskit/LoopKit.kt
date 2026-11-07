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
import org.isoron.uhabits.core.models.HabitList
import org.isoron.uhabits.core.models.sqlite.SQLModelFactory
import org.isoron.uhabits.core.preferences.Preferences
import org.isoron.uhabits.core.preferences.WidgetPreferences

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

    init {
        load()
    }

    /** Closes and reopens the database, picking up writes made by other processes. */
    fun reload() {
        close()
        load()
    }

    fun close() {
        database?.close()
        database = null
    }

    private fun load() {
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
    }

    /** Must be called first by every public method. */
    internal fun refreshToday() {
        val today = todaySource.today(prefs.midnightDelayHours)
        setToday(today)
        setFirstWeekday(prefs.firstWeekday)
        if (lastToday != today) {
            for (h in habitList) h.recompute()
            lastToday = today
        }
    }
}
