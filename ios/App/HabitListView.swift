import SwiftUI
import LoopKit

/// Navigation routes. Tasks 12 and 13 replace the placeholder destinations.
enum Route: Hashable {
    case edit(Int64?)
    case detail(Int64)
    case settings
}

enum ListSheet: Identifiable {
    case number(row: HabitRow, cell: DayCell)
    case entry(row: HabitRow, cell: DayCell)
    case color(row: HabitRow)
    case category(row: HabitRow, existing: [String])
    var id: String {
        switch self {
        case .color(let r): return "c\(r.id)"
        case .category(let r, _): return "k\(r.id)"
        case .number(let r, let c): return "n\(r.id)-\(c.date)"
        case .entry(let r, let c): return "e\(r.id)-\(c.date)"
        }
    }
}

@MainActor
final class HabitListModel: ObservableObject {
    @Published var rows: [ListRow] = []
    @Published var options = ListOptions(sort: 0, isReversed: false, isSortable: true, hideArchived: true, hideCompleted: false)
    @Published var settings = AppSettings(shortToggle: true, midnightDelay: false, skipEnabled: false,
                                          questionMarksEnabled: false, reverseCheckmarks: false,
                                          firstWeekdayChoice: -1, resolvedFirstWeekday: 1)
    @Published var searchQuery = "" {
        didSet { if searchQuery != oldValue { Task { await refresh() } } }
    }
    @Published var lightPalette: [Int] = []
    @Published var darkPalette: [Int] = []
    var questionMarks: Bool { settings.questionMarksEnabled }

    /// Habit rows only (headers skipped).
    var habitRows: [HabitRow] { rows.compactMap { $0.habit } }
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
            Task { @MainActor in await self?.handleExternalChange() }
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

    /// A change signal arrived. Our own writes are already in the open kit; a write from another process
    /// (widget, intent) needs a reload first. Only while active, so the DB is never reopened in the background.
    private func handleExternalChange() async {
        guard isActive else { return }
        if !ChangeSignal.isOwnPost {
            await enqueue { [self] in
                guard isActive else { return }
                do { try await store.reload() } catch { report(error) }
                await performRefresh()
            }
        } else {
            await refresh()
        }
    }

    func refresh() async {
        guard isActive else { return }
        await enqueue { [self] in await performRefresh() }
    }

    private func performRefresh() async {
        guard isActive else { return }
        do {
            let query = searchQuery
            let r = try await store.withKit { kit in
                (try kit.listRows(dayCount: 5, searchQuery: query),
                 try kit.palette(dark: false).map { Int(truncating: $0) },
                 try kit.palette(dark: true).map { Int(truncating: $0) },
                 try kit.settings(),
                 Int(try kit.midnightDelayHours()),
                 try kit.listOptions())
            }
            rows = r.0
            lightPalette = r.1
            darkPalette = r.2
            settings = r.3
            options = r.5
            openError = nil
            loaded = true
            refreshTick += 1
            scheduleMidnight(delayHours: r.4)
        } catch { report(error) }
    }

    func sortBy(_ sort: Int32) async {
        await mutate { try $0.sortBy(sort: sort) }
    }

    func setHideArchived(_ hide: Bool) async {
        await mutate { try $0.setHideArchived(hide: hide) }
    }

    func setHideCompleted(_ hide: Bool) async {
        await mutate { try $0.setHideCompleted(hide: hide) }
    }

    func toggle(_ row: HabitRow, _ cell: DayCell) async {
        await mutate { try $0.toggle(habitId: row.id, date: cell.date) }
    }

    func setNumber(_ row: HabitRow, _ cell: DayCell, value: Double, notes: String) async {
        await mutate { try $0.setNumber(habitId: row.id, date: cell.date, value: value, notes: notes) }
    }

    func setEntry(_ row: HabitRow, _ cell: DayCell, value: Int32, notes: String) async {
        await mutate { try $0.setEntry(habitId: row.id, date: cell.date, value: value, notes: notes) }
    }

