package org.isoron.platform.io

import org.isoron.uhabits.core.DATABASE_VERSION

actual object TestDatabaseHelper {
    actual suspend fun createEmptyDatabase(): Database {
        val db = IosDatabaseOpener().open(":memory:")
        db.setVersion(8)
        db.migrateTo(DATABASE_VERSION) { v -> loadMigrationSQL(v) }
        return db
    }

    actual suspend fun loadMigrationSQL(version: Int): String {
        val path = format("migrations/%02d.sql", version)
        return createTestFileOpener().openResourceFile(path).lines().joinToString("\n")
    }
}
