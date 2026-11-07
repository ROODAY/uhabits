import SwiftUI
import LoopKit

/// Navigation routes. Tasks 12 and 13 replace the placeholder destinations.
enum Route: Hashable {
    case edit(Int64?)
    case detail(Int64)
}

enum ListSheet: Identifiable {
    case number(row: HabitRow, cell: DayCell)
    case notes(row: HabitRow, cell: DayCell)
    var id: String {
        switch self {
        case .number(let r, let c): return "n\(r.id)-\(c.date)"
        case .notes(let r, let c): return "t\(r.id)-\(c.date)"
        }
    }
}

@MainActor
final class HabitListModel: ObservableObject {
    @Published var rows: [HabitRow] = []
    @Published var lightPalette: [Int] = []
    @Published var darkPalette: [Int] = []
    @Published var questionMarks = false
    @Published var openError: String?
    @Published var alertMessage: String?
    @Published var loaded = false
    /// Bumped after every successful refresh so open detail screens re-query.
    @Published var refreshTick = 0

    private var midnightTimer: Timer?
    private var started = false
    private let store: LoopStore
    /// Serializes lifecycle work (R-T12a): each activate/deactivate/refresh awaits the previous one.
    private var chain: Task<Void, Never>?
    /// False while the app is in the background; refresh() is then a no-op so the DB stays closed.
    private(set) var isActive = false

    init(store: LoopStore = .shared) {
        self.store = store
    }

