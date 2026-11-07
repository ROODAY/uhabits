import Foundation
import BackgroundTasks

/// Periodic refresh so pre-scheduled reminders stay fresh even if the app is not opened.
enum BackgroundRefresh {
    static let identifier = "org.isoron.loop.refresh"

    /// Must be called before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(task)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()
        let work = Task {
            await NotificationPlanner.installHook()
            // Opens the store lazily and closes it afterwards when the app is not active (R-T14a).
            await NotificationPlanner.reschedule()
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }
}
