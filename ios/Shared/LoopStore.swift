import Foundation
import LoopKit
import WidgetKit

/// The single owner of the Kotlin LoopKit in this process. All facade calls go through it.
actor LoopStore {
    static let shared = LoopStore()

    private let dbPath: String
    private let resourcesPath: String
    private let keyValueStore: KeyValueStore
    private var kit: LoopKit?
    private var afterMutation: @Sendable () async -> Void = {}

    init(dbPath: String = AppGroup.dbPath,
         resourcesPath: String = Bundle.main.resourcePath!,
         keyValueStore: KeyValueStore = UserDefaultsStore()) {
        self.dbPath = dbPath
        self.resourcesPath = resourcesPath
        self.keyValueStore = keyValueStore
    }

    func setAfterMutation(_ hook: @escaping @Sendable () async -> Void) {
        afterMutation = hook
    }

    func open() {
        guard kit == nil else { return }
        do {
            kit = try LoopKitFactoryKt.createLoopKit(dbPath: dbPath, resourcesPath: resourcesPath, store: keyValueStore)
        } catch {
            fatalError("LoopKit open failed: \(error)")
        }
    }

    func close() {
        guard let k = kit else { return }
        kit = nil
        try? k.close()
    }

    /// Re-reads the database, picking up writes from other processes.
    func reload() {
        if let k = kit {
            do { try k.reload() } catch { kit = nil; open() }
        } else {
            open()
        }
    }

    func withKit<T>(_ body: (LoopKit) throws -> T) rethrows -> T {
        if kit == nil { open() }
        return try body(kit!)
    }

    func mutate(_ body: (LoopKit) throws -> Void) rethrows {
        if kit == nil { open() }
        try body(kit!)
        ChangeSignal.post()
        WidgetCenter.shared.reloadAllTimelines()
        let hook = afterMutation
        Task { await hook() }
    }
}
