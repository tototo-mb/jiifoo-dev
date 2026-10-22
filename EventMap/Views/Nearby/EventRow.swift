import SwiftUI
import CoreLocation

// 一覧の1件分のカード
struct EventRow: View {
    let event: Event
    let distance: CLLocationDistance?
    let isJoined: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 左側の色付きアイコン（ピンの色と同じ）
            Image(systemName: event.scale == .businessMode ? "building.2.fill" : "person.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(event.scale.color, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Label(event.placeName, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text(event.category)          // 投稿者名の代わりにカテゴリを表示
                        .lineLimit(1)
                    if isJoined {
                        Text("参加予定")
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)

            // 右上に距離
            if let distance {
                Text(formatDistance(distance))
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    EventRow(event: sampleEvents[0], distance: 450, isJoined: true)
        .padding()
        .background(Color(.systemGroupedBackground))
}
