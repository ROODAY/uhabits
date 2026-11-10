import SwiftUI
import LoopKit

/// Entry sheet for a measurable habit's value on one day.
struct NumberEntrySheet: View {
    let title: String
    let unit: String
    let skipEnabled: Bool
    let questionMarksEnabled: Bool
    let onSave: (Double, String) -> Void
    /// Sets SKIP or UNKNOWN, keeping the notes currently typed.
    let onSetSpecial: (Int32, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var notes: String

    init(title: String, unit: String, value: Double, notes: String,
         skipEnabled: Bool = false, questionMarksEnabled: Bool = false,
         onSave: @escaping (Double, String) -> Void,
         onSetSpecial: @escaping (Int32, String) -> Void = { _, _ in }) {
        self.title = title
        self.unit = unit
        self.skipEnabled = skipEnabled
        self.questionMarksEnabled = questionMarksEnabled
        self.onSave = onSave
        self.onSetSpecial = onSetSpecial
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
                if skipEnabled || questionMarksEnabled {
                    Section {
                        HStack {
                            if skipEnabled {
                                Button("Skip") { onSetSpecial(LoopKitKt.ENTRY_SKIP, notes); dismiss() }
                                    .buttonStyle(.bordered)
                            }
                            if questionMarksEnabled {
                                Button("?") { onSetSpecial(LoopKitKt.ENTRY_UNKNOWN, notes); dismiss() }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
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
