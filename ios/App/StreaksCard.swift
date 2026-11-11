import SwiftUI
import LoopKit

struct StreaksCard: View {
    let currentStreak: Int
    let bestStreaks: [StreakDto]
    let color: Color

    var body: some View {
        let maxLen = max(1, bestStreaks.map { Int($0.length) }.max() ?? 1)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(currentStreak)").font(.system(size: 44, weight: .bold)).foregroundStyle(color)
                Text("current streak (days)").font(.subheadline).foregroundStyle(.secondary)
            }
            Text("Best streaks").font(.headline)
            if bestStreaks.isEmpty {
                Text("No streaks yet.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(bestStreaks.enumerated()), id: \.offset) { _, s in
                VStack(alignment: .leading, spacing: 2) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.15))
                            RoundedRectangle(cornerRadius: 4).fill(color)
                                .frame(width: max(24, geo.size.width * CGFloat(s.length) / CGFloat(maxLen)))
                            Text("\(s.length)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                .padding(.leading, 6)
                        }
                    }
                    .frame(height: 20)
                    Text("\(Self.short(s.start)) – \(Self.short(s.end))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    static func short(_ iso: String) -> String {
        guard let d = Calendar.current.date(from: DateKey.date(fromIso: iso)) else { return iso }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }
}
