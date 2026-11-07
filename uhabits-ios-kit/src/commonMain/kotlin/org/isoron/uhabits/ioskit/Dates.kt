package org.isoron.uhabits.ioskit

import org.isoron.platform.time.LocalDate

private fun pad(n: Int, width: Int): String = n.toString().padStart(width, '0')

/** Formats as `yyyy-MM-dd`, zero-padded. */
internal fun LocalDate.iso(): String = "${pad(year, 4)}-${pad(month, 2)}-${pad(day, 2)}"

/** Parses `yyyy-MM-dd`. Throws IllegalArgumentException on malformed input. */
internal fun parseIso(s: String): LocalDate {
    val parts = s.split("-")
    require(parts.size == 3) { "Invalid ISO date: $s" }
    val y = parts[0].toIntOrNull()
    val m = parts[1].toIntOrNull()
    val d = parts[2].toIntOrNull()
    require(y != null && m != null && d != null && m in 1..12 && d in 1..31) { "Invalid ISO date: $s" }
    val result = LocalDate(y, m, d)
    require(result.iso() == s) { "Invalid ISO date: $s" }
    return result
}
