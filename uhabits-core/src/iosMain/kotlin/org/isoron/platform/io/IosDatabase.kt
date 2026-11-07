@file:OptIn(ExperimentalForeignApi::class, BetaInteropApi::class)

package org.isoron.platform.io

import kotlinx.cinterop.BetaInteropApi
import kotlinx.cinterop.ByteVar
import kotlinx.cinterop.CPointer
import kotlinx.cinterop.CPointerVar
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.alloc
import kotlinx.cinterop.cstr
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.ptr
import kotlinx.cinterop.reinterpret
import kotlinx.cinterop.toKString
import kotlinx.cinterop.value
import platform.Foundation.NSFileManager
import sqlite3.SQLITE_DONE
import sqlite3.SQLITE_NULL
import sqlite3.SQLITE_OK
import sqlite3.SQLITE_OPEN_CREATE
import sqlite3.SQLITE_OPEN_FULLMUTEX
import sqlite3.SQLITE_OPEN_READWRITE
import sqlite3.SQLITE_ROW
import sqlite3.SQLITE_TRANSIENT
import sqlite3.sqlite3
import sqlite3.sqlite3_bind_double
import sqlite3.sqlite3_bind_int
import sqlite3.sqlite3_bind_int64
import sqlite3.sqlite3_bind_null
import sqlite3.sqlite3_bind_text
import sqlite3.sqlite3_close
import sqlite3.sqlite3_column_double
import sqlite3.sqlite3_column_int
import sqlite3.sqlite3_column_int64
import sqlite3.sqlite3_column_text
import sqlite3.sqlite3_column_type
import sqlite3.sqlite3_errmsg
import sqlite3.sqlite3_finalize
import sqlite3.sqlite3_open_v2
import sqlite3.sqlite3_prepare_v2
import sqlite3.sqlite3_reset
import sqlite3.sqlite3_step
import sqlite3.sqlite3_stmt

private fun sqliteError(db: CPointer<sqlite3>?, what: String, code: Int): Exception {
    val msg = if (db != null) sqlite3_errmsg(db)?.toKString() else null
    return Exception("$what failed (code $code): $msg")
}

class IosDatabaseOpener : DatabaseOpener {
    override fun open(path: String): Database = memScoped {
        if (path != ":memory:" && path.isNotEmpty()) {
            val lastSlash = path.lastIndexOf('/')
            if (lastSlash > 0) {
                NSFileManager.defaultManager.createDirectoryAtPath(
                    path.substring(0, lastSlash),
                    true,
                    null,
                    null
                )
            }
        }

        val dbVar = alloc<CPointerVar<sqlite3>>()
        val flags = SQLITE_OPEN_READWRITE or SQLITE_OPEN_CREATE or SQLITE_OPEN_FULLMUTEX
        val result = sqlite3_open_v2(path, dbVar.ptr, flags, null)
        val db = dbVar.value
        if (result != SQLITE_OK) {
            val e = sqliteError(db, "sqlite3_open_v2", result)
            if (db != null) sqlite3_close(db)
            throw e
        }
        val database = IosDatabase(db!!)
        val pragma = database.prepareStatement("PRAGMA busy_timeout = 3000")
        pragma.step()
        pragma.finalize()
        database
    }
}

class IosDatabase(val db: CPointer<sqlite3>) : Database {
    override fun prepareStatement(sql: String): PreparedStatement = memScoped {
        if (sql.isEmpty()) throw Exception("empty SQL query")
        val stmt = alloc<CPointerVar<sqlite3_stmt>>()
        val result = sqlite3_prepare_v2(db, sql.cstr.ptr, -1, stmt.ptr, null)
        if (result != SQLITE_OK) throw sqliteError(db, "sqlite3_prepare_v2", result)
        IosPreparedStatement(db, stmt.value!!)
    }

    override fun close() {
        sqlite3_close(db)
    }
}

class IosPreparedStatement(
    private val db: CPointer<sqlite3>,
    private val stmt: CPointer<sqlite3_stmt>
) : PreparedStatement {
    override fun step(): StepResult {
        val code = sqlite3_step(stmt)
        return when (code) {
            SQLITE_ROW -> StepResult.ROW
            SQLITE_DONE -> StepResult.DONE
            else -> throw sqliteError(db, "sqlite3_step", code)
        }
    }

    override fun finalize() {
        sqlite3_finalize(stmt)
    }

    private fun isNull(index: Int) = sqlite3_column_type(stmt, index) == SQLITE_NULL

    override fun getInt(index: Int): Int = sqlite3_column_int(stmt, index)
    override fun getLong(index: Int): Long = sqlite3_column_int64(stmt, index)
    override fun getReal(index: Int): Double = sqlite3_column_double(stmt, index)
    override fun getText(index: Int): String = getTextOrNull(index) ?: ""

    override fun getIntOrNull(index: Int): Int? = if (isNull(index)) null else getInt(index)
    override fun getLongOrNull(index: Int): Long? = if (isNull(index)) null else getLong(index)
    override fun getRealOrNull(index: Int): Double? = if (isNull(index)) null else getReal(index)
    override fun getTextOrNull(index: Int): String? {
        if (isNull(index)) return null
        return sqlite3_column_text(stmt, index)?.reinterpret<ByteVar>()?.toKString()
    }

    override fun bindInt(index: Int, value: Int) {
        sqlite3_bind_int(stmt, index + 1, value)
    }

    override fun bindLong(index: Int, value: Long) {
        sqlite3_bind_int64(stmt, index + 1, value)
    }

    override fun bindReal(index: Int, value: Double) {
        sqlite3_bind_double(stmt, index + 1, value)
    }

    override fun bindText(index: Int, value: String) {
        sqlite3_bind_text(stmt, index + 1, value, -1, SQLITE_TRANSIENT)
    }

    override fun bindNull(index: Int) {
        sqlite3_bind_null(stmt, index + 1)
    }

    override fun reset() {
        sqlite3_reset(stmt)
    }
}
