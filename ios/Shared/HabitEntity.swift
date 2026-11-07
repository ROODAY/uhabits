import AppIntents
import LoopKit

/// A habit as seen by Shortcuts / widget configuration. `id` is Int (== Int64 on all iOS devices)
/// because Int is a supported entity identifier type.
struct HabitEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Habit"
    static let defaultQuery = HabitQuery()

    var id: Int
    var name: String

    var habitId: Int64 { Int64(id) }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct HabitQuery: EntityQuery {
    func entities(for identifiers: [Int]) async throws -> [HabitEntity] {
        try await all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [HabitEntity] {
        try await all()
    }

    private func all() async throws -> [HabitEntity] {
        let rows = try await HabitStoreAccess.read { try $0.listHabits(dayCount: 0, includeArchived: false) }
        return rows.map { HabitEntity(id: Int($0.id), name: $0.name) }
    }
}
