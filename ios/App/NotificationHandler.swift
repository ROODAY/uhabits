import Foundation
import UserNotifications
import LoopKit

/// Pending deep link from a numerical-habit notification tap (R-T14d).
@MainActor
final class NotificationRouter: ObservableObject {
    struct Pending: Equatable {
        let habitId: Int64
        let date: String
    }
    static let shared = NotificationRouter()
    @Published var pending: Pending?
}

final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationHandler()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await NotificationPlanner.installHook()
        let content = response.notification.request.content
        let info = content.userInfo
        let habitId = (info["habitId"] as? NSNumber)?.int64Value
        let date = info["date"] as? String

        guard let habitId else {
            await NotificationPlanner.reschedule()
            return
        }
        switch response.actionIdentifier {
        case NotificationPlanner.doneAction:
            await done(habitId: habitId, date: date, requestId: response.notification.request.identifier)
        case NotificationPlanner.snoozeAction:
            await snooze(habitId: habitId, content: content)
        case UNNotificationDefaultActionIdentifier:
            if content.categoryIdentifier == NotificationPlanner.numericalCategory, let date {
                await MainActor.run { NotificationRouter.shared.pending = .init(habitId: habitId, date: date) }
            }
        default:
            break
        }
    }

    private func done(habitId: Int64, date: String?, requestId: String) async {
        if let date {
            // Unknown habit ids are a facade no-op; mutate still reschedules via the hook.
            do {
                try await LoopStore.shared.mutate { try $0.markDone(habitId: habitId, date: date) }
            } catch {
                await NotificationPlanner.reschedule()  // the mutate hook did not run
            }
        } else {
            await NotificationPlanner.reschedule()
        }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [NotificationPlanner.snoozeIdentifier(habitId: habitId)])
        center.removeDeliveredNotifications(withIdentifiers: [requestId, NotificationPlanner.snoozeIdentifier(habitId: habitId)])
        if NotificationPlanner.shouldClose(isForeground: await NotificationPlanner.isForeground(), closeIfInactive: true) {
            await LoopStore.shared.close()
        }
    }

    private func snooze(habitId: Int64, content: UNNotificationContent) async {
        let exists = (try? await LoopStore.shared.withKit { try $0.habitInput(habitId: habitId) != nil }) ?? false
        if exists {
            try? await UNUserNotificationCenter.current().add(NotificationPlanner.snoozeRequest(from: content, habitId: habitId))
        }
        await NotificationPlanner.reschedule()
    }
}
