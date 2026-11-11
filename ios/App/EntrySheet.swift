import SwiftUI
import LoopKit

/// Entry sheet for a yes/no habit's value on one day: Yes, No, optional Skip and ?, plus notes.
struct EntrySheet: View {
    let title: String
    let skipEnabled: Bool
    let questionMarksEnabled: Bool
    /// Called with the new value, or nil when the selection is unchanged (save the note only).
    let onSave: (Int32?, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int32
    @State private var notes: String
    private let initialSelection: Int32
    private let showSkip: Bool
    private let showUnknown: Bool

    init(title: String, current: Int32, notes: String, skipEnabled: Bool, questionMarksEnabled: Bool,
         onSave: @escaping (Int32?, String) -> Void) {
        self.title = title
        self.skipEnabled = skipEnabled
        self.questionMarksEnabled = questionMarksEnabled
        self.onSave = onSave
        // YES_AUTO (1) shows as Yes; an unchanged selection saves notes only, keeping the raw value.
        let sel: Int32 = current == 1 ? LoopKitKt.ENTRY_YES : current
        _selection = State(initialValue: sel)
        initialSelection = sel
        _notes = State(initialValue: notes)
        // A disabled option still shows when it is the current value.
        showSkip = skipEnabled || sel == LoopKitKt.ENTRY_SKIP
        showUnknown = questionMarksEnabled || sel == LoopKitKt.ENTRY_UNKNOWN
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Entry", selection: $selection) {
                        Text("Yes").tag(LoopKitKt.ENTRY_YES)
                        Text("No").tag(LoopKitKt.ENTRY_NO)
                        if showSkip { Text("Skip").tag(LoopKitKt.ENTRY_SKIP) }
                        if showUnknown { Text("?").tag(LoopKitKt.ENTRY_UNKNOWN) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(selection == initialSelection ? nil : selection, notes)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
