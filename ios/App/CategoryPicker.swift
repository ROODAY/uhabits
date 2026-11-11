import SwiftUI

/// Sheet listing "None", the existing categories (in the order given) and a "New category…" field.
/// Reused by Select mode (Task 11).
struct CategoryPicker: View {
    let current: String
    let existing: [String]
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                pickRow("None", value: "")
                ForEach(existing, id: \.self) { name in
                    pickRow(name, value: name)
                }
                HStack {
                    TextField("New category…", text: $newName)
                        .submitLabel(.done)
                        .onSubmit(addNew)
                    Button("Add", action: addNew)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func pickRow(_ title: String, value: String) -> some View {
        Button {
            onPick(value)
            dismiss()
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if value == current { Image(systemName: "checkmark") }
            }
        }
    }

    private func addNew() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        onPick(name)
        dismiss()
    }
}
