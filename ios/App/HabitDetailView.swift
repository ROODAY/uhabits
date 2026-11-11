import SwiftUI
import LoopKit

@MainActor
final class HabitDetailModel: ObservableObject {
    @Published var detail: HabitDetail?
    @Published var lightPalette: [Int] = []
    @Published var darkPalette: [Int] = []
    @Published var missing = false
    @Published var errorMessage: String?
    private let store: LoopStore
    let habitId: Int64
    /// Reports whether the app UI is active. The detail screen must never reopen the DB while backgrounded.
    var isActive: @MainActor () -> Bool = { true }

    init(habitId: Int64, store: LoopStore = .shared) {
        self.habitId = habitId
        self.store = store
    }

    func refresh() async {
        guard isActive() else { return }
        do {
            let id = habitId
            let r = try await store.withKit { kit in
                (try kit.habitDetail(habitId: id, historyDays: 56),
                 try kit.palette(dark: false).map { Int(truncating: $0) },
                 try kit.palette(dark: true).map { Int(truncating: $0) })
            }
            lightPalette = r.1
            darkPalette = r.2
            if let d = r.0 { detail = d; missing = false } else { missing = true }
        } catch { errorMessage = String(describing: error) }
    }

    private func mutate(_ body: @escaping (LoopKit) throws -> Void) async {
        do { try await store.mutate(body) } catch { errorMessage = String(describing: error) }
        // The mutate may have (re)opened the DB after the app went to the background: close it again.
        if isActive() { await refresh() } else { await store.close() }
    }

    func toggle(_ cell: DayCell) async {
        let id = habitId
        await mutate { try $0.toggle(habitId: id, date: cell.date) }
    }
    func setNumber(_ cell: DayCell, value: Double, notes: String) async {
        let id = habitId
        await mutate { try $0.setNumber(habitId: id, date: cell.date, value: value, notes: notes) }
    }
    func setEntry(_ cell: DayCell, value: Int32, notes: String) async {
        let id = habitId
        await mutate { try $0.setEntry(habitId: id, date: cell.date, value: value, notes: notes) }
    }
}

struct HabitDetailView: View {
    @StateObject private var model: HabitDetailModel
    /// The list model drives lifecycle (active/background) and bumps `refreshTick` after each refresh,
    /// including ChangeSignal-triggered ones, so this screen never touches the DB while backgrounded.
    @ObservedObject var listModel: HabitListModel
    var onEdit: (Int64) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var sheet: ListSheet?

    init(habitId: Int64, listModel: HabitListModel, onEdit: @escaping (Int64) -> Void) {
        _model = StateObject(wrappedValue: HabitDetailModel(habitId: habitId))
        self.listModel = listModel
        self.onEdit = onEdit
    }

    private var palette: [Int] { scheme == .dark ? model.darkPalette : model.lightPalette }

    var body: some View {
        Group {
            if let d = model.detail {
                content(d)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(model.detail?.row.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { onEdit(model.habitId) }
            }
        }
        .task {
            model.isActive = { [weak listModel] in listModel?.isActive ?? false }
            await model.refresh()
        }
        .onChange(of: listModel.refreshTick) { _, _ in
            Task { await model.refresh() }
        }
        .onChange(of: model.missing) { _, gone in if gone { dismiss() } }
        .sheet(item: $sheet) { s in
            switch s {
            case .number(let row, let cell):
                NumberEntrySheet(title: row.name, unit: row.unit, value: cell.value, notes: cell.notes,
                                 skipEnabled: listModel.settings.skipEnabled,
                                 questionMarksEnabled: listModel.settings.questionMarksEnabled,
                                 onSave: { v, n in Task { await model.setNumber(cell, value: v, notes: n) } },
                                 onSetSpecial: { v, n in Task { await model.setEntry(cell, value: v, notes: n) } })
            case .entry(let row, let cell):
                EntrySheet(title: "\(row.name) — \(cell.date)", current: Int32(cell.rawValue), notes: cell.notes,
                           skipEnabled: listModel.settings.skipEnabled,
                           questionMarksEnabled: listModel.settings.questionMarksEnabled) { v, n in
                    Task { await model.setEntry(cell, value: v, notes: n) }
                }
            case .color, .category:
                // Only the list screen presents these (row context menu); never set on the detail screen.
                EmptyView()
            }
        }
        .alert("Error", isPresented: Binding(get: { model.errorMessage != nil },
                                             set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
    }

    private func content(_ d: HabitDetail) -> some View {
        let row = d.row
        let color = Palette.color(index: Int(row.colorIndex), in: palette)
        let noted = row.days.filter { !$0.notes.isEmpty }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(d)
                StreaksCard(currentStreak: Int(d.currentStreak), bestStreaks: d.bestStreaks, color: color)
                HistoryEditorCard(
                    days: row.days, today: row.today, isNumerical: row.isNumerical, unit: row.unit, color: color,
                    onTap: { cell in
                        if row.isNumerical { sheet = .number(row: row, cell: cell) }
                        else { Task { await model.toggle(cell) } }
                    },
                    onLongPress: { cell in sheet = row.isNumerical ? .number(row: row, cell: cell) : .entry(row: row, cell: cell) })
                if !noted.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes").font(.headline)
                        ForEach(noted, id: \.date) { cell in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(StreaksCard.short(cell.date)).font(.caption).foregroundStyle(.secondary)
                                Text(cell.notes)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
    }

    private func header(_ d: HabitDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(d.row.name).font(.title2.bold())
            if !d.row.question.isEmpty { Text(d.row.question).foregroundStyle(.secondary) }
            Text(FrequencyPreset.from(numerator: Int(d.freqNumerator), denominator: Int(d.freqDenominator)).label)
                .font(.subheadline)
            if let r = d.reminder { Text(Self.reminderText(r)).font(.subheadline) }
            if !d.description_.isEmpty { Text(d.description_).font(.footnote).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func reminderText(_ r: ReminderDto) -> String {
        let cal = Calendar.current
        let time = cal.date(from: DateComponents(hour: Int(r.hour), minute: Int(r.minute)))?
            .formatted(date: .omitted, time: .shortened) ?? "\(r.hour):\(r.minute)"
        let days = r.days.map { $0.boolValue }
        if days.allSatisfy({ $0 }) { return "Reminder at \(time), every day" }
        let names = days.enumerated().filter { $0.element }.map { cal.shortWeekdaySymbols[$0.offset] }
        return "Reminder at \(time), " + names.joined(separator: " ")
    }
}
