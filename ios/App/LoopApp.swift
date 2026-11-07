import SwiftUI

@main
struct LoopApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = HabitListModel()
    private let seedDemo = ProcessInfo.processInfo.arguments.contains(DemoSeed.flag)

    var body: some Scene {
        WindowGroup {
            HabitListView(model: model)
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
