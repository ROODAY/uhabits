import XCTest
import SwiftUI
import LoopKit
@testable import LoopApp

@MainActor
final class CheckmarkWidgetTests: XCTestCase {
    private func row(numerical: Bool, done: Bool, value: Double) -> HabitRow {
        HabitRow(id: 7, name: numerical ? "Water" : "Meditate", question: "q", colorIndex: 2,
                 isNumerical: numerical, unit: numerical ? "glasses" : "", targetValue: numerical ? 8 : 0,
                 targetType: 0, isArchived: false, score: 0.62, isCompletedToday: done, today: "2026-11-06",
                 days: [DayCell(date: "2026-11-06", rawValue: Int32(value * 1000), value: value, isCompleted: done, notes: "")], category: "")
    }

    func testWidgetEntryForDeletedHabit() {
        let e = CheckmarkEntry.make(row: nil)
        XCTAssertEqual(e.kind, .removed)
    }

    func testEntryForYesNo() {
        let e = CheckmarkEntry.make(row: row(numerical: false, done: true, value: 1), palette: [1, 2, 0xFF0000], darkPalette: [1, 2, 0x00FF00])
        XCTAssertEqual(e.kind, .habit)
        XCTAssertEqual(e.name, "Meditate")
        XCTAssertTrue(e.isDone)
        XCTAssertFalse(e.isNumerical)
        XCTAssertEqual(e.score, 0.62, accuracy: 1e-9)
        XCTAssertEqual(e.colorHex, 0xFF0000)
        XCTAssertEqual(e.darkColorHex, 0x00FF00)
    }

    func testEntryForNumerical() {
        let e = CheckmarkEntry.make(row: row(numerical: true, done: false, value: 2.5))
        XCTAssertTrue(e.isNumerical)
        XCTAssertEqual(e.value, 2.5, accuracy: 1e-9)
        XCTAssertEqual(e.target, 8, accuracy: 1e-9)
        XCTAssertEqual(e.unit, "glasses")
        XCTAssertEqual(CheckmarkEntry.format(2.5), "2.5")
        XCTAssertEqual(CheckmarkEntry.format(8), "8")
    }

    func testNextRefreshIncludesMidnightDelay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let at = { (h: Int) in cal.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: h))! }
        // 10:00 with 3h delay: next rollover is tomorrow 03:00.
        XCTAssertEqual(CheckmarkEntry.nextRefresh(after: at(10), delayHours: 3, calendar: cal),
                       cal.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 3)))
        // 01:00 with 3h delay: rollover still ahead today at 03:00.
        XCTAssertEqual(CheckmarkEntry.nextRefresh(after: at(1), delayHours: 3, calendar: cal), at(3))
        XCTAssertEqual(CheckmarkEntry.nextRefresh(after: at(10), delayHours: 0, calendar: cal),
                       cal.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 0)))
    }

    func testRenderSnapshots() throws {
        let entries: [(String, CheckmarkEntry)] = [
            ("widget", CheckmarkEntry.make(row: row(numerical: false, done: true, value: 1), palette: [0, 0, 0x4CAF50], darkPalette: [0, 0, 0x4CAF50])),
            ("widget-undone", CheckmarkEntry.make(row: row(numerical: false, done: false, value: 0), palette: [0, 0, 0x4CAF50], darkPalette: [0, 0, 0x4CAF50])),
            ("widget-measurable", CheckmarkEntry.make(row: row(numerical: true, done: false, value: 2.5), palette: [0, 0, 0x2196F3], darkPalette: [0, 0, 0x2196F3])),
            ("widget-removed", CheckmarkEntry.make(row: nil)),
        ]
        let dir = ProcessInfo.processInfo.environment["WIDGET_SNAPSHOT_DIR"]
        for (name, entry) in entries {
            let view = CheckmarkWidgetView(entry: entry)
                .padding(16)
                .frame(width: 170, height: 170)
                .background(Color(white: 0.94))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage, name)
            let png = try XCTUnwrap(image.pngData(), name)
            XCTAssertGreaterThan(png.count, 1000)
            let att = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            att.name = name
            att.lifetime = .keepAlways
            add(att)
            if let dir {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
            }
        }
    }
}
