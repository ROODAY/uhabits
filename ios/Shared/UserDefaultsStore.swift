import Foundation
import LoopKit

/// Backs the Kotlin preferences with UserDefaults.
final class UserDefaultsStore: NSObject, KeyValueStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
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
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
    }
}
