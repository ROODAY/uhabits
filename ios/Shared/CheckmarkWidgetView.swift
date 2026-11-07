import SwiftUI
import AppIntents

/// Small-widget content. The widget supplies the container background.
struct CheckmarkWidgetView: View {
    let entry: CheckmarkEntry
    @Environment(\.colorScheme) private var scheme

    private var color: Color {
        Palette.color(hex: scheme == .dark ? entry.darkColorHex : entry.colorHex)
    }
    private var entity: HabitEntity { HabitEntity(id: Int(entry.habitId), name: entry.name) }

    var body: some View {
        switch entry.kind {
        case .habit: habit
        case .removed: message("Habit removed \u{2014} edit widget", "trash.slash")
        case .choose: message("Choose a habit \u{2014} edit widget", "hand.tap")
        case .needsSetup: message("Open Loop to finish setup", "gearshape")
        }
    }

    private func message(_ text: String, _ symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.secondary)
            Text(text).font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var habit: some View {
        VStack(spacing: 6) {
            Text(entry.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if entry.isNumerical { numerical } else { yesNo }
        }
    }

    private var yesNo: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: 8)
            Circle().trim(from: 0, to: max(0, min(1, entry.score)))
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Button(intent: ToggleHabitIntent(habit: entity)) {
                Image(systemName: entry.isDone ? "checkmark.circle.fill" : "circle")
                    .resizable().scaledToFit().frame(width: 52, height: 52)
                    .foregroundStyle(entry.isDone ? color : Color.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var numerical: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            Text(CheckmarkEntry.format(entry.value)).font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(entry.isDone ? color : Color.primary)
                .minimumScaleFactor(0.5).lineLimit(1)
            Text("/ \(CheckmarkEntry.format(entry.target)) \(entry.unit)")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 16) {
                Button(intent: DecrementHabitIntent(habit: entity)) {
                    Image(systemName: "minus.circle.fill").resizable().frame(width: 38, height: 38)
                }
                Button(intent: IncrementHabitIntent(habit: entity)) {
                    Image(systemName: "plus.circle.fill").resizable().frame(width: 38, height: 38)
                }
            }
            .buttonStyle(.plain).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
