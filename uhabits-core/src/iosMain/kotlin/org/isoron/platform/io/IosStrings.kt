@file:OptIn(ExperimentalForeignApi::class)

package org.isoron.platform.io

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.cstr
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.toKString
import kotlinx.cinterop.usePinned

// One overload per type: Kotlin/Native cannot do type conversions for Any
// when calling C variadic functions.

private const val BUFFER_SIZE = 1024

actual fun format(format: String, arg: String): String = memScoped {
    val buffer = ByteArray(BUFFER_SIZE)
    val cArg = arg.cstr.getPointer(this)
    buffer.usePinned { p ->
        platform.posix.snprintf(p.addressOf(0), BUFFER_SIZE.toULong(), format, cArg)
    }
    buffer.toKString()
}

actual fun format(format: String, arg: Int): String {
    val buffer = ByteArray(BUFFER_SIZE)
    buffer.usePinned { p ->
        platform.posix.snprintf(p.addressOf(0), BUFFER_SIZE.toULong(), format, arg)
    }
    return buffer.toKString()
}

actual fun format(format: String, arg: Double): String {
    val buffer = ByteArray(BUFFER_SIZE)
    buffer.usePinned { p ->
        platform.posix.snprintf(p.addressOf(0), BUFFER_SIZE.toULong(), format, arg)
    }
    return buffer.toKString()
}
