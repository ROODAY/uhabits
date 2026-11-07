import SwiftUI

/// Reminder toggle, time picker and weekday toggles. `days` is indexed by daysSinceSunday (0 = Sunday);
/// the buttons are displayed starting from the locale's first weekday.
struct ReminderPicker: View {
    @Binding var enabled: Bool
    @Binding var time: Date
    @Binding var days: [Bool]

    /// daysSinceSunday indices in display order.
    static func displayOrder(firstWeekday: Int = Calendar.current.firstWeekday) -> [Int] {
        (0..<7).map { ($0 + firstWeekday - 1) % 7 }
    }

    var body: some View {
        Toggle("Reminder", isOn: $enabled)
        if enabled {
            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
            HStack(spacing: 6) {
                ForEach(Self.displayOrder(), id: \.self) { idx in
                    let on = days[idx]
                    Button { days[idx].toggle() } label: {
                        Text(Calendar.current.veryShortStandaloneWeekdaySymbols[idx])
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(on ? Color.accentColor : Color.secondary.opacity(0.2), in: Circle())
                            .foregroundStyle(on ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Calendar.current.standaloneWeekdaySymbols[idx])
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}
