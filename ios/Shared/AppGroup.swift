import Foundation

enum AppGroup {
    static var id: String {
        (Bundle.main.object(forInfoDictionaryKey: "LoopAppGroup") as? String) ?? "group.com.example.loop"
    }

    /// App Group container; falls back to Application Support when the group is unavailable (unsigned simulator builds).
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
            return url
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static var dbPath: String {
        containerURL.appendingPathComponent("Loop.db").path
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }
}
