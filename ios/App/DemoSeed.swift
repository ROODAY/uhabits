import Foundation
import LoopKit

enum DemoSeed {
    static let flag = "--seed-demo"

    /// Creates the demo habits and 30 days of entries, only if the list is empty.
    /// Returns true if it seeded.
    @discardableResult
    static func seedIfEmpty(_ store: LoopStore) async throws -> Bool {
        let existing = try await store.withKit { try $0.listHabits(dayCount: 1, includeArchived: true) }
        guard existing.isEmpty else { return false }

        func input(_ name: String, color: Int32, numerical: Bool) -> HabitInput {
            HabitInput(name: name, question: "", description: "", colorIndex: color,
                       isNumerical: numerical, unit: numerical ? "glasses" : "",
                       targetValue: numerical ? 8 : 0, targetType: 0,
                       freqNumerator: 1, freqDenominator: 1, reminder: nil)
        }
        let specs: [(String, Int32, Bool)] = [
            ("Meditate", 0, false), ("Exercise", 5, false), ("Read", 11, false), ("Water", 8, true),
        ]
        var ids: [Int64] = []
        for s in specs {
            let id = try await store.withKit { try $0.createHabit(input: input(s.0, color: s.1, numerical: s.2)) }
            ids.append(id)
        }
        // Dates come from the facade (newest first), so Swift does no date math.
        let rows = try await store.withKit { try $0.listHabits(dayCount: 30, includeArchived: false) }
        let dates = (rows.first?.days ?? []).map { $0.date }
        let habitIds = ids
        try await store.mutate { kit in
            for (dayIndex, date) in dates.enumerated() {
                // Deterministic, varied patterns.
                if dayIndex % 3 != 2 { try kit.toggle(habitId: habitIds[0], date: date) }
                if dayIndex % 2 == 0 { try kit.toggle(habitId: habitIds[1], date: date) }
                if dayIndex % 5 != 4 && dayIndex % 7 != 3 { try kit.toggle(habitId: habitIds[2], date: date) }
                if dayIndex % 4 != 3 {
                    let glasses = Double((dayIndex * 3) % 10) + (dayIndex % 2 == 0 ? 0.5 : 0)
                    try kit.setNumber(habitId: habitIds[3], date: date, value: glasses, notes: "")
                }
            }
        }
        return true
    }
}
