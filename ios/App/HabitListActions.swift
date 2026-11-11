import SwiftUI
import LoopKit

/// Row context-menu actions and category rename. All writes go through the list model's mutate.
extension HabitListModel {
    private func boxed(_ id: Int64) -> [KotlinLong] { [KotlinLong(value: id)] }

    func setArchived(_ row: HabitRow, _ archived: Bool) async {
        let ids = boxed(row.id)
        await mutate { kit in
            if archived { try kit.archive(ids: ids) } else { try kit.unarchive(ids: ids) }
        }
    }

    func setCategory(_ row: HabitRow, _ category: String) async {
        let ids = boxed(row.id)
        await mutate { try $0.setCategory(ids: ids, category: category) }
    }

    func setColor(_ row: HabitRow, _ index: Int) async {
        let ids = boxed(row.id)
        await mutate { try $0.setColor(ids: ids, colorIndex: Int32(index)) }
    }

    func delete(_ row: HabitRow) async {
        let ids = boxed(row.id)
        await mutate { try $0.deleteHabits(ids: ids) }
    }

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
