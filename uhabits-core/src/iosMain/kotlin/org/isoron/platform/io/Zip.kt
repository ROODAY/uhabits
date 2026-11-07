package org.isoron.platform.io

actual class ZipReader actual constructor(bytes: ByteArray) {
    actual suspend fun entries(): List<ZipEntry> {
        throw UnsupportedOperationException("zip: phase 4")
    }
}

actual class ZipWriter actual constructor() {
    actual fun addEntry(name: String, content: String) {
        throw UnsupportedOperationException("zip: phase 4")
    }

    actual suspend fun toBytes(): ByteArray {
        throw UnsupportedOperationException("zip: phase 4")
    }
}
