import SwiftUI
import LoopKit

struct ScoreRing: View {
    let score: Double
    let color: Color
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: 4)
            Circle().trim(from: 0, to: CGFloat(min(max(score, 0), 1)))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 26, height: 26)
    }
}

struct HabitRowView: View {
    let row: HabitRow
    let color: Color
    let questionMarks: Bool
    var reversed = false
    var onOpen: () -> Void
    var onCellTap: (DayCell) -> Void
    var onCellLongPress: (DayCell) -> Void

    enum CellAction { case toggle, openSheet }

    /// Facade days are newest first, which Android shows left to right. `reversed` (the reverse-checkmarks
    /// setting) puts the newest on the right.
    static func displayDays(_ days: [DayCell], reversed: Bool) -> [DayCell] {
        reversed ? Array(days.reversed()) : days
    }

    /// With short toggle a tap toggles and a long press opens the sheet; otherwise the reverse.
    static func cellTapAction(shortToggle: Bool, isLongPress: Bool) -> CellAction {
        (shortToggle != isLongPress) ? .toggle : .openSheet
    }

    var body: some View {
        HStack(spacing: 6) {
            ScoreRing(score: row.score, color: color)
            Text(row.name)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
            ForEach(Array(Self.displayDays(row.days, reversed: reversed).enumerated()), id: \.offset) { _, cell in
                CheckmarkCell(cell: cell, isNumerical: row.isNumerical, unit: row.unit, color: color,
                              questionMarks: questionMarks,
                              onTap: { onCellTap(cell) }, onLongPress: { onCellLongPress(cell) })
                    .frame(width: 42)
            }
        }
        .padding(.vertical, 4)
    }
}
