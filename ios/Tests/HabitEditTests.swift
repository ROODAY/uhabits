import XCTest
import LoopKit
@testable import LoopApp

final class HabitEditTests: XCTestCase {
    func testFrequencyPresetMapping() {
        let cases: [(FrequencyPreset, Int, Int)] = [
            (.everyDay, 1, 1), (.everyWeek, 1, 7),
            (.timesPerWeek(3), 3, 7), (.timesPerWeek(2), 2, 7),
            (.timesPerMonth(5), 5, 30), (.timesPerMonth(1), 1, 30),
            (.everyNDays(3), 1, 3), (.everyNDays(14), 1, 14),
        ]
        for (preset, n, d) in cases {
            XCTAssertEqual(preset.numDen.0, n, "\(preset)")
            XCTAssertEqual(preset.numDen.1, d, "\(preset)")
            XCTAssertEqual(FrequencyPreset.from(numerator: n, denominator: d), preset)
        }
        // Existing values that fit no preset are preserved.
        let custom = FrequencyPreset.from(numerator: 3, denominator: 5)
        XCTAssertEqual(custom, .custom(3, 5))
        XCTAssertEqual(custom.numDen.0, 3)
        XCTAssertEqual(custom.numDen.1, 5)
        XCTAssertEqual(custom.label, "Custom: 3 times in 5 days")
        XCTAssertEqual(FrequencyPreset.from(numerator: 2, denominator: 31), .custom(2, 31))
    }

    func testReminderDisplayOrder() {
        XCTAssertEqual(ReminderPicker.displayOrder(firstWeekday: 1), [0, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(ReminderPicker.displayOrder(firstWeekday: 2), [1, 2, 3, 4, 5, 6, 0])
    }

    @MainActor
    func testRefreshWhileInactiveDoesNotReopen() async throws {
        let dir = NSTemporaryDirectory() + "loop-life-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "test-" + UUID().uuidString)!
        let store = LoopStore(dbPath: dir + "/Loop.db",
                              resourcesPath: Bundle.main.resourcePath!,
                              keyValueStore: UserDefaultsStore(defaults: defaults, suiteName: nil))
        let model = HabitListModel(store: store)
        await model.activate(seedDemo: false)
        let openAfterActivate = await store.isOpen
        XCTAssertTrue(openAfterActivate)
        await model.deactivate()
        let openAfterDeactivate = await store.isOpen
        XCTAssertFalse(openAfterDeactivate)
        await model.refresh()
        let openAfterRefresh = await store.isOpen
        XCTAssertFalse(openAfterRefresh)
    }
}
