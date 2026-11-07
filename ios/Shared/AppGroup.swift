import Foundation

enum AppGroup {
    static var id: String {
        (Bundle.main.object(forInfoDictionaryKey: "LoopAppGroup") as? String) ?? "group.com.example.loop"
    }

    /// App Group container. Only simulator builds (unsigned, no group entitlement) fall back to Application
    /// Support. On a device a missing container returns a path that cannot be opened, so the app shows its
    /// open-failed screen instead of silently creating a second, empty database the widget would not see.
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
            return url
        }
        #if !targetEnvironment(simulator)
        return URL(fileURLWithPath: "/nonexistent/app-group-unavailable/\(id)", isDirectory: true)
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
        #endif
    }

    static var dbPath: String {
        containerURL.appendingPathComponent("Loop.db").path
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }
}
