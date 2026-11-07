@file:OptIn(ExperimentalForeignApi::class)

package org.isoron.platform.io

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.toKString
import org.isoron.platform.gui.Canvas
import org.isoron.platform.time.IosLocalDateFormatter
import org.isoron.platform.time.LocalDateFormatter
import platform.Foundation.NSTemporaryDirectory
import platform.Foundation.NSUUID
import platform.posix.getenv

private val tempUserRoot: String by lazy {
    NSTemporaryDirectory().trimEnd('/') + "/loop-test-" + NSUUID().UUIDString
}

actual fun createTestFileOpener(): FileOpener {
    val assets = getenv("LOOP_TEST_ASSETS")?.toKString()
        ?: error("LOOP_TEST_ASSETS environment variable is not set")
    return IosFileOpener(listOf("$assets/main", "$assets/test"), tempUserRoot)
}

actual fun createTestDatabaseOpener(): DatabaseOpener = IosDatabaseOpener()
actual suspend fun createTestDatabaseOpenerSuspend(): DatabaseOpener = IosDatabaseOpener()

actual fun createTestCanvas(width: Int, height: Int): Canvas =
    throw UnsupportedOperationException("canvas is not supported on iOS")

actual fun createTestDateFormatter(): LocalDateFormatter = IosLocalDateFormatter("en_US")

actual suspend fun ensureFontsLoaded() {
    throw UnsupportedOperationException("fonts are not supported on iOS")
}
