import XCTest
import UserNotifications
import LoopKit
@testable import LoopApp

final class NotificationPlannerTests: XCTestCase {
    private func occ(_ id: Int64, _ date: String = "2026-11-06", hour: Int32 = 21, minute: Int32 = 30,
                     name: String = "Read", question: String = "", numerical: Bool = false) -> ReminderOccurrence {
        ReminderOccurrence(habitId: id, habitName: name, question: question, isNumerical: numerical,
                           date: date, hour: hour, minute: minute)
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func testIdentifierScheme() {
        let reqs = NotificationPlanner.requests(for: [occ(7, "2026-11-06"), occ(7, "2026-11-07")], calendar: calendar)
        XCTAssertEqual(reqs.map { $0.identifier }, ["habit-7-2026-11-06", "habit-7-2026-11-07"])
        XCTAssertEqual((reqs[0].content.userInfo["habitId"] as? NSNumber)?.int64Value, 7)
        XCTAssertEqual(reqs[0].content.userInfo["date"] as? String, "2026-11-06")
    }

    func testTriggerComponents() throws {
        let reqs = NotificationPlanner.requests(for: [occ(1)], calendar: calendar)
        let trigger = try XCTUnwrap(reqs[0].trigger as? UNCalendarNotificationTrigger)
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.year, 2026)
        XCTAssertEqual(trigger.dateComponents.month, 11)
        XCTAssertEqual(trigger.dateComponents.day, 6)
        XCTAssertEqual(trigger.dateComponents.hour, 21)
        XCTAssertEqual(trigger.dateComponents.minute, 30)
    }

    func testCategoryByType() {
        let reqs = NotificationPlanner.requests(for: [occ(1, numerical: false), occ(2, numerical: true)], calendar: calendar)
        XCTAssertEqual(reqs[0].content.categoryIdentifier, "HABIT_YESNO")
        XCTAssertEqual(reqs[1].content.categoryIdentifier, "HABIT_NUMERICAL")
        let cats = NotificationPlanner.categories()
        let yesNo = cats.first { $0.identifier == "HABIT_YESNO" }
        let num = cats.first { $0.identifier == "HABIT_NUMERICAL" }
        XCTAssertEqual(yesNo?.actions.map { $0.identifier }, ["DONE", "SNOOZE"])
        XCTAssertEqual(num?.actions.map { $0.identifier }, ["SNOOZE"])
        XCTAssertTrue(yesNo!.actions.allSatisfy { !$0.options.contains(.foreground) })
    }

    func testCapRespected() {
        let many = (0..<100).map { occ(Int64($0)) }
        let reqs = NotificationPlanner.requests(for: many, calendar: calendar)
        XCTAssertEqual(reqs.count, NotificationPlanner.maxPending)
        XCTAssertLessThanOrEqual(reqs.count, 60)
    }

    func testBodyUsesQuestion() {
        let reqs = NotificationPlanner.requests(
            for: [occ(1, name: "Read", question: "Did you read today?"), occ(2, name: "Run", question: "")],
            calendar: calendar)
        XCTAssertEqual(reqs[0].content.title, "Read")
        XCTAssertEqual(reqs[0].content.body, "Did you read today?")
        XCTAssertEqual(reqs[1].content.title, "Run")
        XCTAssertEqual(reqs[1].content.body, "")
    }

    func testShouldCloseTruthTable() {
        XCTAssertTrue(NotificationPlanner.shouldClose(isForeground: false, closeIfInactive: true))
        XCTAssertFalse(NotificationPlanner.shouldClose(isForeground: true, closeIfInactive: true))
        XCTAssertFalse(NotificationPlanner.shouldClose(isForeground: false, closeIfInactive: false))
        XCTAssertFalse(NotificationPlanner.shouldClose(isForeground: true, closeIfInactive: false))
    }

    func testCleanupIdentifiers() {
        let ids = NotificationPlanner.cleanupIdentifiers(completedRows: [(id: 3, today: "2026-11-06"), (id: 9, today: "2026-11-06")])
        XCTAssertEqual(ids.pending, ["snooze-3", "snooze-9"])
        XCTAssertEqual(ids.delivered, ["habit-3-2026-11-06", "snooze-3", "habit-9-2026-11-06", "snooze-9"])
        let none = NotificationPlanner.cleanupIdentifiers(completedRows: [])
        XCTAssertTrue(none.pending.isEmpty && none.delivered.isEmpty)
    }
}
