import SwiftUI
import LoopKit

/// Row context-menu actions and category rename. All writes go through the list model's mutate.
extension HabitListModel {
    private func boxed(_ ids: [Int64]) -> [KotlinLong] { ids.map { KotlinLong(value: $0) } }

    func setArchived(ids: [Int64], _ archived: Bool) async {
        let boxedIds = boxed(ids)
        await mutate { kit in
            if archived { try kit.archive(ids: boxedIds) } else { try kit.unarchive(ids: boxedIds) }
        }
    }

    func setCategory(ids: [Int64], _ category: String) async {
        let boxedIds = boxed(ids)
        await mutate { try $0.setCategory(ids: boxedIds, category: category) }
    }

    func setColor(ids: [Int64], _ index: Int) async {
        let boxedIds = boxed(ids)
        await mutate { try $0.setColor(ids: boxedIds, colorIndex: Int32(index)) }
    }

    func delete(ids: [Int64]) async {
        let boxedIds = boxed(ids)
        await mutate { try $0.deleteHabits(ids: boxedIds) }
    }

    func setArchived(_ row: HabitRow, _ archived: Bool) async { await setArchived(ids: [row.id], archived) }
    func setCategory(_ row: HabitRow, _ category: String) async { await setCategory(ids: [row.id], category) }
    func setColor(_ row: HabitRow, _ index: Int) async { await setColor(ids: [row.id], index) }
    func delete(_ row: HabitRow) async { await delete(ids: [row.id]) }

    func renameCategory(_ old: String, to new: String) async {
        await mutate { try $0.renameCategory(oldName: old, newName: new) }
    }

    /// Existing categories in the order the facade returns them.
    func loadCategories() async -> [String] {
        let result = (try? await store.withKit { try $0.categories() }) ?? []
        if !isActive { await store.close() }
        return result
    }
}

/// Color grid sheet for a single habit.
struct ColorSheet: View {
    let palette: [Int]
    @State var selected: Int
    let onPick: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                HabitColorPicker(selected: Binding(get: { selected }, set: { i in
                    selected = i
                    onPick(i)
                    dismiss()
                }), palette: palette).padding()
            }
            .navigationTitle("Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}
