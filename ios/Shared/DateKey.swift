import Foundation

enum DateKey {
    /// "yyyy-MM-dd" for the calendar day of `date`.
    static func iso(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Parses "yyyy-MM-dd" into year/month/day components (empty components if malformed).
    static func date(fromIso s: String) -> DateComponents {
        let parts = s.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return DateComponents() }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
