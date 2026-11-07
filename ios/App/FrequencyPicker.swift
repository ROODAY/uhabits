import SwiftUI

/// Frequency presets, mirroring Android's frequency picker.
/// Mapping: every day = 1/1, every week = 1/7, N per week = N/7, N per month = N/30, every N days = 1/N.
enum FrequencyPreset: Equatable {
    case everyDay
    case everyWeek
    case timesPerWeek(Int)
    case timesPerMonth(Int)
    case everyNDays(Int)
    /// A numerator/denominator that fits no preset. Shown and saved unchanged.
    case custom(Int, Int)

    var numDen: (Int, Int) {
        switch self {
        case .everyDay: return (1, 1)
        case .everyWeek: return (1, 7)
        case .timesPerWeek(let n): return (n, 7)
        case .timesPerMonth(let n): return (n, 30)
        case .everyNDays(let n): return (1, n)
        case .custom(let n, let d): return (n, d)
        }
    }

    /// Classifies stored numerator/denominator into a preset, like Android's formatFrequency.
    static func from(numerator n: Int, denominator d: Int) -> FrequencyPreset {
        switch (n, d) {
        case (1, 1): return .everyDay
        case (1, 7): return .everyWeek
        case (_, 30) where n >= 1: return .timesPerMonth(n)
        case (1, _) where d > 1: return .everyNDays(d)
        case (_, 7) where n >= 1: return .timesPerWeek(n)
        default: return .custom(n, d)
        }
    }

    var label: String {
        switch self {
        case .everyDay: return "Every day"
        case .everyWeek: return "Every week"
        case .timesPerWeek(let n): return "\(n) times per week"
        case .timesPerMonth(let n): return "\(n) times per month"
        case .everyNDays(let n): return "Every \(n) days"
        case .custom(let n, let d): return "Custom: \(n) times in \(d) days"
        }
    }

    enum Kind: Hashable, CaseIterable {
        case everyDay, everyWeek, timesPerWeek, timesPerMonth, everyNDays, custom
        var title: String {
            switch self {
            case .everyDay: return "Every day"
            case .everyWeek: return "Every week"
            case .timesPerWeek: return "N times per week"
            case .timesPerMonth: return "N times per month"
            case .everyNDays: return "Every N days"
            case .custom: return "Custom"
            }
        }
    }

    var kind: Kind {
        switch self {
        case .everyDay: return .everyDay
        case .everyWeek: return .everyWeek
        case .timesPerWeek: return .timesPerWeek
        case .timesPerMonth: return .timesPerMonth
        case .everyNDays: return .everyNDays
        case .custom: return .custom
        }
    }

    /// The N parameter, for kinds that have one.
    var amount: Int? {
        switch self {
        case .timesPerWeek(let n), .timesPerMonth(let n), .everyNDays(let n): return n
        default: return nil
        }
    }

    var amountRange: ClosedRange<Int> {
        switch self {
        case .timesPerWeek: return 1...7
        case .timesPerMonth: return 1...30
        default: return 2...365
        }
    }

    /// Switches to another kind, keeping N where it makes sense.
    func switched(to kind: Kind) -> FrequencyPreset {
        let n = amount ?? 2
        switch kind {
        case .everyDay: return .everyDay
        case .everyWeek: return .everyWeek
        case .timesPerWeek: return .timesPerWeek(min(max(n, 1), 7))
        case .timesPerMonth: return .timesPerMonth(min(max(n, 1), 30))
        case .everyNDays: return .everyNDays(max(n, 2))
        case .custom: return self
        }
    }
}

struct FrequencyPicker: View {
    @Binding var preset: FrequencyPreset

    private var kinds: [FrequencyPreset.Kind] {
        FrequencyPreset.Kind.allCases.filter { $0 != .custom || preset.kind == .custom }
    }

    var body: some View {
        Picker("Frequency", selection: Binding(get: { preset.kind },
                                               set: { preset = preset.switched(to: $0) })) {
            ForEach(kinds, id: \.self) { Text($0.title).tag($0) }
        }
        if let n = preset.amount {
            Stepper(value: Binding(get: { n }, set: { preset = amountUpdated($0) }),
                    in: preset.amountRange) {
                Text(preset.label)
            }
        } else if case .custom = preset {
            Text(preset.label).foregroundStyle(.secondary)
        }
    }

    private func amountUpdated(_ v: Int) -> FrequencyPreset {
        switch preset {
        case .timesPerWeek: return .timesPerWeek(v)
        case .timesPerMonth: return .timesPerMonth(v)
        default: return .everyNDays(v)
        }
    }
}
