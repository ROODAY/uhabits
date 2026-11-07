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
                Task {
                    await model.activate(seedDemo: seedDemo)
                    await NotificationPlanner.requestAuthorizationIfRemindersExist()
                    await NotificationPlanner.reschedule()
                }
            case .background:
                BackgroundRefresh.schedule()
                Task { await model.deactivate() }
            default: break
            }
        }
    }
}
