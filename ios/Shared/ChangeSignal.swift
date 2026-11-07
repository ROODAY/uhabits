import Foundation

/// Cross-process "data changed" signal over a Darwin notification.
enum ChangeSignal {
    static let name = "org.isoron.loop.dataChanged"

    private static let lock = NSLock()
    private static var handlers: [@Sendable () -> Void] = []
    private static var installed = false

    static func post() {
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
