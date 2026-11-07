import XCTest
@testable import LoopApp

final class DateKeyTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func testIsoFormat() {
        let d = cal.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 12))!
        XCTAssertEqual(DateKey.iso(d, calendar: cal), "2026-11-06")
        let comps = DateKey.date(fromIso: "2026-11-06")
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 11)
        XCTAssertEqual(comps.day, 6)
    }

    func testMinuteOfDay() {
        let d = cal.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 7, minute: 30))!
        XCTAssertEqual(DateKey.minuteOfDay(d, calendar: cal), 450)
    }
}
