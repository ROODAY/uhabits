package org.isoron.uhabits.ioskit

import org.isoron.platform.io.IosDatabaseOpener
import org.isoron.platform.io.IosFileOpener

fun createLoopKit(dbPath: String, resourcesPath: String, store: KeyValueStore): LoopKit {
    val dir = dbPath.substringBeforeLast('/', "")
    return LoopKit(
        IosDatabaseOpener(),
        IosFileOpener(listOf(resourcesPath), dir),
        dbPath,
        store
    )
}
