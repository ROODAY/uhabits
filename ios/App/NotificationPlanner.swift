import Foundation
import UIKit
import UserNotifications
import LoopKit

/// Single source of truth for "UI is in use" (R-T14h). Set synchronously by the scenePhase handler;
/// stays false on background launches (notification actions, BGTasks).
@MainActor
enum AppActivity {
    static var isForeground = false
}

/// Pre-schedules concrete reminder occurrences computed by the facade (iOS cannot run code at fire time).
/// App-only: shared intents call `reschedule()` under `#if LOOP_APP`.
enum NotificationPlanner {
    static let maxPending = 60
    static let snoozeMinutes = 15
    static let yesNoCategory = "HABIT_YESNO"
    static let numericalCategory = "HABIT_NUMERICAL"
    static let doneAction = "DONE"
    static let snoozeAction = "SNOOZE"
    static let habitPrefix = "habit-"
    static let snoozePrefix = "snooze-"

    // MARK: Pure

    static func identifier(habitId: Int64, date: String) -> String { "\(habitPrefix)\(habitId)-\(date)" }
    static func snoozeIdentifier(habitId: Int64) -> String { "\(snoozePrefix)\(habitId)" }

    static func requests(for occurrences: [ReminderOccurrence], calendar: Calendar) -> [UNNotificationRequest] {
        occurrences.prefix(maxPending).map { o in
            let content = UNMutableNotificationContent()
            content.title = o.habitName
            content.body = o.question
            content.sound = .default
            content.categoryIdentifier = o.isNumerical ? numericalCategory : yesNoCategory
            content.userInfo = ["habitId": o.habitId, "date": o.date]
            var c = DateKey.date(fromIso: o.date)
            c.calendar = calendar
            c.hour = Int(o.hour)
            c.minute = Int(o.minute)
            let trigger = UNCalendarNotificationTrigger(dateMatching: c, repeats: false)
            return UNNotificationRequest(identifier: identifier(habitId: o.habitId, date: o.date),
                                         content: content, trigger: trigger)
        }
    }

    /// Identifiers to clear for habits completed today (R-T14c).
    static func cleanupIdentifiers(completedRows: [(id: Int64, today: String)]) -> (pending: [String], delivered: [String]) {
        var pending: [String] = []
        var delivered: [String] = []
        for r in completedRows {
            pending.append(snoozeIdentifier(habitId: r.id))
            delivered.append(identifier(habitId: r.id, date: r.today))
            delivered.append(snoozeIdentifier(habitId: r.id))
        }
        return (pending, delivered)
    }

    static func categories() -> Set<UNNotificationCategory> {
        let done = UNNotificationAction(identifier: doneAction, title: "Done", options: [])
        let snooze = UNNotificationAction(identifier: snoozeAction, title: "Snooze \(snoozeMinutes) min", options: [])
        return [
            UNNotificationCategory(identifier: yesNoCategory, actions: [done, snooze], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: numericalCategory, actions: [snooze], intentIdentifiers: [], options: []),
        ]
    }

    static func snoozeRequest(from content: UNNotificationContent, habitId: Int64) -> UNNotificationRequest {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(snoozeMinutes * 60), repeats: false)
        return UNNotificationRequest(identifier: snoozeIdentifier(habitId: habitId), content: content, trigger: trigger)
    }

    // MARK: Side effects

    private static let lock = NSLock()
    private static var chain: Task<Void, Never>?

    private static func enqueue(_ work: @escaping () async -> Void) -> Task<Void, Never> {
        lock.lock()
        defer { lock.unlock() }
        let previous = chain
        let task = Task {
            await previous?.value
            await work()
        }
        chain = task
        return task
    }

    /// Installs the LoopStore hook so every mutation reschedules (R-T14b). Idempotent.
    static func installHook() async {
        await LoopStore.shared.setAfterMutation { await NotificationPlanner.reschedule() }
    }

    /// Replaces pending `habit-*` requests with the facade's upcoming occurrences. Concurrent calls are serialized.
    /// Closes the store afterwards when the app is not active (R-T14a).
    static func reschedule(closeIfInactive: Bool = true) async {
        await enqueue { await performReschedule(closeIfInactive: closeIfInactive) }.value
    }

    private static func performReschedule(closeIfInactive: Bool) async {
        let now = Date()
        var result: ([ReminderOccurrence], [HabitRow])?
        do {
            result = try await LoopStore.shared.withKit { kit in
                (try kit.upcomingReminders(nowDate: DateKey.iso(now), nowMinuteOfDay: Int32(DateKey.minuteOfDay(now)),
                                           horizonDays: 14, maxCount: Int32(maxPending)),
                 try kit.listHabits(dayCount: 1, includeArchived: false))
            }
        } catch {}
        if shouldClose(isForeground: await isForeground(), closeIfInactive: closeIfInactive) { await LoopStore.shared.close() }
        guard let (occurrences, rows) = result else { return }

        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map { $0.identifier }.filter { $0.hasPrefix(habitPrefix) })
        for r in requests(for: occurrences, calendar: .current) {
            try? await center.add(r)
        }

        let completed = rows.filter { $0.isCompletedToday }.map { (id: $0.id, today: $0.today) }
        let ids = cleanupIdentifiers(completedRows: completed)
        center.removePendingNotificationRequests(withIdentifiers: ids.pending)
        center.removeDeliveredNotifications(withIdentifiers: ids.delivered)
    }

    /// Close the store iff the app is not in the foreground and the caller asked for it (R-T14a/h).
    static func shouldClose(isForeground: Bool, closeIfInactive: Bool) -> Bool {
        closeIfInactive && !isForeground
    }

    static func isForeground() async -> Bool {
        await MainActor.run { AppActivity.isForeground }
    }

    // MARK: Permission

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func notificationsDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// On launch: ask for permission if any habit has an upcoming reminder (R-T14e).
    static func requestAuthorizationIfRemindersExist() async {
        let any = (try? await LoopStore.shared.withKit { kit -> Bool in
            let now = Date()
            return !(try kit.upcomingReminders(nowDate: DateKey.iso(now), nowMinuteOfDay: Int32(DateKey.minuteOfDay(now)),
                                               horizonDays: 14, maxCount: 1)).isEmpty
        }) ?? false
        if any { await requestAuthorization() }
    }
}
