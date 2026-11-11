import SwiftUI

/// Bottom-bar actions for select mode. All buttons are disabled while nothing is selected.
struct SelectModeBar: View {
    let count: Int
    let isUnarchive: Bool
    let onColor: () -> Void
    let onCategory: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button("Color", action: onColor).disabled(count == 0)
        Spacer()
        Button("Category", action: onCategory).disabled(count == 0)
        Spacer()
        Button(isUnarchive ? "Unarchive" : "Archive", action: onArchive).disabled(count == 0)
        Spacer()
        Button("Delete", role: .destructive, action: onDelete).disabled(count == 0)
    }
}
