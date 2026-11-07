import SwiftUI
import LoopKit

/// One day cell. Glyph chosen by the facade's `rawValue`; Swift decides nothing about completion.
struct CheckmarkCell: View {
    let cell: DayCell
    let isNumerical: Bool
    let unit: String
    let color: Color
    let questionMarks: Bool
    var onTap: () -> Void
    var onLongPress: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            content
            if isNumerical && !unit.isEmpty {
                Text(unit).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: 0.5, perform: onLongPress)
        .accessibilityLabel(cell.date)
    }

    @ViewBuilder private var content: some View {
        if isNumerical {
            Text(CheckmarkCell.format(cell.value))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(cell.isCompleted ? color : Color.secondary)
        } else {
            switch cell.rawValue {
            case 2: Text("✓").font(.system(size: 20, weight: .bold)).foregroundStyle(color)
            case 1: Text("✓").font(.system(size: 20, weight: .bold)).foregroundStyle(color.opacity(0.4))
            case 3: Text("⤏").font(.system(size: 20, weight: .bold)).foregroundStyle(color.opacity(0.7))
            case -1:
                if questionMarks {
                    Text("?").font(.system(size: 18, weight: .bold)).foregroundStyle(.secondary)
                } else {
                    cross
                }
            default: cross
            }
        }
    }

    private var cross: some View {
        Text("✗").font(.system(size: 18)).foregroundStyle(.secondary.opacity(0.6))
    }

    static func format(_ v: Double) -> String {
        let f = NumberFormatter()
        f.maximumFractionDigits = 3
        f.minimumFractionDigits = 0
        f.usesGroupingSeparator = false
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }
}
