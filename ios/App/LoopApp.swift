import SwiftUI

@main
struct LoopApp: App {
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
            case .active: Task { await model.activate(seedDemo: seedDemo) }
            case .background: Task { await model.deactivate() }
            default: break
            }
        }
    }
}
