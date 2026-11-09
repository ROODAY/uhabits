import XCTest
import LoopKit
@testable import LoopApp

final class ListGlueTests: XCTestCase {
    private func days() -> [DayCell] {
        ["2026-11-09", "2026-11-08", "2026-11-07"].map {
            DayCell(date: $0, rawValue: 0, value: 0, isCompleted: false, notes: "")
        }
    }

    func testDisplayDaysDefaultKeepsNewestFirst() {
        let out = HabitRowView.displayDays(days(), reversed: false)
        XCTAssertEqual(out.map { $0.date }, ["2026-11-09", "2026-11-08", "2026-11-07"])
    }

    func testDisplayDaysReversedPutsNewestLast() {
        let out = HabitRowView.displayDays(days(), reversed: true)
        XCTAssertEqual(out.map { $0.date }, ["2026-11-07", "2026-11-08", "2026-11-09"])
    }

    func testCellTapActionShortToggle() {
        XCTAssertEqual(HabitRowView.cellTapAction(shortToggle: true, isLongPress: false), .toggle)
        XCTAssertEqual(HabitRowView.cellTapAction(shortToggle: true, isLongPress: true), .openSheet)
    }

    func testCellTapActionLongToggle() {
        XCTAssertEqual(HabitRowView.cellTapAction(shortToggle: false, isLongPress: false), .openSheet)
        XCTAssertEqual(HabitRowView.cellTapAction(shortToggle: false, isLongPress: true), .toggle)
    }
}
