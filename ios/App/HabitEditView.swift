import SwiftUI
import LoopKit

struct HabitEditView: View {
    let habitId: Int64?
    var onDone: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var name = ""
    @State private var question = ""
    @State private var notes = ""
    @State private var isNumerical = false
    @State private var unit = ""
    @State private var targetText = ""
    @State private var targetType: Int32 = 0
    @State private var colorIndex = 11
    @State private var freq: FrequencyPreset = .everyDay
    @State private var customFreq: FrequencyPreset?
    @State private var reminderOn = false
    @State private var reminderTime = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    @State private var reminderDays = [Bool](repeating: true, count: 7)
    @State private var lightPalette: [Int] = []
    @State private var darkPalette: [Int] = []
    @State private var error: String?
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var saving = false
    @State private var notificationsDenied = false

    private var palette: [Int] { scheme == .dark ? darkPalette : lightPalette }

    var body: some View {
        Form {
            Section("Habit") {
                TextField("Name", text: $name)
                TextField("Question (e.g. Did you meditate today?)", text: $question)
                TextField("Notes", text: $notes, axis: .vertical)
            }
            Section("Type") {
                Picker("Type", selection: $isNumerical) {
                    Text("Yes or No").tag(false)
                    Text("Measurable").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(habitId != nil)
                if habitId != nil {
                    Text("The type cannot be changed after creation.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if isNumerical {
                Section("Target") {
                    TextField("Unit (e.g. glasses)", text: $unit)
                    TextField("Target", text: $targetText).keyboardType(.decimalPad)
                    Picker("Target type", selection: $targetType) {
                        Text("At least").tag(Int32(0))
                        Text("At most").tag(Int32(1))
                    }
                }
            }
            Section("Color") {
                HabitColorPicker(selected: $colorIndex, palette: palette)
            }
            Section("Schedule") {
                FrequencyPicker(preset: $freq, customOption: customFreq)
            }
            Section("Reminder") {
                ReminderPicker(enabled: $reminderOn, time: $reminderTime, days: $reminderDays)
                if reminderOn && notificationsDenied {
                    Text("Notifications are off for Loop in iOS Settings").font(.caption).foregroundStyle(.secondary)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: url).font(.caption)
                    }
                }
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
            if habitId != nil {
                Section {
                    Button("Delete habit", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(habitId == nil ? "New habit" : "Edit habit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }.disabled(saving || !loaded)
            }
        }
        .confirmationDialog("Delete this habit?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This also deletes all its history.") }
        .task {
            await load()
            notificationsDenied = await NotificationPlanner.notificationsDenied()
        }
    }

    private func load() async {
        guard !loaded else { return }
        let id = habitId
        do {
            let r = try await LoopStore.shared.withKit { kit -> ([Int], [Int], HabitInput?) in
                let light = try kit.palette(dark: false).map { Int(truncating: $0) }
                let dark = try kit.palette(dark: true).map { Int(truncating: $0) }
                var input: HabitInput?
                if let id { input = try kit.habitInput(habitId: id) }
                return (light, dark, input)
            }
            lightPalette = r.0
            darkPalette = r.1
            if let h = r.2 { apply(h) }
            loaded = true
        } catch { self.error = Self.message(error) }
    }

    private func apply(_ h: HabitInput) {
        name = h.name
        question = h.question
        notes = h.description_
        colorIndex = Int(h.colorIndex)
        isNumerical = h.isNumerical
        unit = h.unit
        targetText = h.isNumerical ? Self.formatTarget(h.targetValue) : ""
        targetType = h.targetType
        freq = .from(numerator: Int(h.freqNumerator), denominator: Int(h.freqDenominator))
        if case .custom = freq { customFreq = freq }
        if let r = h.reminder {
            reminderOn = true
            reminderTime = Calendar.current.date(from: DateComponents(hour: Int(r.hour), minute: Int(r.minute))) ?? reminderTime
            let d = r.days.map { $0.boolValue }
            reminderDays = d.count == 7 ? d : [Bool](repeating: true, count: 7)
        }
    }

    private static func formatTarget(_ v: Double) -> String {
        v.isFinite && abs(v) < 1e15 && v == v.rounded() ? String(Int(v)) : String(v)
    }

    private func buildInput() -> HabitInput? {
        var target = 0.0
        if isNumerical {
            let text = targetText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            guard let t = Double(text) else {
                error = "Enter a target value."
                return nil
            }
            target = t
        }
        var reminder: ReminderDto?
        if reminderOn {
            let c = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
            reminder = ReminderDto(hour: Int32(c.hour ?? 9), minute: Int32(c.minute ?? 0),
                                   days: reminderDays.map { KotlinBoolean(value: $0) })
        }
        let (n, d) = freq.numDen
        return HabitInput(name: name, question: question, description: notes,
                          colorIndex: Int32(colorIndex), isNumerical: isNumerical,
                          unit: unit, targetValue: target, targetType: targetType,
                          freqNumerator: Int32(n), freqDenominator: Int32(d), reminder: reminder)
    }

    private func save() async {
        error = nil
        guard let input = buildInput() else { return }
        let id = habitId
        saving = true
        defer { saving = false }
        do {
            // Ask before saving: the post-save reschedule drops requests if not authorized.
            if input.reminder != nil {
                await NotificationPlanner.requestAuthorization()
                notificationsDenied = await NotificationPlanner.notificationsDenied()
            }
            try await LoopStore.shared.mutate { kit in
                if let id { try kit.editHabit(habitId: id, input: input) }
                else { _ = try kit.createHabit(input: input) }
            }
            onDone()
            dismiss()
        } catch { self.error = Self.message(error) }
    }

    private func delete() async {
        guard let id = habitId else { return }
        do {
            try await LoopStore.shared.mutate { try $0.deleteHabit(habitId: id) }
            onDone()
            dismiss()
        } catch { self.error = Self.message(error) }
    }

    /// Kotlin exceptions arrive as NSError whose description is the Kotlin message.
    static func message(_ error: Error) -> String {
        (error as NSError).localizedDescription
    }
}
