package org.isoron.uhabits.ioskit

import org.isoron.uhabits.core.preferences.Preferences

/** Implemented in Swift over UserDefaults(suiteName:). */
interface KeyValueStore {
    fun getString(key: String): String?
    fun putString(key: String, value: String)
    fun remove(key: String)
    fun clear()
}

/** Adapts a [KeyValueStore] to the core preference storage. Non-string values are stored via toString(). */
internal class KeyValueStorage(private val store: KeyValueStore) : Preferences.Storage {
    override fun clear() = store.clear()

    override fun getBoolean(key: String, defValue: Boolean): Boolean =
        store.getString(key)?.toBooleanStrictOrNull() ?: defValue

    override fun getInt(key: String, defValue: Int): Int =
        store.getString(key)?.toIntOrNull() ?: defValue

    override fun getLong(key: String, defValue: Long): Long =
        store.getString(key)?.toLongOrNull() ?: defValue

    override fun getString(key: String, defValue: String): String =
        store.getString(key) ?: defValue

    override fun putBoolean(key: String, value: Boolean) = store.putString(key, value.toString())
    override fun putInt(key: String, value: Int) = store.putString(key, value.toString())
    override fun putLong(key: String, value: Long) = store.putString(key, value.toString())
    override fun putString(key: String, value: String) = store.putString(key, value)
    override fun remove(key: String) = store.remove(key)
}
