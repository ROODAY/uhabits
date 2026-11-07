import SwiftUI

/// Grid of palette swatches. `palette` holds the facade's 0xRRGGBB values.
struct HabitColorPicker: View {
    @Binding var selected: Int
    let palette: [Int]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(palette.enumerated()), id: \.offset) { i, hex in
                Button { selected = i } label: {
                    Circle().fill(Palette.color(hex: hex))
                        .frame(width: 36, height: 36)
                        .overlay {
                            if i == selected {
                                Image(systemName: "checkmark").foregroundStyle(.white).bold()
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color \(i + 1)")
                .accessibilityAddTraits(i == selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
