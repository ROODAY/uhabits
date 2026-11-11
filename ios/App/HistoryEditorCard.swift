import SwiftUI
import LoopKit

/// Pure layout of day cells into a weekday x week grid. Layout only; no habit logic.
enum HistoryGrid {
    /// Returns 7 rows (weekdays starting at `firstWeekday`, 1 = Sunday) x N columns (weeks, oldest left,
    /// newest right). `days` may be in any order. `today` is an ISO date; days after it are nil.
    static func layout(days: [DayCell], firstWeekday: Int, today: String,
                       calendar: Calendar = .current) -> [[DayCell?]] {
        func date(_ iso: String) -> Date? { calendar.date(from: DateKey.date(fromIso: iso)) }
        func row(_ d: Date) -> Int { (calendar.component(.weekday, from: d) - firstWeekday + 7) % 7 }
        guard let todayDate = date(today) else { return [] }
        let todayWeekStart = calendar.date(byAdding: .day, value: -row(todayDate), to: todayDate) ?? todayDate
        var placed: [(row: Int, col: Int, cell: DayCell)] = []
        for cell in days {
            guard let d = date(cell.date), d <= todayDate else { continue }
            let r = row(d)
            let start = calendar.date(byAdding: .day, value: -r, to: d) ?? d
            let weeks = (calendar.dateComponents([.day], from: start, to: todayWeekStart).day ?? 0) / 7
            placed.append((r, weeks, cell))
        }
        guard let maxBack = placed.map({ $0.col }).max() else { return [] }
        let cols = maxBack + 1
        var grid = [[DayCell?]](repeating: [DayCell?](repeating: nil, count: cols), count: 7)
        for p in placed { grid[p.row][cols - 1 - p.col] = p.cell }
        return grid
    }
}

struct HistoryEditorCard: View {
    let days: [DayCell]
    let today: String
    /// Resolved first weekday (1 = Sunday ... 7 = Saturday) from the facade.
    let firstWeekday: Int
    let isNumerical: Bool
    let unit: String
    let color: Color
    var onTap: (DayCell) -> Void
    var onLongPress: (DayCell) -> Void

    var body: some View {
        let cal = Calendar.current
        let grid = HistoryGrid.layout(days: days, firstWeekday: firstWeekday, today: today, calendar: cal)
        VStack(alignment: .leading, spacing: 8) {
            Text("History").font(.headline)
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(0..<grid.count, id: \.self) { r in
                    GridRow {
                        Text(cal.shortWeekdaySymbols[(firstWeekday - 1 + r) % 7])
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)
                        ForEach(0..<grid[r].count, id: \.self) { c in
                            if let cell = grid[r][c] {
                                cellView(cell)
                            } else {
                                Color.clear.aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func dayNumber(_ iso: String) -> String {
        DateKey.date(fromIso: iso).day.map(String.init) ?? ""
    }

    @ViewBuilder private func cellView(_ cell: DayCell) -> some View {
        let completed = cell.isCompleted
        let skipped = !isNumerical && cell.rawValue == 3
        let auto = !isNumerical && cell.rawValue == 1
        // Skipped cells are outlined, not filled, so their text must stay readable on the card background.
        let filled = completed && !skipped
        ZStack {
            if skipped {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(completed ? (auto ? color.opacity(0.5) : color) : Color.gray.opacity(0.2))
            }
            VStack(spacing: 0) {
                if isNumerical && cell.value > 0 {
                    Text(CheckmarkCell.format(cell.value)).font(.system(size: 9, weight: .bold))
                        .minimumScaleFactor(0.5).lineLimit(1)
                }
                Text(dayNumber(cell.date)).font(.system(size: 9))
            }
            .foregroundStyle(filled ? Color.white : (skipped ? Color.primary : Color.secondary))
            if !cell.notes.isEmpty {
                Circle().fill(filled ? Color.white : color).frame(width: 5, height: 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture { onTap(cell) }
        .onLongPressGesture(minimumDuration: 0.5) { onLongPress(cell) }
        .accessibilityLabel(cell.date)
    }
}
