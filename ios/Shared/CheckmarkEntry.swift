import Foundation
import WidgetKit
import LoopKit

/// Pure value for one widget render. Built from a facade `HabitRow`; no habit logic here.
struct CheckmarkEntry: TimelineEntry, Equatable {
    enum Kind: Equatable {
        case habit
        case removed      // configured habit no longer exists
        case choose       // fresh widget, nothing configured yet
        case needsSetup   // store could not be opened
    }

    var date: Date
    var kind: Kind
    var habitId: Int64 = 0
    var name: String = ""
    var isNumerical = false
    var unit = ""
    var target: Double = 0
    var value: Double = 0
    var score: Double = 0
    var isDone = false
    var colorHex: Int = 0x808080
    var darkColorHex: Int = 0x808080

    /// nil row gives the "habit removed" state. Palettes are the facade's `palette(dark:)` values.
    static func make(row: HabitRow?, palette: [Int] = [], darkPalette: [Int] = [], date: Date = Date()) -> CheckmarkEntry {
        guard let row else { return CheckmarkEntry(date: date, kind: .removed) }
        func hex(_ p: [Int]) -> Int {
            let i = Int(row.colorIndex)
            return i >= 0 && i < p.count ? p[i] : 0x808080
        }
        return CheckmarkEntry(
            date: date, kind: .habit, habitId: row.id, name: row.name,
            isNumerical: row.isNumerical, unit: row.unit, target: row.targetValue,
            value: row.days.first?.value ?? 0, score: row.score,
            isDone: row.isCompletedToday, colorHex: hex(palette), darkColorHex: hex(darkPalette))
    }

    static func choose(date: Date = Date()) -> CheckmarkEntry { CheckmarkEntry(date: date, kind: .choose) }
    static func needsSetup(date: Date = Date()) -> CheckmarkEntry { CheckmarkEntry(date: date, kind: .needsSetup) }

    /// Refresh schedule only (not habit logic): the next local midnight plus the user's midnight delay.
    static func nextRefresh(after now: Date, delayHours: Int, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: now)
        let todays = calendar.date(byAdding: .hour, value: delayHours, to: start) ?? start
        if todays > now { return todays }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        return calendar.date(byAdding: .hour, value: delayHours, to: tomorrow) ?? tomorrow
    }

    static func format(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        return r.isFinite && abs(r) < 1e15 && r == r.rounded() ? String(Int(r)) : String(r)
    }
}