    func mutate(_ body: @escaping (LoopKit) throws -> Void) async {
        do { try await store.mutate(body) } catch { report(error) }
        if isActive { await refresh() } else { await store.close() }
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
    @State private var deleteTarget: HabitRow?
    @State private var renameOld: String?
    @State private var renameText = ""
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
                ToolbarItem(placement: .topBarLeading) {
                    Button { path.append(.settings) } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .primaryAction) { sortMenu }
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
                case .settings:
                    SettingsView(onChanged: { Task { await model.refresh() } },
                                 isActive: { [weak model] in model?.isActive ?? false })
                }
            }
        }
        .onChange(of: model.loaded, initial: true) { _, isLoaded in
            guard isLoaded, !launchHandled else { return }
            if launchScreen == "settings" {
                launchHandled = true
                path.append(.settings)
                return
            }
            if launchScreen == "entry" {
                guard let row = model.habitRows.first(where: { !$0.isNumerical }),
                      let cell = row.days.first(where: { $0.date == row.today }) ?? row.days.first else { return }
                launchHandled = true
                sheet = .entry(row: row, cell: cell)
                return
            }
            if launchScreen == "menu" {
                guard let row = model.habitRows.first else { return }
                launchHandled = true
                Task { sheet = .category(row: row, existing: await model.loadCategories()) }
                return
            }
            guard launchScreen == "edit" || launchScreen == "detail", let first = model.habitRows.first else { return }
            launchHandled = true
            path.append(launchScreen == "detail" ? .detail(first.id) : .edit(first.id))
        }
        .onReceive(NotificationRouter.shared.$pending) { _ in handlePending() }
        .onChange(of: model.loaded) { _, _ in handlePending() }
        .sheet(item: $sheet) { s in
            switch s {
            case .number(let row, let cell):
                NumberEntrySheet(title: row.name, unit: row.unit, value: cell.value, notes: cell.notes,
                                 skipEnabled: model.settings.skipEnabled,
                                 questionMarksEnabled: model.settings.questionMarksEnabled,
                                 onSave: { v, n in Task { await model.setNumber(row, cell, value: v, notes: n) } },
                                 onSetSpecial: { v, n in Task { await model.setEntry(row, cell, value: v, notes: n) } })
            case .color(let row):
                ColorSheet(palette: palette, selected: Int(row.colorIndex)) { i in
                    Task { await model.setColor(row, i) }
                }
            case .category(let row, let existing):
                CategoryPicker(current: row.category, existing: existing) { c in
                    Task { await model.setCategory(row, c) }
                }
            case .entry(let row, let cell):
                EntrySheet(title: "\(row.name) — \(cell.date)", current: Int32(cell.rawValue), notes: cell.notes,
                           skipEnabled: model.settings.skipEnabled,
                           questionMarksEnabled: model.settings.questionMarksEnabled) { v, n in
                    Task { await model.setEntry(row, cell, value: v, notes: n) }
                }
            }
        }
        .confirmationDialog("Delete this habit?", isPresented: Binding(get: { deleteTarget != nil },
                                                                       set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let row = deleteTarget { Task { await model.delete(row) } }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        }
        .alert("Rename category", isPresented: Binding(get: { renameOld != nil },
                                                       set: { if !$0 { renameOld = nil } })) {
            TextField("Category", text: $renameText)
            Button("Cancel", role: .cancel) { renameOld = nil }
            Button("Rename") {
                if let old = renameOld { Task { await model.renameCategory(old, to: renameText) } }
                renameOld = nil
            }
        }
        .alert("Error", isPresented: Binding(get: { model.alertMessage != nil },
                                             set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.alertMessage ?? "") }
    }

    /// Opens the numerical-entry sheet for a tapped numerical-habit notification (R-T14d).
    private func handlePending() {
        let router = NotificationRouter.shared
        guard let p = router.pending, model.loaded else { return }
        router.pending = nil
        guard let row = model.habitRows.first(where: { $0.id == p.habitId }) else { return }  // deleted habit
        if path.last != .detail(row.id) { path.append(.detail(row.id)) }
        if let cell = row.days.first(where: { $0.date == p.date }) {
            sheet = .number(row: row, cell: cell)
            return
        }
        // Outside the loaded window: fetch the real cell so saving cannot overwrite value/notes.
        Task {
            let detail = try? await LoopStore.shared.withKit { try $0.habitDetail(habitId: row.id, historyDays: 60) }
            if let cell = detail?.row.days.first(where: { $0.date == p.date }) {
                sheet = .number(row: row, cell: cell)
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Toggle("Hide archived", isOn: Binding(get: { model.options.hideArchived },
                                                  set: { v in Task { await model.setHideArchived(v) } }))
            Toggle("Hide completed", isOn: Binding(get: { model.options.hideCompleted },
                                                   set: { v in Task { await model.setHideCompleted(v) } }))
            Menu("Sort") {
                sortItem("Manually", LoopKitListKt.SORT_MANUAL)
                sortItem("By name", LoopKitListKt.SORT_NAME)
                sortItem("By color", LoopKitListKt.SORT_COLOR)
                sortItem("By score", LoopKitListKt.SORT_SCORE)
                sortItem("By status", LoopKitListKt.SORT_STATUS)
            }
        } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
            .accessibilityLabel("Filter and sort")
    }

    @ViewBuilder private func sortItem(_ title: String, _ sort: Int32) -> some View {
        let current = model.options.sort == sort
        Button {
            Task { await model.sortBy(sort) }
        } label: {
            if current {
                Label(title, systemImage: model.options.isReversed ? "arrow.up" : "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func menuAction(_ row: HabitRow, _ action: HabitRowView.MenuAction) {
        switch action {
        case .edit, .reminder: path.append(.edit(row.id))
        case .color: sheet = .color(row: row)
        case .category: Task { sheet = .category(row: row, existing: await model.loadCategories()) }
        case .toggleArchive: Task { await model.setArchived(row, !row.isArchived) }
        case .delete: deleteTarget = row
        }
    }

    private func cellAction(_ row: HabitRow, _ cell: DayCell, longPress: Bool) {
        if row.isNumerical {
            // Measurable cells open the number sheet (value, notes, Skip, ?) on tap and long press.
            sheet = .number(row: row, cell: cell)
            return
        }
        switch HabitRowView.cellTapAction(shortToggle: model.settings.shortToggle, isLongPress: longPress) {
        case .toggle: Task { await model.toggle(row, cell) }
        case .openSheet: sheet = .entry(row: row, cell: cell)
        }
    }

    private var list: some View {
        List {
            if let first = model.habitRows.first {
                header(first.days)
                    .listRowSeparator(.hidden)
            }
            ForEach(model.rows, id: \.key) { item in
                if let title = item.categoryTitle {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .moveDisabled(true)
                        .onLongPressGesture {
                            renameText = title
                            renameOld = title
                        }
                } else if let row = item.habit {
                    HabitRowView(
                        row: row,
                        color: Palette.color(index: Int(row.colorIndex), in: palette),
                        questionMarks: model.questionMarks,
                        reversed: model.settings.reverseCheckmarks,
                        onOpen: { path.append(.detail(row.id)) },
                        onCellTap: { cell in cellAction(row, cell, longPress: false) },
                        onCellLongPress: { cell in cellAction(row, cell, longPress: true) },
                        onMenu: { menuAction(row, $0) })
                        .opacity(row.isArchived ? 0.5 : 1)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $model.searchQuery)
        .overlay {
            if model.loaded && model.rows.isEmpty {
                Text(model.searchQuery.isEmpty ? "No habits yet. Tap + to add one." : "No matching habits.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func header(_ days: [DayCell]) -> some View {
        HStack(spacing: 6) {
            Spacer()
            ForEach(Array(HabitRowView.displayDays(days, reversed: model.settings.reverseCheckmarks).enumerated()), id: \.offset) { _, d in
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
