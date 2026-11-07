import SwiftUI
import UserNotifications

/// Sets up notification handling before launch finishes, so background action launches are handled (R-T14f/g).
final class LoopAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories(NotificationPlanner.categories())
        center.delegate = NotificationHandler.shared
        BackgroundRefresh.register()
        BackgroundRefresh.schedule()
        Task { await NotificationPlanner.installHook() }
        return true
    }
}

/// Runs `work` inside a UIKit background task so it can finish after the app leaves the foreground.
@MainActor
enum BackgroundGrace {
    private final class Token { var id = UIBackgroundTaskIdentifier.invalid }

    static func run(_ work: @escaping @MainActor () async -> Void) {
        let app = UIApplication.shared
        let token = Token()
        token.id = app.beginBackgroundTask(withName: "close-store") {
            if token.id != .invalid { app.endBackgroundTask(token.id); token.id = .invalid }
        }
        Task { @MainActor in
            await work()
            if token.id != .invalid { app.endBackgroundTask(token.id); token.id = .invalid }
        }
    }
}

@main
struct LoopApp: App {
    @UIApplicationDelegateAdaptor(LoopAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = HabitListModel()
    private let seedDemo = ProcessInfo.processInfo.arguments.contains(DemoSeed.flag)

    private var launchScreen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--screen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    var body: some Scene {
        WindowGroup {
            HabitListView(model: model, launchScreen: launchScreen)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                AppActivity.isForeground = true
                Task {
                    await model.activate(seedDemo: seedDemo)
                    await NotificationPlanner.requestAuthorizationIfRemindersExist()
                    await NotificationPlanner.reschedule()
                }
            case .background:
                AppActivity.isForeground = false
                BackgroundRefresh.schedule()
                // Ask for extra time so the DB close finishes before the process is suspended (0xdead10cc).
                BackgroundGrace.run { await model.deactivate() }
            default: break
            }
        }
    }
}
