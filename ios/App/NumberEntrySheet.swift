import SwiftUI

/// Entry sheet for a measurable habit's value on one day.
struct NumberEntrySheet: View {
    let title: String
    let unit: String
    let onSave: (Double, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var notes: String

    init(title: String, unit: String, value: Double, notes: String, onSave: @escaping (Double, String) -> Void) {
        self.title = title
        self.unit = unit
        self.onSave = onSave
        _text = State(initialValue: CheckmarkCell.format(value))
        _notes = State(initialValue: notes)
    }

    private var parsed: Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(unit.isEmpty ? "Value" : "Value (\(unit))") {
                    TextField("0", text: $text).keyboardType(.decimalPad)
                }
                Section("Notes") {
                    TextEditor(text: $notes).frame(minHeight: 80)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let v = parsed {
                            onSave(v, notes)
                            dismiss()
                        }
                    }.disabled(parsed == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Notes editor opened by long-pressing a cell.
struct NotesSheet: View {
    let title: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var notes: String

    init(title: String, notes: String, onSave: @escaping (String) -> Void) {
        self.title = title
        self.onSave = onSave
        _notes = State(initialValue: notes)
    }

    var body: some View {
        NavigationStack {
            Form { TextEditor(text: $notes).frame(minHeight: 120) }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave(notes)
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium])
    }
}
