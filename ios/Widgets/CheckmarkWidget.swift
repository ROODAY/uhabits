import SwiftUI
import WidgetKit
import AppIntents
import LoopKit

struct SelectHabitIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose habit"
    @Parameter(title: "Habit") var habit: HabitEntity?
}

struct CheckmarkProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CheckmarkEntry {
        CheckmarkEntry(date: Date(), kind: .habit, name: "Habit", score: 0.6, isDone: false)
    }

    func snapshot(for configuration: SelectHabitIntent, in context: Context) async -> CheckmarkEntry {
        await load(configuration).0
    }

    func timeline(for configuration: SelectHabitIntent, in context: Context) async -> Timeline<CheckmarkEntry> {
        let (entry, delay) = await load(configuration)
        return Timeline(entries: [entry],
                        policy: .after(CheckmarkEntry.nextRefresh(after: entry.date, delayHours: delay)))
    }

    /// Opens the store, reads, and always closes it again (DB lock rule).
    private func load(_ configuration: SelectHabitIntent) async -> (CheckmarkEntry, Int) {
        let now = Date()
        guard let habit = configuration.habit else { return (.choose(date: now), 0) }
        do {
            let r = try await LoopStore.shared.withKit { kit -> (HabitRow?, [Int], [Int], Int) in
                let row = try kit.listHabits(dayCount: 1, includeArchived: false).first { $0.id == habit.habitId }
                return (row,
                        try kit.palette(dark: false).map { Int(truncating: $0) },
                        try kit.palette(dark: true).map { Int(truncating: $0) },
                        Int(try kit.midnightDelayHours()))
            }
            await LoopStore.shared.close()
            return (CheckmarkEntry.make(row: r.0, palette: r.1, darkPalette: r.2, date: now), r.3)
        } catch {
            await LoopStore.shared.close()
            return (.needsSetup(date: now), 0)
        }
    }
}

struct CheckmarkWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CheckmarkWidget", intent: SelectHabitIntent.self, provider: CheckmarkProvider()) { entry in
            CheckmarkWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Habit check-off")
        .description("Check off a habit for today.")
        .supportedFamilies([.systemSmall])
    }
}
