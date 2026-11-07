import AppIntents

struct LoopShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleHabitIntent(),
            phrases: ["Check off \(\.$habit) in \(.applicationName)"],
            shortTitle: "Check off habit",
            systemImageName: "checkmark.circle")
    }
}
