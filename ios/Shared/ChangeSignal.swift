import Foundation

/// Cross-process "data changed" signal over a Darwin notification.
enum ChangeSignal {
    static let name = "org.isoron.loop.dataChanged"

    private static let lock = NSLock()
    private static var handlers: [@Sendable () -> Void] = []
    private static var installed = false

    private static var lastOwnPost: Date?

    /// True when this process posted the signal moments ago. Darwin notifications carry no sender, so the
    /// poster hears its own post; its kit already holds those writes and needs no reload. A short window is
    /// used because deliveries can coalesce. A false negative only costs an extra reload.
    static var isOwnPost: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let t = lastOwnPost else { return false }
        return Date().timeIntervalSince(t) < 1.0
    }

    static func post() {
        lock.lock()
        lastOwnPost = Date()
        lock.unlock()
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString), nil, nil, true)
    }

    /// Handlers are invoked on the main queue.
    static func observe(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        handlers.append(handler)
        let needInstall = !installed
        installed = true
        lock.unlock()
        guard needInstall else { return }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), nil,
            { _, _, _, _, _ in ChangeSignal.fire() },
            name as CFString, nil, .deliverImmediately)
    }

    private static func fire() {
        lock.lock()
        let copy = handlers
        lock.unlock()
        DispatchQueue.main.async {
            for h in copy { h() }
        }
    }
}
