import XCTest
import LoopKit
@testable import LoopApp

final class HistoryGridTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// 56 days ending 2026-11-06 (a Friday), newest first.
    private func days() -> [DayCell] {
        let end = cal.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 12))!
        return (0..<56).map { i in
            let d = cal.date(byAdding: .day, value: -i, to: end)!
            return DayCell(date: DateKey.iso(d, calendar: cal), rawValue: 0, value: 0, isCompleted: false, notes: "")
        }
    }

    private func find(_ grid: [[DayCell?]], _ iso: String) -> (Int, Int)? {
        for r in 0..<grid.count { for c in 0..<grid[r].count where grid[r][c]?.date == iso { return (r, c) } }
        return nil
    }

    func testSundayFirst() {
        let g = HistoryGrid.layout(days: days(), firstWeekday: 1, today: "2026-11-06", calendar: cal)
        XCTAssertEqual(g.count, 7)
        XCTAssertEqual(g[0].count, 9)
        let t = find(g, "2026-11-06")!
        XCTAssertEqual(t.0, 5)
        XCTAssertEqual(t.1, 8)
        let sun = find(g, "2026-11-01")!
        XCTAssertEqual(sun.0, 0)
        XCTAssertEqual(sun.1, 8)
        let sat = find(g, "2026-10-31")!
        XCTAssertEqual(sat.0, 6)
        XCTAssertEqual(sat.1, 7)
        XCTAssertNil(g[6][8])  // 2026-11-07 is in the future
    }

    func testMondayFirst() {
        let g = HistoryGrid.layout(days: days(), firstWeekday: 2, today: "2026-11-06", calendar: cal)
        XCTAssertEqual(g[0].count, 9)
        let t = find(g, "2026-11-06")!
        XCTAssertEqual(t.0, 4)
        XCTAssertEqual(t.1, 8)
        let mon = find(g, "2026-11-02")!
        XCTAssertEqual(mon.0, 0)
        XCTAssertEqual(mon.1, 8)
        let sun = find(g, "2026-11-01")!
        XCTAssertEqual(sun.0, 6)
        XCTAssertEqual(sun.1, 7)
        XCTAssertNil(g[5][8])
        XCTAssertNil(g[6][8])
    }

    func testFutureDaysAreNil() {
        let g = HistoryGrid.layout(days: days(), firstWeekday: 1, today: "2026-11-06", calendar: cal)
        XCTAssertNil(find(g, "2026-11-07"))
    }
}
