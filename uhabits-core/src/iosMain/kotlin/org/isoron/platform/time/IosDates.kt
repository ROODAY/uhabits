@file:OptIn(ExperimentalForeignApi::class)

package org.isoron.platform.time

import kotlinx.cinterop.ExperimentalForeignApi
import platform.Foundation.NSCalendar
import platform.Foundation.NSCalendarIdentifierGregorian
import platform.Foundation.NSDate
import platform.Foundation.NSDateComponents
import platform.Foundation.NSDateFormatter
import platform.Foundation.NSLocale
import platform.Foundation.NSTimeZone
import platform.Foundation.localTimeZone
import platform.Foundation.localeWithLocaleIdentifier
import platform.Foundation.timeIntervalSince1970
import platform.Foundation.timeZoneWithAbbreviation

actual fun getFirstWeekdayNumberAccordingToLocale(): Int =
    NSCalendar.currentCalendar.firstWeekday.toInt()

actual fun computeToday(hourOffset: Int, minuteOffset: Int): LocalDate {
    val now = NSDate()
    val nowMillis = (now.timeIntervalSince1970 * 1000.0).toLong()
    val tzOffsetMillis = NSTimeZone.localTimeZone.secondsFromGMTForDate(now) * 1000L
    val localMillis = nowMillis + tzOffsetMillis
    val offsetMillis = hourOffset * 3600000L + minuteOffset * 60000L
    val adjustedMillis = localMillis - offsetMillis
    val daysSinceEpoch = adjustedMillis.floorDiv(86400000L)
    return LocalDate((daysSinceEpoch - 10957).toInt())
}

private val utc: NSTimeZone get() = NSTimeZone.timeZoneWithAbbreviation("UTC")!!

/**
 * Midday UTC for the given date, so that formatting in the UTC time zone never
 * drifts to an adjacent day.
 */
private fun LocalDate.toNsDate(): NSDate {
    val calendar = NSCalendar.calendarWithIdentifier(NSCalendarIdentifierGregorian)!!
    calendar.timeZone = utc
    val dc = NSDateComponents()
    dc.year = year.toLong()
    dc.month = month.toLong()
    dc.day = day.toLong()
    dc.hour = 12
    dc.minute = 0
    return calendar.dateFromComponents(dc)!!
}

class IosLocalDateFormatter(localeIdentifier: String) : LocalDateFormatter {
    private val locale = NSLocale.localeWithLocaleIdentifier(localeIdentifier)

    private fun fmt(pattern: String, date: LocalDate): String {
        val f = NSDateFormatter()
        f.locale = locale
        f.timeZone = utc
        f.dateFormat = pattern
        return f.stringFromDate(date.toNsDate())
    }

    // 2015-01-25 is a Sunday
    private fun dateOf(weekday: DayOfWeek) = LocalDate(2015, 1, 25 + weekday.daysSinceSunday)

    override fun narrowWeekdayName(weekday: DayOfWeek) = narrowWeekdayName(dateOf(weekday))
    override fun narrowWeekdayName(date: LocalDate) = fmt("EEEEE", date)
    override fun shortWeekdayName(weekday: DayOfWeek) = shortWeekdayName(dateOf(weekday))
    override fun shortWeekdayName(date: LocalDate) = fmt("EEE", date)
    override fun shortMonthName(date: LocalDate): String {
        // For some locales, such as Japanese, the short name is exceedingly short.
        val long = fmt("MMMM", date)
        return if (long.length <= 3) long else fmt("MMM", date)
    }
    override fun longWeekdayName(weekday: DayOfWeek) = fmt("EEEE", dateOf(weekday))
    override fun longMonthName(date: LocalDate) = fmt("MMMM", date)
}
