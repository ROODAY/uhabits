import Foundation

/// Single source of truth for "UI is in use" (R-T14h). Set synchronously by the scenePhase handler;
/// stays false on background launches (notification actions, BGTasks). App target only.
@MainActor
enum AppActivity {
    static var isForeground = false
}
