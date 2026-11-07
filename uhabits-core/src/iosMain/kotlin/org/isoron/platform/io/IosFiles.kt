@file:OptIn(ExperimentalForeignApi::class, BetaInteropApi::class)

package org.isoron.platform.io

import kotlinx.cinterop.BetaInteropApi
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.usePinned
import org.isoron.platform.gui.Image
import platform.Foundation.NSBundle
import platform.Foundation.NSData
import platform.Foundation.NSDocumentDirectory
import platform.Foundation.NSFileManager
import platform.Foundation.NSString
import platform.Foundation.NSURL
import platform.Foundation.NSUTF8StringEncoding
import platform.Foundation.NSUserDomainMask
import platform.Foundation.create
import platform.Foundation.dataWithContentsOfFile
import platform.Foundation.stringWithContentsOfFile
import platform.Foundation.writeToFile
import platform.posix.memcpy

/**
 * @param resourceRoots directories searched in order for bundled resources;
 *   the first root containing the requested path wins.
 * @param userRoot directory against which user file paths are resolved.
 */
class IosFileOpener(
    private val resourceRoots: List<String>,
    private val userRoot: String
) : FileOpener {
    constructor() : this(
        listOf(NSBundle.mainBundle.resourcePath ?: ""),
        defaultDocumentsPath()
    )

    override fun openResourceFile(path: String): ResourceFile {
        val fm = NSFileManager.defaultManager
        val resolved = resourceRoots
            .map { "$it/$path" }
            .firstOrNull { fm.fileExistsAtPath(it) }
            ?: "${resourceRoots.first()}/$path"
        return IosResourceFile(resolved)
    }

    override fun openUserFile(path: String): UserFile = IosUserFile("$userRoot/$path")
}

private fun defaultDocumentsPath(): String {
    val urls = NSFileManager.defaultManager.URLsForDirectory(NSDocumentDirectory, NSUserDomainMask)
    return (urls.first() as NSURL).path!!
}

private fun parentOf(path: String): String {
    val i = path.trimEnd('/').lastIndexOf('/')
    return if (i <= 0) "/" else path.substring(0, i)
}

private fun readLinesOf(path: String): List<String> {
    if (!NSFileManager.defaultManager.fileExistsAtPath(path)) {
        throw Exception("File not found: $path")
    }
    val contents = NSString.stringWithContentsOfFile(path, NSUTF8StringEncoding, null)
        ?: throw Exception("Could not read file: $path")
    val lines = (contents as String).split("\r\n", "\n", "\r")
    // Match java.nio.file.Files.readAllLines: a trailing newline adds no extra line.
    return if (lines.isNotEmpty() && lines.last().isEmpty()) lines.dropLast(1) else lines
}

class IosResourceFile(val path: String) : ResourceFile {
    override suspend fun copyTo(dest: UserFile) {
        val to = (dest as IosUserFile).path
        val fm = NSFileManager.defaultManager
        fm.createDirectoryAtPath(parentOf(to), true, null, null)
        if (fm.fileExistsAtPath(to)) fm.removeItemAtPath(to, null)
        if (!fm.copyItemAtPath(path, to, null)) throw Exception("Could not copy $path to $to")
    }

    override suspend fun lines(): List<String> = readLinesOf(path)

    override suspend fun exists(): Boolean = NSFileManager.defaultManager.fileExistsAtPath(path)

    override suspend fun toImage(): Image {
        throw UnsupportedOperationException("images are rendered natively on iOS")
    }
}

class IosUserFile(val path: String) : UserFile {
    override val pathString: String
        get() = path

    override suspend fun delete() {
        NSFileManager.defaultManager.removeItemAtPath(path, null)
    }

    override suspend fun exists(): Boolean = NSFileManager.defaultManager.fileExistsAtPath(path)

    override suspend fun lines(): List<String> = readLinesOf(path)

    override suspend fun writeString(content: String) {
        writeBytes(content.encodeToByteArray())
    }

    override suspend fun writeBytes(bytes: ByteArray) {
        NSFileManager.defaultManager.createDirectoryAtPath(parentOf(path), true, null, null)
        val data = if (bytes.isEmpty()) {
            NSData()
        } else {
            bytes.usePinned { NSData.create(bytes = it.addressOf(0), length = bytes.size.toULong()) }
        }
        if (!data.writeToFile(path, true)) throw Exception("Could not write file: $path")
    }

    override suspend fun readBytes(limit: Int): ByteArray {
        val data = NSData.dataWithContentsOfFile(path) ?: throw Exception("File not found: $path")
        val n = minOf(limit.toULong(), data.length).toInt()
        val result = ByteArray(n)
        if (n > 0) {
            result.usePinned { memcpy(it.addressOf(0), data.bytes, n.toULong()) }
        }
        return result
    }

    override fun resolve(child: String): UserFile = IosUserFile("${path.trimEnd('/')}/$child")

    override suspend fun listFiles(): List<UserFile>? {
        val names = NSFileManager.defaultManager.contentsOfDirectoryAtPath(path, null) ?: return null
        return names.map { IosUserFile("${path.trimEnd('/')}/$it") }
    }

    override suspend fun mkdirs() {
        NSFileManager.defaultManager.createDirectoryAtPath(path, true, null, null)
    }
}
