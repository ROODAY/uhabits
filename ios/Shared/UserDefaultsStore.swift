import Foundation
import LoopKit

/// Backs the Kotlin preferences with UserDefaults.
final class UserDefaultsStore: NSObject, KeyValueStore {
    private let defaults: UserDefaults
    private let suiteName: String?

    init(defaults: UserDefaults = AppGroup.defaults, suiteName: String? = AppGroup.id) {
        self.defaults = defaults
        self.suiteName = suiteName
    }

    func getString(key: String) -> String? {
        defaults.string(forKey: key)
    }

    func putString(key: String, value: String) {
        defaults.set(value, forKey: key)
    }

    func remove(key: String) {
        defaults.removeObject(forKey: key)
    }

    func clear() {
        if let suiteName {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        } else {
            for key in defaults.dictionaryRepresentation().keys { defaults.removeObject(forKey: key) }
        }
    }
}
