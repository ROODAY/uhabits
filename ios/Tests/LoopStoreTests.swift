import XCTest
import LoopKit
@testable import LoopApp

final class LoopStoreTests: XCTestCase {
    private func tempDir() -> String {
        let dir = NSTemporaryDirectory() + "loop-" + UUID().uuidString
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeStore(_ dir: String, defaults: UserDefaults) -> LoopStore {
        LoopStore(dbPath: dir + "/Loop.db",
                  resourcesPath: Bundle.main.resourcePath!,
                  keyValueStore: UserDefaultsStore(defaults: defaults, suiteName: nil))
    }

    private func input(_ name: String) -> HabitInput {
        HabitInput(name: name, question: "", description: "", colorIndex: 3, isNumerical: false,
                   unit: "", targetValue: 0, targetType: 0, freqNumerator: 1, freqDenominator: 1,
                   reminder: nil, category: "")
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "test-" + UUID().uuidString)!
    }

    func testStoreCreateToggleList() async throws {
        let store = makeStore(tempDir(), defaults: defaults())
        try await store.open()
        let id = try await store.withKit { try $0.createHabit(input: input("Read")) }
        let today = try await store.withKit { try $0.today() }
        try await store.mutate { try $0.toggle(habitId: id, date: today) }
        let rows = try await store.withKit { try $0.listHabits(dayCount: 5, includeArchived: false) }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].name, "Read")
        XCTAssertTrue(rows[0].isCompletedToday)
        await store.close()
    }

    func testReloadSeesOtherInstance() async throws {
        let dir = tempDir()
        let d = defaults()
        let a = makeStore(dir, defaults: d)
        let b = makeStore(dir, defaults: d)
        try await a.open()
        let id = try await a.withKit { try $0.createHabit(input: input("Run")) }
        try await b.open()
        let today = try await a.withKit { try $0.today() }
        try await a.mutate { try $0.toggle(habitId: id, date: today) }
        try await b.reload()
        let rows = try await b.withKit { try $0.listHabits(dayCount: 1, includeArchived: false) }
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].isCompletedToday)
        await a.close()
        await b.close()
    }

    func testUserDefaultsStoreRoundTrip() {
        let store = UserDefaultsStore(defaults: defaults(), suiteName: nil)
        XCTAssertNil(store.getString(key: "k"))
        store.putString(key: "k", value: "v")
        XCTAssertEqual(store.getString(key: "k"), "v")
        store.remove(key: "k")
        XCTAssertNil(store.getString(key: "k"))
        store.putString(key: "a", value: "1")
        store.clear()
        XCTAssertNil(store.getString(key: "a"))
    }

    func testClearOnlyAffectsOwnSuite() {
        let nameA = "test-" + UUID().uuidString, nameB = "test-" + UUID().uuidString
        let a = UserDefaultsStore(defaults: UserDefaults(suiteName: nameA)!, suiteName: nameA)
        let b = UserDefaultsStore(defaults: UserDefaults(suiteName: nameB)!, suiteName: nameB)
        a.putString(key: "k", value: "1")
        b.putString(key: "k", value: "2")
        a.clear()
        XCTAssertNil(a.getString(key: "k"))
        XCTAssertEqual(b.getString(key: "k"), "2")
        b.clear()
    }

    func testOpenFailureThrows() async throws {
        let dir = tempDir()
        let store = LoopStore(dbPath: dir, resourcesPath: Bundle.main.resourcePath!,
                              keyValueStore: UserDefaultsStore(defaults: defaults(), suiteName: nil))
        do {
            try await store.open()
            XCTFail("expected throw")
        } catch let LoopStoreError.openFailed(msg) {
            XCTAssertFalse(msg.isEmpty)
        }
    }
}
