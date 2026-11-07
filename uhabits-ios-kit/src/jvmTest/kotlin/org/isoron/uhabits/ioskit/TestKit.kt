package org.isoron.uhabits.ioskit

import org.isoron.platform.io.JavaDatabaseOpener
import org.isoron.platform.io.JavaFileOpener
import org.isoron.platform.time.LocalDate
import java.io.File

class MapStore : KeyValueStore {
    val map = mutableMapOf<String, String>()
    override fun getString(key: String): String? = map[key]
    override fun putString(key: String, value: String) {
        map[key] = value
    }
    override fun remove(key: String) {
        map.remove(key)
    }
    override fun clear() = map.clear()
}

fun testKit(dir: File, today: LocalDate = LocalDate(2015, 1, 25)): Pair<LoopKit, MapStore> =
    testKit(dir, MapStore(), today)

fun testKit(dir: File, store: MapStore, today: LocalDate = LocalDate(2015, 1, 25)): Pair<LoopKit, MapStore> {
    val kit = LoopKit(
        JavaDatabaseOpener(),
        JavaFileOpener(),
        File(dir, "loop.db").absolutePath,
        store,
        TodaySource { today }
    )
    return Pair(kit, store)
}
