import AppIntents
import Foundation
import UserNotifications
import LoopKit

/// Store access that respects the DB lock rule (design 6.3): the widget extension always closes the
/// store before returning; in the app, the store is closed only when the UI is not in the foreground.
enum HabitStoreAccess {
    static func read<T>(_ body: (LoopKit) throws -> T) async throws -> T {
        do {
            let r = try await LoopStore.shared.withKit(body)
            await closeIfAllowed()
            return r
        } catch {
            await closeIfAllowed()
            throw error
        }
    }

    static func closeIfAllowed() async {
        await NotificationPlanner.closeStoreIfInactive()
    }
}

enum HabitAction { case toggle, increment, decrement }

enum HabitActions {
    /// Applies the action for today. Never throws: a deleted habit or a store failure is a no-op.
    static func run(_ action: HabitAction, habitId: Int64) async {
        do {
            try await LoopStore.shared.mutate { kit in
                let today = try kit.today()
                switch action {
                case .toggle: try kit.toggle(habitId: habitId, date: today)
                case .increment: try kit.increment(habitId: habitId, date: today)
                case .decrement: try kit.decrement(habitId: habitId, date: today)
                }
            }
        } catch {}
        // Re-plan reminders before finishing (design 6.4): restores today's reminder after an un-check and
        // suppresses reminders of completed periods. Reuses the open kit, then closes it unless the app UI is up.
        await NotificationPlanner.reschedule()
        await NotificationPlanner.closeStoreIfInactive()
    }
}

struct ToggleHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Check off habit"
    static let description = IntentDescription("Toggles a habit for today.")
    @Parameter(title: "Habit") var habit: HabitEntity
    init() {}
    init(habit: HabitEntity) { self.habit = habit }
    func perform() async throws -> some IntentResult {
        await HabitActions.run(.toggle, habitId: habit.habitId)
        return .result()
    }
}

struct IncrementHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Add one to habit"
    @Parameter(title: "Habit") var habit: HabitEntity
    init() {}
    init(habit: HabitEntity) { self.habit = habit }
    func perform() async throws -> some IntentResult {
        await HabitActions.run(.increment, habitId: habit.habitId)
        return .result()
    }
}

struct DecrementHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Subtract one from habit"
    @Parameter(title: "Habit") var habit: HabitEntity
    init() {}
    init(habit: HabitEntity) { self.habit = habit }
    func perform() async throws -> some IntentResult {
        await HabitActions.run(.decrement, habitId: habit.habitId)
        return .result()
    }
}
