import XCTest
import LoopKit
@testable import LoopApp

final class DemoSeedTests: XCTestCase {
    func testDemoSeedCreatesFourHabits() async throws {
        let dir = NSTemporaryDirectory() + "loop-seed-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "test-" + UUID().uuidString)!
        let store = LoopStore(dbPath: dir + "/Loop.db",
                              resourcesPath: Bundle.main.resourcePath!,
                              keyValueStore: UserDefaultsStore(defaults: defaults, suiteName: nil))
        let seeded = try await DemoSeed.seedIfEmpty(store)
        XCTAssertTrue(seeded)
        let rows = try await store.withKit { try $0.listHabits(dayCount: 30, includeArchived: false) }
        XCTAssertEqual(rows.map { $0.name }, ["Meditate", "Exercise", "Read", "Water"])
        XCTAssertTrue(rows[3].isNumerical)
        XCTAssertEqual(rows[3].unit, "glasses")
        XCTAssertEqual(rows[3].targetValue, 8)
        XCTAssertTrue(rows[0].days.contains { $0.rawValue == 2 })
        let again = try await DemoSeed.seedIfEmpty(store)
        XCTAssertFalse(again)
        await store.close()
    }
}