    func start() {
        guard !started else { return }
        started = true
        ChangeSignal.observe { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) async {
        let previous = chain
        let task = Task { @MainActor in
            await previous?.value
            await work()
        }
        chain = task
        await task.value
    }

    /// Called when the app becomes active.
    func activate(seedDemo: Bool) async {
        isActive = true  // synchronous: the last lifecycle call wins
        await enqueue { [self] in
            guard isActive else { return }  // superseded by a later deactivate
            start()
            do {
                if seedDemo { try await DemoSeed.seedIfEmpty(store) }
                try await store.reload()
            } catch { report(error) }
            await performRefresh()
        }
    }

    func deactivate() async {
        isActive = false
        await enqueue { [self] in
            midnightTimer?.invalidate()
            midnightTimer = nil
            // Decide from the state at the time this work runs, so the last call wins.
            if !isActive { await store.close() }
        }
    }

    func retry() async {
        await enqueue { [self] in
            do { try await store.reload() } catch { report(error) }
            await performRefresh()
        }
    }

    func refresh() async {
        guard isActive else { return }
        await enqueue { [self] in await performRefresh() }
    }

    private func performRefresh() async {
        guard isActive else { return }
        do {
            let r = try await store.withKit { kit in
                (try kit.listHabits(dayCount: 5, includeArchived: false),
                 try kit.palette(dark: false).map { Int(truncating: $0) },
                 try kit.palette(dark: true).map { Int(truncating: $0) },
                 try kit.areQuestionMarksEnabled(),
                 Int(try kit.midnightDelayHours()))
            }
            rows = r.0
            lightPalette = r.1
            darkPalette = r.2
            questionMarks = r.3
            openError = nil
            loaded = true
            refreshTick += 1
            scheduleMidnight(delayHours: r.4)
        } catch { report(error) }
    }

    func toggle(_ row: HabitRow, _ cell: DayCell) async {
        await mutate { try $0.toggle(habitId: row.id, date: cell.date) }
    }

    func setNumber(_ row: HabitRow, _ cell: DayCell, value: Double, notes: String) async {
        await mutate { try $0.setNumber(habitId: row.id, date: cell.date, value: value, notes: notes) }
    }

    func setNotes(_ row: HabitRow, _ cell: DayCell, notes: String) async {
        await mutate { try $0.setNotes(habitId: row.id, date: cell.date, notes: notes) }
    }

    private func mutate(_ body: @escaping (LoopKit) throws -> Void) async {
        do { try await store.mutate(body) } catch { report(error) }
        await refresh()
    }

    private func report(_ error: Error) {
        if let e = error as? LoopStoreError, case .openFailed(let m) = e {
            openError = m
        } else {
            alertMessage = String(describing: error)
        }
    }

    private func scheduleMidnight(delayHours: Int) {
        midnightTimer?.invalidate()
        let cal = Calendar.current
        let now = Date()
        let startToday = cal.startOfDay(for: now)
        let nextMidnight = cal.date(byAdding: .day, value: 1, to: startToday) ?? now.addingTimeInterval(86400)
        let candidates = [startToday, nextMidnight].compactMap { cal.date(byAdding: .hour, value: delayHours, to: $0) }
        guard let fire = candidates.filter({ $0 > now }).min() else { return }
        midnightTimer = Timer.scheduledTimer(withTimeInterval: fire.timeIntervalSinceNow + 1, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }
}

struct HabitListView: View {
    @ObservedObject var model: HabitListModel
    @Environment(\.colorScheme) private var scheme
    @State private var sheet: ListSheet?
    @State private var path: [Route] = []
    @State private var launchHandled = false
    /// Value of the --screen launch argument (CI screenshots).
    var launchScreen: String?

    private var palette: [Int] { scheme == .dark ? model.darkPalette : model.lightPalette }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let err = model.openError {
                    VStack(spacing: 12) {
                        Text("Couldn't open your habits database").font(.headline)
                        Text(err).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Retry") { Task { await model.retry() } }.buttonStyle(.borderedProminent)
                    }.padding()
                } else {
                    list
                }
            }
            .navigationTitle("Habits")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { path.append(.edit(nil)) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add habit")
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .edit(let id):
                    HabitEditView(habitId: id, onDone: { Task { await model.refresh() } })
                case .detail(let id):
                    HabitDetailView(habitId: id, listModel: model, onEdit: { path.append(.edit($0)) })
                }
            }
        }
        .onChange(of: model.loaded, initial: true) { _, isLoaded in
            guard isLoaded, !launchHandled, launchScreen == "edit" || launchScreen == "detail", let first = model.rows.first else { return }
            launchHandled = true
            path.append(launchScreen == "detail" ? .detail(first.id) : .edit(first.id))
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .number(let row, let cell):
                NumberEntrySheet(title: row.name, unit: row.unit, value: cell.value, notes: cell.notes) { v, n in
                    Task { await model.setNumber(row, cell, value: v, notes: n) }
                }
            case .notes(let row, let cell):
                NotesSheet(title: "\(row.name) — \(cell.date)", notes: cell.notes) { n in
                    Task { await model.setNotes(row, cell, notes: n) }
                }
            }
        }
        .alert("Error", isPresented: Binding(get: { model.alertMessage != nil },
                                             set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.alertMessage ?? "") }
    }

    private var list: some View {
        List {
            if let first = model.rows.first {
                header(first.days)
                    .listRowSeparator(.hidden)
            }
            ForEach(model.rows, id: \.id) { row in
                HabitRowView(
                    row: row,
                    color: Palette.color(index: Int(row.colorIndex), in: palette),
                    questionMarks: model.questionMarks,
                    onOpen: { path.append(.detail(row.id)) },
                    onCellTap: { cell in
                        if row.isNumerical {
                            sheet = .number(row: row, cell: cell)
                        } else {
                            Task { await model.toggle(row, cell) }
                        }
                    },
                    onCellLongPress: { cell in sheet = .notes(row: row, cell: cell) })
            }
        }
        .listStyle(.plain)
        .overlay {
            if model.loaded && model.rows.isEmpty {
                Text("No habits yet. Tap + to add one.").foregroundStyle(.secondary)
            }
        }
    }

    private func header(_ days: [DayCell]) -> some View {
        HStack(spacing: 6) {
            Spacer()
            ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                let parts = Self.label(d.date)
                VStack(spacing: 0) {
                    Text(parts.0).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(parts.1).font(.system(size: 13, weight: .semibold))
                }
                .frame(width: 42)
            }
        }
    }

    /// Weekday initial and day number for display only.
    static func label(_ iso: String) -> (String, String) {
        let c = DateKey.date(fromIso: iso)
        let cal = Calendar.current
        guard let date = cal.date(from: c), let day = c.day else { return ("", "") }
        let idx = cal.component(.weekday, from: date) - 1
        return (cal.veryShortStandaloneWeekdaySymbols[idx], String(day))
    }
}
